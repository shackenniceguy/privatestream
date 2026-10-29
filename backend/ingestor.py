import os
import sys
import json
import asyncio
import logging
import subprocess
from pathlib import Path
from typing import Optional, List, Dict, Any
import datetime

import qbittorrentapi
from aiogram import Bot, Dispatcher, types, F
from aiogram.filters import Command
from aiogram.enums import ParseMode
from sqlalchemy import select, update
from sqlalchemy.ext.asyncio import AsyncSession

from database import AsyncSessionLocal, init_db
from models import MediaItem, SubtitleTrack, TorrentJob
from tmdb import parse_filename, TmdbClient

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
)
logger = logging.getLogger("privatestream.ingestor")

# Environment configuration
LOCAL_DOWNLOAD_DIR = Path(os.getenv("LOCAL_DOWNLOAD_DIR", "/data/local_downloads"))
REMOTE_MEDIA_DIR = os.getenv("REMOTE_MEDIA_DIR", "/mnt/gdrive/Media")
RCLONE_REMOTE_NAME = os.getenv("RCLONE_REMOTE_NAME", "gdrive")
QBITTORRENT_HOST = os.getenv("QBITTORRENT_HOST", "qbittorrent-nox")
QBITTORRENT_PORT = int(os.getenv("QBITTORRENT_PORT", "8080"))
QBITTORRENT_USER = os.getenv("QBITTORRENT_USER", "admin")
QBITTORRENT_PASSWORD = os.getenv("QBITTORRENT_PASSWORD", "adminadmin")
TELEGRAM_BOT_TOKEN = os.getenv("TELEGRAM_BOT_TOKEN", "")
ALLOWED_USER_ID_RAW = os.getenv("ALLOWED_USER_ID", "")
ALLOWED_USER_IDS = [
    int(uid.strip()) for uid in ALLOWED_USER_ID_RAW.split(",") if uid.strip().isdigit()
]

VIDEO_EXTENSIONS = {".mkv", ".mp4", ".avi", ".mov", ".webm", ".ts", ".m4v"}

# Initialize TMDB client
tmdb_client = TmdbClient()

# Initialize Telegram Bot & Dispatcher
bot: Optional[Bot] = None
dp: Optional[Dispatcher] = None
if TELEGRAM_BOT_TOKEN and TELEGRAM_BOT_TOKEN != "your_telegram_bot_token_here":
    bot = Bot(token=TELEGRAM_BOT_TOKEN)
    dp = Dispatcher()


def is_allowed_user(user_id: int) -> bool:
    if not ALLOWED_USER_IDS:
        return True
    return user_id in ALLOWED_USER_IDS


def get_qbittorrent_client() -> qbittorrentapi.Client:
    """Connects to the qBittorrent WebUI."""
    client = qbittorrentapi.Client(
        host=QBITTORRENT_HOST,
        port=QBITTORRENT_PORT,
        username=QBITTORRENT_USER,
        password=QBITTORRENT_PASSWORD,
    )
    return client


# ------------------------------------------------------------------------------
# Video Inspection & Post-Processing Helpers (ffprobe & ffmpeg)
# ------------------------------------------------------------------------------

