import os
import sys
import asyncio
import subprocess
from pathlib import Path
import datetime

from database import engine, AsyncSessionLocal, init_db
from models import MediaItem, SubtitleTrack, TorrentJob, WatchProgress

SAMPLE_DIR = Path("./sample_media")


def generate_sample_video(filename: str, width: int, height: int, duration_sec: int = 15, dar: str = "16:9"):
    SAMPLE_DIR.mkdir(parents=True, exist_ok=True)
    out_path = SAMPLE_DIR / filename
    if out_path.exists():
        return out_path

    # Generate synthetic video with visual test pattern and beep tone
    cmd = [
        "ffmpeg",
        "-y",
        "-f", "lavfi",
        "-i", f"testsrc=size={width}x{height}:rate=30",
        "-f", "lavfi",
        "-i", "sine=frequency=1000:beep_factor=4:sample_rate=48000",
        "-t", str(duration_sec),
        "-c:v", "libx264",
        "-preset", "ultrafast",
        "-pix_fmt", "yuv420p",
        "-c:a", "aac",
        "-b:a", "128k",
        "-aspect", dar,
        "-movflags", "+faststart",
        str(out_path),
    ]

    try:
        subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True)
        print(f"Generated test video: {out_path} ({width}x{height}, DAR {dar})")
    except Exception as e:
        print(f"Notice: ffmpeg not available or error generating {filename}: {e}")
        # Create dummy file if ffmpeg is not installed
        out_path.write_bytes(b"\x00" * 1024)

    return out_path


def generate_sample_vtt(filename: str, title: str):
    SAMPLE_DIR.mkdir(parents=True, exist_ok=True)
    vtt_path = SAMPLE_DIR / filename
    if vtt_path.exists():
        return vtt_path

    content = f"""WEBVTT - {title}

00:00:01.000 --> 00:00:05.000
PrivateStream: Personal Cloud Streaming Engine Active.

00:00:06.000 --> 00:00:10.000
Universal Orientation & Aspect-Ratio Engine Verified.

00:00:11.000 --> 00:00:14.500
Offline Mode & Resumable Downloads Enabled.
"""
    vtt_path.write_text(content, encoding="utf-8")
    return vtt_path


