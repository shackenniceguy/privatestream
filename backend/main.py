import os
import re
import json
import asyncio
import logging
from pathlib import Path
from typing import Optional, List
import datetime

import aiofiles
from fastapi import FastAPI, Depends, HTTPException, Query, Request, Response, status, UploadFile, File, Form, WebSocket, WebSocketDisconnect
from fastapi.responses import StreamingResponse, FileResponse, JSONResponse
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field
from sqlalchemy import select, update, delete, desc
from sqlalchemy.ext.asyncio import AsyncSession
from contextlib import asynccontextmanager

from database import get_db, init_db, AsyncSessionLocal
from models import MediaItem, SubtitleTrack, WatchProgress, TorrentJob

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("privatestream.api")

def resolve_directory(env_var: str, default_path: str, fallback_folder: str) -> Path:
    target = Path(os.getenv(env_var, default_path))
    try:
        target.mkdir(parents=True, exist_ok=True)
        return target
    except (PermissionError, OSError):
        fb = Path(__file__).resolve().parent.parent / "data" / fallback_folder
        fb.mkdir(parents=True, exist_ok=True)
        return fb

LOCAL_DOWNLOAD_DIR = resolve_directory("LOCAL_DOWNLOAD_DIR", "/data/local_downloads", "local_downloads")
REMOTE_MEDIA_DIR = Path(os.getenv("REMOTE_MEDIA_DIR", "/mnt/gdrive/Media"))
VFS_CACHE_DIR = resolve_directory("VFS_CACHE_DIR", "/data/vfs_cache", "vfs_cache")
QBITTORRENT_HOST = os.getenv("QBITTORRENT_HOST", "qbittorrent-nox")
QBITTORRENT_PORT = int(os.getenv("QBITTORRENT_PORT", "8080"))
QBITTORRENT_USER = os.getenv("QBITTORRENT_USER", "admin")
QBITTORRENT_PASSWORD = os.getenv("QBITTORRENT_PASSWORD", "adminadmin")

CHUNK_SIZE = 1024 * 1024 * 4  # 4MB streaming chunk alignment


@asynccontextmanager
async def lifespan(app: FastAPI):
    logger.info("Initializing PrivateStream database tables...")
    await init_db()
    LOCAL_DOWNLOAD_DIR.mkdir(parents=True, exist_ok=True)
    yield
    logger.info("PrivateStream API shutdown.")