async def inspect_video_file(file_path: Path) -> Dict[str, Any]:
    """
    Runs ffprobe once on the local video file to extract duration, resolution,
    display aspect ratio (DAR), codecs, audio channels, and subtitle streams.
    """
    cmd = [
        "ffprobe",
        "-v", "quiet",
        "-print_format", "json",
        "-show_format",
        "-show_streams",
        str(file_path),
    ]

    proc = await asyncio.create_subprocess_exec(
        *cmd,
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.PIPE,
    )
    stdout, stderr = await proc.communicate()

    if proc.returncode != 0:
        logger.error(f"ffprobe failed for {file_path}: {stderr.decode()}")
        return {
            "duration": 0.0,
            "width": 1920,
            "height": 1080,
            "aspect_ratio": "16:9",
            "aspect_ratio_category": "horizontal",
            "video_codec": "h264",
            "audio_codec": "aac",
            "audio_channels": 2,
            "subtitle_streams": [],
        }

    probe_data = json.loads(stdout.decode())
    streams = probe_data.get("streams", [])
    format_info = probe_data.get("format", {})

    duration = float(format_info.get("duration", 0.0))
    video_stream = next((s for s in streams if s.get("codec_type") == "video"), None)
    audio_stream = next((s for s in streams if s.get("codec_type") == "audio"), None)
    subtitle_streams = [s for s in streams if s.get("codec_type") == "subtitle"]

    width = 1920
    height = 1080
    dar_str = "16:9"
    category = "horizontal"
    v_codec = "h264"
    a_codec = "aac"
    a_channels = 2

    if video_stream:
        width = int(video_stream.get("width", 1920))
        height = int(video_stream.get("height", 1080))
        v_codec = video_stream.get("codec_name", "h264")

        # Determine display aspect ratio
        raw_dar = video_stream.get("display_aspect_ratio")
        ratio_val = width / height if height > 0 else 1.777

        if raw_dar and ":" in raw_dar:
            dar_str = raw_dar
        elif abs(ratio_val - 1.777) < 0.05:
            dar_str = "16:9"
        elif abs(ratio_val - 0.562) < 0.05:
            dar_str = "9:16"
        elif abs(ratio_val - 1.333) < 0.05:
            dar_str = "4:3"
        elif abs(ratio_val - 0.75) < 0.05:
            dar_str = "3:4"
        elif abs(ratio_val - 2.39) < 0.1:
            dar_str = "21:9"
        else:
            dar_str = f"{round(ratio_val, 2)}:1"

        if ratio_val < 0.8:
            category = "vertical"
        elif 0.8 <= ratio_val <= 1.2:
            category = "square"
        elif 1.2 < ratio_val < 2.0:
            category = "horizontal"
        else:
            category = "ultrawide"

    if audio_stream:
        a_codec = audio_stream.get("codec_name", "aac")
        a_channels = int(audio_stream.get("channels", 2))

    return {
        "duration": duration,
        "width": width,
        "height": height,
        "aspect_ratio": dar_str,
        "aspect_ratio_category": category,
        "video_codec": v_codec,
        "audio_codec": a_codec,
        "audio_channels": a_channels,
        "subtitle_streams": subtitle_streams,
    }


async def extract_subtitles_to_vtt(video_path: Path, subtitle_streams: List[Dict[str, Any]]) -> List[Dict[str, str]]:
    """
    Extracts embedded subtitle tracks from video to web-ready .vtt files.
    """
    extracted_tracks = []
    base_name = video_path.stem

    for idx, sub in enumerate(subtitle_streams):
        sub_index = sub.get("index", idx)
        tags = sub.get("tags", {})
        lang = tags.get("language", f"sub{idx}")
        title = tags.get("title", f"Track {idx + 1} ({lang.upper()})")

        vtt_output_path = video_path.parent / f"{base_name}_{lang}_{idx}.vtt"

        cmd = [
            "ffmpeg",
            "-y",
            "-i", str(video_path),
            "-map", f"0:{sub_index}",
            str(vtt_output_path),
        ]

        proc = await asyncio.create_subprocess_exec(
            *cmd,
            stdout=asyncio.subprocess.DEVNULL,
            stderr=asyncio.subprocess.DEVNULL,
        )
        await proc.wait()

        if vtt_output_path.exists() and vtt_output_path.stat().st_size > 0:
            extracted_tracks.append({
                "language": lang,
                "title": title,
                "vtt_path": str(vtt_output_path),
            })
            logger.info(f"Extracted subtitle [{lang}] to {vtt_output_path}")

    return extracted_tracks


async def upload_file_to_gdrive(local_path: Path, remote_folder: str) -> bool:
    """
    Sequentially moves completed file to Google Drive using rclone with Anti-Ban rate limiting:
    --drive-chunk-size 128M --tpslimit 4 --transfers 1 --checkers 2
    """
    target_remote = f"{RCLONE_REMOTE_NAME}:{remote_folder}"
    cmd = [
        "rclone", "move",
        str(local_path),
        target_remote,
        "--drive-chunk-size", "128M",
        "--tpslimit", "4",
        "--transfers", "1",
        "--checkers", "2",
        "--stats", "10s",
        "--log-level", "INFO",
    ]

    logger.info(f"Starting sequential Anti-Ban upload of {local_path.name} to {target_remote}...")
    proc = await asyncio.create_subprocess_exec(*cmd)
    ret = await proc.wait()

    if ret == 0:
        logger.info(f"Successfully uploaded {local_path.name} to {target_remote}")
        return True
    else:
        logger.error(f"rclone move failed for {local_path} with exit code {ret}")
        return False


# ------------------------------------------------------------------------------
# Ingestion & Post-Processing Pipeline
# ------------------------------------------------------------------------------