async def seed_database():
    print("Initializing Database schema...")
    await init_db()

    # Generate test playable files
    v1 = generate_sample_video("cyberpunk_neon_16x9.mp4", 1920, 1080, duration_sec=30, dar="16:9")
    v2 = generate_sample_video("mobile_vertical_cinema_9x16.mp4", 1080, 1920, duration_sec=25, dar="9:16")
    v3 = generate_sample_video("sci_fi_ultrawide_21x9.mp4", 2560, 1080, duration_sec=35, dar="21:9")
    v4 = generate_sample_video("classic_retro_4x3.mp4", 1440, 1080, duration_sec=20, dar="4:3")

    sub_rus = generate_sample_vtt("cyberpunk_rus.vtt", "Russian Subtitles")
    sub_eng = generate_sample_vtt("cyberpunk_eng.vtt", "English SDH")

    async with AsyncSessionLocal() as session:
        # 1. 16:9 Widescreen Movie
        item1 = MediaItem(
            title="Cyberpunk 2099: Neon Horizon",
            original_title="Cyberpunk 2099",
            overview="In a dystopian megalopolis, a rogue netrunner and an ex-corporate operative uncover a neural streaming conspiracy that threatens physical and virtual reality.",
            media_type="movie",
            year=2026,
            file_path=str(v1.resolve()),
            file_size_bytes=v1.stat().st_size if v1.exists() else 52428800,
            duration_seconds=120.0,
            width=1920,
            height=1080,
            aspect_ratio="16:9",
            aspect_ratio_category="horizontal",
            video_codec="h264",
            audio_codec="aac",
            audio_channels=6,
            poster_url="https://images.unsplash.com/photo-1542751371-adc38448a05e?q=80&w=800&auto=format&fit=crop",
            backdrop_url="https://images.unsplash.com/photo-1578632767115-351597cf2477?q=80&w=1920&auto=format&fit=crop",
            vote_average=8.9,
            genres="Sci-Fi, Cyberpunk, Action",
        )
        session.add(item1)
        await session.flush()

        # Add Subtitles for item 1
        session.add(SubtitleTrack(media_id=item1.id, language="rus", title="Russian Full", vtt_path=str(sub_rus.resolve()), is_default=True))
        session.add(SubtitleTrack(media_id=item1.id, language="eng", title="English SDH", vtt_path=str(sub_eng.resolve()), is_default=False))

        # Add initial Watch Progress for Continue Watching row
        session.add(WatchProgress(user_id="primary_user", media_id=item1.id, position_seconds=42.0, duration_seconds=120.0, completed=False))

        # 2. 9:16 Vertical Video (Native Mobile Fullscreen)
        item2 = MediaItem(
            title="Tokyo Nights: Vertical Cinema (9:16)",
            original_title="Tokyo Nights Mobile",
            overview="A cinematic vertical film captured entirely in native 9:16 portrait format across the neon rain-slicked alleyways of Shinjuku.",
            media_type="movie",
            year=2026,
            file_path=str(v2.resolve()),
            file_size_bytes=v2.stat().st_size if v2.exists() else 35428800,
            duration_seconds=95.0,
            width=1080,
            height=1920,
            aspect_ratio="9:16",
            aspect_ratio_category="vertical",
            video_codec="h264",
            audio_codec="aac",
            audio_channels=2,
            poster_url="https://images.unsplash.com/photo-1503899036084-c55cdd92da26?q=80&w=800&auto=format&fit=crop",
            backdrop_url="https://images.unsplash.com/photo-1503899036084-c55cdd92da26?q=80&w=1920&auto=format&fit=crop",
            vote_average=9.2,
            genres="Vertical, Documentary, Visual Arts",
        )
        session.add(item2)

        # 3. 21:9 Ultrawide Cinema Movie
        item3 = MediaItem(
            title="Interstellar Odyssey",
            original_title="Interstellar Odyssey",
            overview="An exploration ship voyages into the unexplored outer rim of the galaxy, seeking a new habitable colony as the solar flares intensify.",
            media_type="movie",
            year=2025,
            file_path=str(v3.resolve()),
            file_size_bytes=v3.stat().st_size if v3.exists() else 85428800,
            duration_seconds=180.0,
            width=2560,
            height=1080,
            aspect_ratio="21:9",
            aspect_ratio_category="ultrawide",
            video_codec="h264",
            audio_codec="aac",
            audio_channels=6,
            poster_url="https://images.unsplash.com/photo-1451187580459-43490279c0fa?q=80&w=800&auto=format&fit=crop",
            backdrop_url="https://images.unsplash.com/photo-1446776811953-b23d57bd21aa?q=80&w=1920&auto=format&fit=crop",
            vote_average=8.6,
            genres="Adventure, Sci-Fi, Drama",
        )
        session.add(item3)

        # 4. TV Series Episode (S01E01)
        item4 = MediaItem(
            title="Silicon Grid (S01E01)",
            original_title="Silicon Grid - Episode 1",
            overview="When an autonomous AI agent develops unexpected self-awareness, an elite incident response squad must determine if it is a threat or humanity's last hope.",
            media_type="series",
            year=2026,
            season=1,
            episode=1,
            file_path=str(v1.resolve()),
            file_size_bytes=v1.stat().st_size if v1.exists() else 42428800,
            duration_seconds=150.0,
            width=1920,
            height=1080,
            aspect_ratio="16:9",
            aspect_ratio_category="horizontal",
            video_codec="h264",
            audio_codec="aac",
            audio_channels=2,
            poster_url="https://images.unsplash.com/photo-1518770660439-4636190af475?q=80&w=800&auto=format&fit=crop",
            backdrop_url="https://images.unsplash.com/photo-1526374965328-7f61d4dc18c5?q=80&w=1920&auto=format&fit=crop",
            vote_average=8.8,
            genres="Drama, Tech Thriller",
        )
        session.add(item4)

        # 5. Live Ingestion Torrent Job for Cloud Queue
        job1 = TorrentJob(
            hash="d8c47b51b3a14e9f9024fba97312984a861cf9e3",
            name="Dune.Part.Two.2024.2160p.UHD.Remux.HEVC.DDP5.1",
            state="downloading",
            progress=0.68,
            download_speed=24500000,  # ~24.5 MB/s
            upload_speed=1200000,     # ~1.2 MB/s
            eta_seconds=310,          # ~5 min
            added_at=datetime.datetime.utcnow(),
        )
        session.add(job1)

        job2 = TorrentJob(
            hash="a1b2c3d4e5f60718293a4b5c6d7e8f9012345678",
            name="Arcane.League.of.Legends.S02E01.1080p.WEBRip.x265",
            state="post_processing",
            progress=1.0,
            download_speed=0,
            upload_speed=0,
            eta_seconds=0,
            added_at=datetime.datetime.utcnow() - datetime.timedelta(minutes=15),
        )
        session.add(job2)

        await session.commit()

    print("Database successfully seeded with playable sample media and active torrent jobs!")


if __name__ == "__main__":
    asyncio.run(seed_database())