app = FastAPI(
    title="PrivateStream Personal Cloud Streaming API",
    version="1.0.0",
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


# ------------------------------------------------------------------------------
# Pydantic Schemas
# ------------------------------------------------------------------------------

class ProgressUpdateItem(BaseModel):
    media_id: int
    position_seconds: float
    duration_seconds: float = 0.0
    completed: bool = False
    updated_at: Optional[str] = None


class BatchProgressRequest(BaseModel):
    user_id: str = "primary_user"
    updates: List[ProgressUpdateItem]


class TorrentAddRequest(BaseModel):
    magnet_url: Optional[str] = None


# ------------------------------------------------------------------------------
# Catalog Endpoints
# ------------------------------------------------------------------------------

@app.get("/api/catalog")
async def get_catalog(
    genre: Optional[str] = Query(None, description="Filter by genre"),
    search: Optional[str] = Query(None, description="Search by title"),
    aspect_ratio_category: Optional[str] = Query(None, description="Filter: horizontal, vertical, square, ultrawide"),
    media_type: Optional[str] = Query(None, description="Filter: movie, series"),
    limit: int = Query(50, ge=1, le=200),
    offset: int = Query(0, ge=0),
    user_id: str = Query("primary_user"),
    db: AsyncSession = Depends(get_db),
):
    """
    Catalog browsing with zero Google Drive API calls. All metadata is read from DB.
    """
    query = select(MediaItem).order_by(desc(MediaItem.created_at))

    if media_type:
        query = query.where(MediaItem.media_type == media_type.lower())

    if aspect_ratio_category:
        query = query.where(MediaItem.aspect_ratio_category == aspect_ratio_category.lower())

    if search:
        query = query.where(MediaItem.title.ilike(f"%{search}%"))

    if genre:
        query = query.where(MediaItem.genres.ilike(f"%{genre}%"))

    # Execute paginated query
    paginated_query = query.limit(limit).offset(offset)
    result = await db.execute(paginated_query)
    media_items = result.scalars().all()

    # Fetch watch progress map for the user
    media_ids = [m.id for m in media_items]
    progress_map = {}
    if media_ids:
        progress_res = await db.execute(
            select(WatchProgress).where(
                WatchProgress.user_id == user_id,
                WatchProgress.media_id.in_(media_ids),
            )
        )
        for p in progress_res.scalars().all():
            progress_map[p.media_id] = p.to_dict()

    items = []
    for m in media_items:
        d = m.to_dict()
        d["watch_progress"] = progress_map.get(m.id)
        items.append(d)

    return {
        "items": items,
        "count": len(items),
        "limit": limit,
        "offset": offset,
    }


@app.get("/api/media/{media_id}")
async def get_media_details(
    media_id: int,
    user_id: str = Query("primary_user"),
    db: AsyncSession = Depends(get_db),
):
    """
    Returns full metadata for a media item, including audio/subtitle tracks and watch progress.
    """
    res = await db.execute(select(MediaItem).where(MediaItem.id == media_id))
    item = res.scalar_one_or_none()
    if not item:
        raise HTTPException(status_code=404, detail="Media item not found")

    prog_res = await db.execute(
        select(WatchProgress).where(
            WatchProgress.user_id == user_id,
            WatchProgress.media_id == media_id,
        )
    )
    progress = prog_res.scalar_one_or_none()

    data = item.to_dict()
    data["watch_progress"] = progress.to_dict() if progress else None
    data["stream_url"] = f"/api/stream/{item.id}"
    data["download_url"] = f"/api/download/{item.id}"
    return data


# ------------------------------------------------------------------------------
# Watch Progress Sync (Online & Offline Conflict Resolution)
# ------------------------------------------------------------------------------

@app.post("/api/progress/sync")
async def sync_watch_progress(
    payload: BatchProgressRequest,
    db: AsyncSession = Depends(get_db),
):
    """
    Synchronizes watch progress from online or offline sessions.
    Resolves conflicts using the client-provided updated_at timestamp.
    """
    synced_count = 0
    for u in payload.updates:
        client_ts = None
        if u.updated_at:
            try:
                client_ts = datetime.datetime.fromisoformat(u.updated_at.replace("Z", "+00:00"))
            except ValueError:
                client_ts = datetime.datetime.utcnow()
        else:
            client_ts = datetime.datetime.utcnow()

        res = await db.execute(
            select(WatchProgress).where(
                WatchProgress.user_id == payload.user_id,
                WatchProgress.media_id == u.media_id,
            )
        )
        existing = res.scalar_one_or_none()

        if not existing:
            new_prog = WatchProgress(
                user_id=payload.user_id,
                media_id=u.media_id,
                position_seconds=u.position_seconds,
                duration_seconds=u.duration_seconds,
                completed=u.completed,
                updated_at=client_ts,
            )
            db.add(new_prog)
            synced_count += 1
        else:
            # Conflict resolution: only overwrite if update timestamp is strictly newer or position advanced
            if existing.updated_at is None or client_ts >= existing.updated_at:
                existing.position_seconds = u.position_seconds
                if u.duration_seconds > 0:
                    existing.duration_seconds = u.duration_seconds
                existing.completed = u.completed
                existing.updated_at = client_ts
                synced_count += 1

    await db.commit()
    return {"status": "success", "synced": synced_count}


# ------------------------------------------------------------------------------
# HTTP Range Streaming & Live Remuxing
# ------------------------------------------------------------------------------

def resolve_playable_file(file_path: str) -> Path:
    """Finds physical file either on mounted Google Drive or local download cache."""
    path = Path(file_path)
    if path.exists():
        return path

    # Check local downloads folder
    local_candidate = LOCAL_DOWNLOAD_DIR / path.name
    if local_candidate.exists():
        return local_candidate

    # Check mounted media folder
    remote_candidate = REMOTE_MEDIA_DIR / path.name
    if remote_candidate.exists():
        return remote_candidate

    return path


@app.get("/api/stream/{media_id}")
async def stream_media(
    media_id: int,
    request: Request,
    remux: int = Query(0, description="1 to force AAC audio remuxing"),
    audio_track: int = Query(0, description="Audio track index for remuxing"),
    start_time: float = Query(0.0, description="Seek start position in seconds"),
    db: AsyncSession = Depends(get_db),
):
    """
    High-performance video streaming endpoint:
    - Standard Range (206 Partial Content) with 4MB aligned chunks.
    - Dynamic on-the-fly ffmpeg remuxing for incompatible codecs into fragmented MP4.
    """
    res = await db.execute(select(MediaItem).where(MediaItem.id == media_id))
    item = res.scalar_one_or_none()
    if not item:
        raise HTTPException(status_code=404, detail="Media not found")

    file_path = resolve_playable_file(item.file_path)
    if not file_path.exists():
        raise HTTPException(status_code=404, detail=f"Physical media file unavailable at {file_path}")

    # Dynamic on-the-fly FFmpeg Remuxing to fragmented MP4
    if remux == 1:
        logger.info(f"Remuxing {file_path.name} on-the-fly with audio track {audio_track} from {start_time}s")
        cmd = [
            "ffmpeg",
            "-ss", str(start_time),
            "-i", str(file_path),
            "-map", "0:v:0",
            "-map", f"0:a:{audio_track}",
            "-c:v", "copy",
            "-c:a", "aac",
            "-b:a", "192k",
            "-movflags", "frag_keyframe+empty_moov+default_base_moof",
            "-f", "mp4",
            "pipe:1",
        ]

        proc = await asyncio.create_subprocess_exec(
            *cmd,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.DEVNULL,
        )

        async def ffmpeg_stream_generator():
            try:
                while True:
                    chunk = await proc.stdout.read(64 * 1024)
                    if not chunk:
                        break
                    yield chunk
            finally:
                if proc.returncode is None:
                    try:
                        proc.kill()
                    except ProcessLookupError:
                        pass

        return StreamingResponse(
            ffmpeg_stream_generator(),
            media_type="video/mp4",
            headers={
                "Accept-Ranges": "none",
                "Cache-Control": "no-cache",
            },
        )

    # Standard HTTP Range (206 Partial Content) Streaming
    file_size = file_path.stat().st_size
    range_header = request.headers.get("Range")

    if not range_header:
        # Full content response
        async def full_file_sender():
            async with aiofiles.open(file_path, "rb") as f:
                while chunk := await f.read(CHUNK_SIZE):
                    yield chunk

        return StreamingResponse(
            full_file_sender(),
            media_type="video/mp4",
            headers={
                "Accept-Ranges": "bytes",
                "Content-Length": str(file_size),
                "Content-Disposition": f'inline; filename="{file_path.name}"',
            },
        )

    # Parse Range Header (e.g., "bytes=0-1048575")
    range_match = re.match(r"^bytes=(\d+)-(\d*)$", range_header.strip())
    if not range_match:
        return Response(status_code=status.HTTP_416_REQUESTED_RANGE_NOT_SATISFIABLE)

    start = int(range_match.group(1))
    end = int(range_match.group(2)) if range_match.group(2) else file_size - 1

    if start >= file_size or end >= file_size or start > end:
        return Response(
            status_code=status.HTTP_416_REQUESTED_RANGE_NOT_SATISFIABLE,
            headers={"Content-Range": f"bytes */{file_size}"},
        )

    # Align chunk size to 4MB max for optimal VFS buffer reading
    requested_length = end - start + 1
    content_length = min(requested_length, CHUNK_SIZE * 2)
    end = start + content_length - 1

    async def range_file_sender():
        bytes_to_read = content_length
        async with aiofiles.open(file_path, "rb") as f:
            await f.seek(start)
            while bytes_to_read > 0:
                cur_chunk_size = min(bytes_to_read, 64 * 1024)
                chunk = await f.read(cur_chunk_size)
                if not chunk:
                    break
                bytes_to_read -= len(chunk)
                yield chunk

    headers = {
        "Content-Range": f"bytes {start}-{end}/{file_size}",
        "Accept-Ranges": "bytes",
        "Content-Length": str(content_length),
        "Content-Type": "video/mp4",
    }
    return StreamingResponse(
        range_file_sender(),
        status_code=status.HTTP_206_PARTIAL_CONTENT,
        headers=headers,
    )


@app.get("/api/download/{media_id}")
async def download_media(
    media_id: int,
    request: Request,
    db: AsyncSession = Depends(get_db),
):
    """
    Resumable offline download endpoint supporting HTTP Range headers for Flutter Offline Manager.
    """
    res = await db.execute(select(MediaItem).where(MediaItem.id == media_id))
    item = res.scalar_one_or_none()
    if not item:
        raise HTTPException(status_code=404, detail="Media not found")

    file_path = resolve_playable_file(item.file_path)
    if not file_path.exists():
        raise HTTPException(status_code=404, detail="File unavailable")

    file_size = file_path.stat().st_size
    range_header = request.headers.get("Range")

    if range_header:
        # Resumable download chunk
        range_match = re.match(r"^bytes=(\d+)-(\d*)$", range_header.strip())
        if range_match:
            start = int(range_match.group(1))
            end = int(range_match.group(2)) if range_match.group(2) else file_size - 1
            content_length = end - start + 1

            async def file_sender():
                async with aiofiles.open(file_path, "rb") as f:
                    await f.seek(start)
                    rem = content_length
                    while rem > 0:
                        chunk = await f.read(min(rem, 256 * 1024))
                        if not chunk:
                            break
                        rem -= len(chunk)
                        yield chunk

            return StreamingResponse(
                file_sender(),
                status_code=status.HTTP_206_PARTIAL_CONTENT,
                headers={
                    "Content-Range": f"bytes {start}-{end}/{file_size}",
                    "Accept-Ranges": "bytes",
                    "Content-Length": str(content_length),
                    "Content-Disposition": f'attachment; filename="{file_path.name}"',
                    "Content-Type": "application/octet-stream",
                },
            )

    return FileResponse(
        path=str(file_path),
        filename=file_path.name,
        media_type="application/octet-stream",
        headers={"Accept-Ranges": "bytes"},
    )


@app.get("/api/subtitles/{subtitle_id}")
async def get_subtitle_file(
    subtitle_id: int,
    db: AsyncSession = Depends(get_db),
):
    """Serves the extracted .vtt subtitle file."""
    res = await db.execute(select(SubtitleTrack).where(SubtitleTrack.id == subtitle_id))
    sub = res.scalar_one_or_none()
    if not sub:
        raise HTTPException(status_code=404, detail="Subtitle track not found")

    sub_path = Path(sub.vtt_path)
    if not sub_path.exists():
        raise HTTPException(status_code=404, detail="Subtitle file not found on disk")

    return FileResponse(
        path=str(sub_path),
        media_type="text/vtt; charset=utf-8",
        filename=sub_path.name,
    )


# ------------------------------------------------------------------------------
# Torrent Ingestion Endpoints (Flutter App Integration)
# ------------------------------------------------------------------------------

@app.post("/api/torrents/add")
async def add_torrent(
    magnet_url: Optional[str] = Form(None),
    file: Optional[UploadFile] = File(None),
    db: AsyncSession = Depends(get_db),
):
    """
    Dual-input torrent upload endpoint for Flutter client:
    Accepts magnet links OR multipart .torrent file uploads.
    Enforces local SSD staging rule.
    """
    LOCAL_DOWNLOAD_DIR.mkdir(parents=True, exist_ok=True)

    import qbittorrentapi
    try:
        qbt = qbittorrentapi.Client(
            host=QBITTORRENT_HOST,
            port=QBITTORRENT_PORT,
            username=QBITTORRENT_USER,
            password=QBITTORRENT_PASSWORD,
        )
        qbt.auth_log_in()
    except Exception as e:
        logger.warning(f"qBittorrent connection error: {e}")
        # Even if qbt service is connecting, accept and stage in DB
        pass

    torrent_name = "Torrent Ingest"
    torrent_hash = ""

    if magnet_url:
        magnet_url = magnet_url.strip()
        # Extract name or hash if available in magnet link
        hash_match = re.search(r"urn:btih:([a-zA-Z0-9]+)", magnet_url, re.IGNORECASE)
        torrent_hash = hash_match.group(1).lower() if hash_match else f"magnet_{datetime.datetime.utcnow().timestamp()}"
        name_match = re.search(r"dn=([^&]+)", magnet_url)
        if name_match:
            import urllib.parse
            torrent_name = urllib.parse.unquote_plus(name_match.group(1))

        try:
            qbt.torrents_add(
                urls=magnet_url,
                save_path=str(LOCAL_DOWNLOAD_DIR),
                category="privatestream",
            )
        except Exception as e:
            logger.error(f"Failed to submit magnet to qBittorrent: {e}")

        # Record in DB
        job = TorrentJob(
            hash=torrent_hash,
            name=torrent_name,
            magnet_uri=magnet_url,
            state="downloading",
            progress=0.0,
        )
        db.add(job)
        await db.commit()
        return {"status": "queued", "hash": torrent_hash, "name": torrent_name}

    elif file:
        staged_dir = LOCAL_DOWNLOAD_DIR / "staged_torrents"
        staged_dir.mkdir(parents=True, exist_ok=True)
        saved_file_path = staged_dir / file.filename

        contents = await file.read()
        async with aiofiles.open(saved_file_path, "wb") as f:
            await f.write(contents)

        torrent_name = file.filename
        torrent_hash = f"torrent_{datetime.datetime.utcnow().timestamp()}"

        try:
            with open(saved_file_path, "rb") as tf:
                qbt.torrents_add(
                    torrent_files=tf,
                    save_path=str(LOCAL_DOWNLOAD_DIR),
                    category="privatestream",
                )
        except Exception as e:
            logger.error(f"Failed to add torrent file to qBittorrent: {e}")

        job = TorrentJob(
            hash=torrent_hash,
            name=torrent_name,
            state="downloading",
            progress=0.0,
        )
        db.add(job)
        await db.commit()
        return {"status": "queued", "hash": torrent_hash, "name": torrent_name}

    raise HTTPException(status_code=400, detail="Must provide either magnet_url or file")


@app.get("/api/torrents/list")
async def list_torrents(db: AsyncSession = Depends(get_db)):
    """Returns active and completed torrent jobs."""
    res = await db.execute(select(TorrentJob).order_by(desc(TorrentJob.added_at)).limit(50))
    jobs = res.scalars().all()
    return [j.to_dict() for j in jobs]


@app.delete("/api/torrents/{job_hash}")
async def cancel_torrent(job_hash: str, db: AsyncSession = Depends(get_db)):
    """Cancels and deletes torrent job."""
    import qbittorrentapi
    try:
        qbt = qbittorrentapi.Client(
            host=QBITTORRENT_HOST,
            port=QBITTORRENT_PORT,
            username=QBITTORRENT_USER,
            password=QBITTORRENT_PASSWORD,
        )
        qbt.auth_log_in()
        qbt.torrents_delete(torrent_hashes=job_hash, delete_files=True)
    except Exception as e:
        logger.warning(f"Error removing from qBittorrent: {e}")

    await db.execute(delete(TorrentJob).where(TorrentJob.hash == job_hash))
    await db.commit()
    return {"status": "deleted", "hash": job_hash}


# ------------------------------------------------------------------------------
# WebSocket Real-Time Progress Broadcast
# ------------------------------------------------------------------------------

@app.websocket("/ws/torrents")
async def websocket_torrents(websocket: WebSocket):
    """
    Live WebSocket broadcasting torrent progress, speeds, and ETA to Flutter client.
    """
    await websocket.accept()
    try:
        while True:
            async with AsyncSessionLocal() as session:
                res = await session.execute(
                    select(TorrentJob).order_by(desc(TorrentJob.added_at)).limit(20)
                )
                jobs = res.scalars().all()
                data = [j.to_dict() for j in jobs]

            await websocket.send_text(json.dumps(data))
            await asyncio.sleep(1.5)
    except WebSocketDisconnect:
        logger.info("WebSocket client disconnected from /ws/torrents")
    except Exception as e:
        logger.warning(f"WebSocket error: {e}")