async def process_completed_torrent(torrent_hash: str, torrent_name: str, save_path: str):
    """
    Runs the automated post-processing pipeline for 100% completed torrent:
    1. Scan video files locally.
    2. ffprobe single-pass metadata & DAR extraction.
    3. Extract embedded subtitles to .vtt.
    4. Fetch TMDB metadata & artwork.
    5. Anti-ban sequential upload to Google Drive.
    6. Persist metadata in database for instant zero-API browsing.
    """
    logger.info(f"Starting post-processing pipeline for: {torrent_name} [{torrent_hash}]")

    async with AsyncSessionLocal() as session:
        # Mark TorrentJob as post_processing
        await session.execute(
            update(TorrentJob)
            .where(TorrentJob.hash == torrent_hash)
            .values(state="post_processing")
        )
        await session.commit()

    content_dir = Path(save_path)
    if (content_dir / torrent_name).exists():
        target_path = content_dir / torrent_name
    else:
        target_path = content_dir

    # Find video files
    video_files: List[Path] = []
    if target_path.is_file() and target_path.suffix.lower() in VIDEO_EXTENSIONS:
        video_files.append(target_path)
    elif target_path.is_dir():
        for root, _, files in os.walk(target_path):
            for f in files:
                p = Path(root) / f
                if p.suffix.lower() in VIDEO_EXTENSIONS:
                    video_files.append(p)

    if not video_files:
        logger.warning(f"No playable video files found in {target_path}")
        async with AsyncSessionLocal() as session:
            await session.execute(
                update(TorrentJob)
                .where(TorrentJob.hash == torrent_hash)
                .values(state="completed", error_message="No video files found")
            )
            await session.commit()
        return

    # Process each discovered video file
    for vid in video_files:
        logger.info(f"Inspecting video: {vid.name}")
        file_size = vid.stat().st_size
        probe = await inspect_video_file(vid)

        # Extract embedded subtitles
        extracted_subs = await extract_subtitles_to_vtt(vid, probe["subtitle_streams"])

        # Parse filename & fetch TMDB metadata
        parsed = parse_filename(vid.name)
        if not parsed.get("year") and not parsed.get("season"):
            # Try parsing parent folder name
            parent_parsed = parse_filename(torrent_name)
            if parent_parsed.get("title"):
                parsed["title"] = parent_parsed["title"]
            if parent_parsed.get("year"):
                parsed["year"] = parent_parsed["year"]

        metadata = await tmdb_client.fetch_metadata(parsed)

        # Move to Google Drive sequentially
        subfolder = "Series" if metadata.get("media_type") == "series" else "Movies"
        remote_dest = f"Media/{subfolder}"

        async with AsyncSessionLocal() as session:
            await session.execute(
                update(TorrentJob)
                .where(TorrentJob.hash == torrent_hash)
                .values(state="uploading")
            )
            await session.commit()

        # Upload VTT subtitles
        uploaded_subs = []
        for sub in extracted_subs:
            vtt_p = Path(sub["vtt_path"])
            upload_success = await upload_file_to_gdrive(vtt_p, f"{remote_dest}/Subtitles")
            remote_vtt = f"{REMOTE_MEDIA_DIR}/{subfolder}/Subtitles/{vtt_p.name}"
            uploaded_subs.append({
                "language": sub["language"],
                "title": sub["title"],
                "vtt_path": remote_vtt if upload_success else sub["vtt_path"],
            })

        # Upload main video file
        upload_success = await upload_file_to_gdrive(vid, remote_dest)
        final_video_path = f"{REMOTE_MEDIA_DIR}/{subfolder}/{vid.name}" if upload_success else str(vid)

        # Register in Database
        async with AsyncSessionLocal() as session:
            media_item = MediaItem(
                title=metadata["title"],
                original_title=metadata.get("original_title"),
                overview=metadata.get("overview"),
                media_type=metadata["media_type"],
                year=metadata.get("year"),
                season=metadata.get("season"),
                episode=metadata.get("episode"),
                file_path=final_video_path,
                file_size_bytes=file_size,
                duration_seconds=probe["duration"],
                width=probe["width"],
                height=probe["height"],
                aspect_ratio=probe["aspect_ratio"],
                aspect_ratio_category=probe["aspect_ratio_category"],
                video_codec=probe["video_codec"],
                audio_codec=probe["audio_codec"],
                audio_channels=probe["audio_channels"],
                poster_url=metadata["poster_url"],
                backdrop_url=metadata["backdrop_url"],
                tmdb_id=metadata.get("tmdb_id"),
                vote_average=metadata.get("vote_average", 0.0),
                genres=metadata.get("genres", ""),
            )
            session.add(media_item)
            await session.flush()

            for s_info in uploaded_subs:
                sub_track = SubtitleTrack(
                    media_id=media_item.id,
                    language=s_info["language"],
                    title=s_info["title"],
                    vtt_path=s_info["vtt_path"],
                    is_default=(s_info["language"] in {"rus", "ru", "und"}),
                )
                session.add(sub_track)

            # Mark torrent job as completed
            await session.execute(
                update(TorrentJob)
                .where(TorrentJob.hash == torrent_hash)
                .values(
                    state="completed",
                    progress=1.0,
                    completed_at=datetime.datetime.utcnow(),
                )
            )
            await session.commit()
            logger.info(f"Registered '{media_item.title}' in database (ID: {media_item.id})")

            # Notify Telegram user
            if bot and ALLOWED_USER_IDS:
                for uid in ALLOWED_USER_IDS:
                    try:
                        msg = (
                            f"🎬 <b>Added to PrivateStream!</b>\n\n"
                            f"<b>Title:</b> {media_item.title} ({media_item.year or 'N/A'})\n"
                            f"<b>Type:</b> {media_item.media_type.upper()}\n"
                            f"<b>Aspect Ratio:</b> {media_item.aspect_ratio} ({media_item.aspect_ratio_category})\n"
                            f"<b>Resolution:</b> {media_item.width}x{media_item.height}\n"
                            f"<b>Subtitles:</b> {len(uploaded_subs)} tracks extracted\n"
                            f"<b>Cloud Status:</b> Ingested & Stream Ready 🍿"
                        )
                        await bot.send_message(chat_id=uid, text=msg, parse_mode=ParseMode.HTML)
                    except Exception as e:
                        logger.warning(f"Failed to send Telegram notification to {uid}: {e}")

    # Remove torrent from qBittorrent to free local SSD space
    try:
        qbt = get_qbittorrent_client()
        qbt.auth_log_in()
        qbt.torrents_delete(torrent_hashes=torrent_hash, delete_files=True)
        logger.info(f"Removed torrent {torrent_hash} from qBittorrent.")
    except Exception as e:
        logger.error(f"Error removing torrent from qBittorrent: {e}")


async def qbittorrent_monitor_loop():
    """
    Periodically checks qBittorrent for torrent download progress and triggers
    post-processing once download reaches 100%.
    """
    logger.info("Starting qBittorrent monitoring loop...")
    while True:
        try:
            qbt = get_qbittorrent_client()
            qbt.auth_log_in()
            torrents = qbt.torrents_info()

            async with AsyncSessionLocal() as session:
                for t in torrents:
                    thash = t.hash.lower()
                    progress = float(t.progress)
                    state = t.state
                    name = t.name
                    d_speed = t.dlspeed
                    u_speed = t.upspeed
                    eta = t.eta

                    # Update or insert TorrentJob in DB
                    res = await session.execute(select(TorrentJob).where(TorrentJob.hash == thash))
                    job = res.scalar_one_or_none()

                    if not job:
                        job = TorrentJob(
                            hash=thash,
                            name=name,
                            state=state,
                            progress=progress,
                            download_speed=d_speed,
                            upload_speed=u_speed,
                            eta_seconds=eta,
                        )
                        session.add(job)
                        await session.commit()
                    else:
                        if job.state not in {"post_processing", "uploading", "completed"}:
                            job.progress = progress
                            job.state = state
                            job.download_speed = d_speed
                            job.upload_speed = u_speed
                            job.eta_seconds = eta
                            await session.commit()

                    # Trigger post-processing on completion
                    if progress >= 1.0 and job.state in {
                        "downloading", "queuedUP", "uploading", "stalledUP", "pausedUP"
                    }:
                        # Check that files exist in local storage
                        asyncio.create_task(
                            process_completed_torrent(thash, name, t.save_path)
                        )

        except Exception as e:
            logger.debug(f"qBittorrent loop tick notice: {e}")

        await asyncio.sleep(3)


# ------------------------------------------------------------------------------
# Telegram Bot Handlers (aiogram 3.x)
# ------------------------------------------------------------------------------

if dp:
    @dp.message(Command("start"))
    async def cmd_start(message: types.Message):
        if not is_allowed_user(message.from_user.id):
            await message.reply("⛔ Access denied. Unauthorized user.")
            return

        welcome_text = (
            "🎥 <b>Welcome to PrivateStream Ingestion Bot</b>\n\n"
            "Send me any <b>.torrent file</b> or <b>magnet:?</b> link to initiate ingestion.\n\n"
            "Commands:\n"
            "/status - View active downloads and queue\n"
            "/help - Usage guidance"
        )
        await message.reply(welcome_text, parse_mode=ParseMode.HTML)


    @dp.message(Command("status"))
    async def cmd_status(message: types.Message):
        if not is_allowed_user(message.from_user.id):
            return

        async with AsyncSessionLocal() as session:
            res = await session.execute(
                select(TorrentJob).order_by(TorrentJob.added_at.desc()).limit(10)
            )
            jobs = res.scalars().all()

        if not jobs:
            await message.reply("ℹ️ No torrent jobs currently in queue.")
            return

        lines = ["<b>Active & Recent Torrents:</b>\n"]
        for j in jobs:
            pct = int(j.progress * 100)
            spd = f"{round(j.download_speed / (1024 * 1024), 1)} MB/s" if j.download_speed > 0 else "0 KB/s"
            lines.append(
                f"• <b>{j.name[:35]}</b>\n"
                f"  Status: <code>{j.state}</code> | {pct}% | {spd}\n"
            )

        await message.reply("\n".join(lines), parse_mode=ParseMode.HTML)


    @dp.message(F.text.startswith("magnet:?"))
    async def handle_magnet(message: types.Message):
        if not is_allowed_user(message.from_user.id):
            await message.reply("⛔ Access denied.")
            return

        magnet_link = message.text.strip()
        status_msg = await message.reply("⏳ Staging magnet link into local downloader...")

        try:
            qbt = get_qbittorrent_client()
            qbt.auth_log_in()
            LOCAL_DOWNLOAD_DIR.mkdir(parents=True, exist_ok=True)
            qbt.torrents_add(
                urls=magnet_link,
                save_path=str(LOCAL_DOWNLOAD_DIR),
                category="privatestream",
            )
            await status_msg.edit_text(
                "✅ <b>Magnet link added!</b>\n"
                "Local SSD staging engaged. Post-processing will trigger upon 100% completion.",
                parse_mode=ParseMode.HTML,
            )
        except Exception as e:
            logger.error(f"Failed to add magnet: {e}")
            await status_msg.edit_text(f"❌ Failed to add magnet link:\n<code>{e}</code>", parse_mode=ParseMode.HTML)


    @dp.message(F.document)
    async def handle_torrent_document(message: types.Message):
        if not is_allowed_user(message.from_user.id):
            await message.reply("⛔ Access denied.")
            return

        doc = message.document
        if not doc.file_name.lower().endswith(".torrent"):
            await message.reply("⚠️ Please send a valid <code>.torrent</code> file.", parse_mode=ParseMode.HTML)
            return

        status_msg = await message.reply("📥 Downloading .torrent metadata file...")
        staged_dir = LOCAL_DOWNLOAD_DIR / "staged_torrents"
        staged_dir.mkdir(parents=True, exist_ok=True)
        local_torrent_path = staged_dir / doc.file_name

        try:
            file = await bot.get_file(doc.file_id)
            await bot.download_file(file.file_path, destination=local_torrent_path)

            qbt = get_qbittorrent_client()
            qbt.auth_log_in()
            with open(local_torrent_path, "rb") as f:
                qbt.torrents_add(
                    torrent_files=f,
                    save_path=str(LOCAL_DOWNLOAD_DIR),
                    category="privatestream",
                )

            await status_msg.edit_text(
                f"✅ <b>Torrent file '{doc.file_name}' added!</b>\n"
                f"Downloading strictly to local SSD storage before Anti-Ban cloud sync.",
                parse_mode=ParseMode.HTML,
            )
        except Exception as e:
            logger.error(f"Failed to process torrent file: {e}")
            await status_msg.edit_text(f"❌ Failed to add torrent:\n<code>{e}</code>", parse_mode=ParseMode.HTML)


# ------------------------------------------------------------------------------
# Entrypoint Runner
# ------------------------------------------------------------------------------

async def main():
    logger.info("Initializing PrivateStream Ingestor...")
    await init_db()
    LOCAL_DOWNLOAD_DIR.mkdir(parents=True, exist_ok=True)

    tasks = [asyncio.create_task(qbittorrent_monitor_loop())]

    if bot and dp:
        logger.info("Starting Telegram Bot listener...")
        tasks.append(asyncio.create_task(dp.start_polling(bot)))
    else:
        logger.info("Telegram Bot token not configured or placeholder detected; skipping Bot polling.")

    await asyncio.gather(*tasks)


if __name__ == "__main__":
    try:
        asyncio.run(main())
    except (KeyboardInterrupt, SystemExit):
        logger.info("Ingestor stopped cleanly.")
