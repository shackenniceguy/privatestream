import datetime
from sqlalchemy import (
    Column,
    Integer,
    BigInteger,
    Float,
    String,
    Text,
    Boolean,
    DateTime,
    ForeignKey,
    Index,
)
from sqlalchemy.orm import relationship
from database import Base


class MediaItem(Base):
    __tablename__ = "media_items"

    id = Column(Integer, primary_key=True, index=True)
    title = Column(String(255), nullable=False, index=True)
    original_title = Column(String(255), nullable=True)
    overview = Column(Text, nullable=True)
    media_type = Column(String(32), nullable=False, default="movie", index=True)  # "movie" or "series"
    year = Column(Integer, nullable=True, index=True)
    season = Column(Integer, nullable=True)
    episode = Column(Integer, nullable=True)

    # Physical file & streaming attributes
    file_path = Column(String(1024), nullable=False)
    file_size_bytes = Column(BigInteger, default=0)
    duration_seconds = Column(Float, default=0.0)

    # Video characteristics extracted via ffprobe
    width = Column(Integer, default=1920)
    height = Column(Integer, default=1080)
    aspect_ratio = Column(String(32), default="16:9")  # e.g., "16:9", "9:16", "4:3", "3:4", "21:9"
    aspect_ratio_category = Column(String(32), default="horizontal", index=True)  # "horizontal", "vertical", "ultrawide", "square"
    video_codec = Column(String(64), default="h264")
    audio_codec = Column(String(64), default="aac")
    audio_channels = Column(Integer, default=2)

    # TMDB Enrichment
    poster_url = Column(String(1024), nullable=True)
    backdrop_url = Column(String(1024), nullable=True)
    tmdb_id = Column(Integer, nullable=True, index=True)
    vote_average = Column(Float, default=0.0)
    genres = Column(String(255), default="")  # Comma separated e.g. "Action,Sci-Fi"

    created_at = Column(DateTime, default=datetime.datetime.utcnow)

    # Relationships
    subtitles = relationship("SubtitleTrack", back_populates="media", cascade="all, delete-orphan", lazy="selectin")
    progress_records = relationship("WatchProgress", back_populates="media", cascade="all, delete-orphan", lazy="selectin")

    def to_dict(self):
        return {
            "id": self.id,
            "title": self.title,
            "original_title": self.original_title,
            "overview": self.overview,
            "media_type": self.media_type,
            "year": self.year,
            "season": self.season,
            "episode": self.episode,
            "file_size_bytes": self.file_size_bytes,
            "duration_seconds": self.duration_seconds,
            "width": self.width,
            "height": self.height,
            "aspect_ratio": self.aspect_ratio,
            "aspect_ratio_category": self.aspect_ratio_category,
            "video_codec": self.video_codec,
            "audio_codec": self.audio_codec,
            "audio_channels": self.audio_channels,
            "poster_url": self.poster_url,
            "backdrop_url": self.backdrop_url,
            "tmdb_id": self.tmdb_id,
            "vote_average": self.vote_average,
            "genres": [g.strip() for g in self.genres.split(",") if g.strip()],
            "subtitles": [sub.to_dict() for sub in (self.subtitles or [])],
            "created_at": self.created_at.isoformat() if self.created_at else None,
        }


class SubtitleTrack(Base):
    __tablename__ = "subtitle_tracks"

    id = Column(Integer, primary_key=True, index=True)
    media_id = Column(Integer, ForeignKey("media_items.id", ondelete="CASCADE"), nullable=False, index=True)
    language = Column(String(32), default="und")  # "rus", "eng", etc.
    title = Column(String(128), default="Subtitles")
    vtt_path = Column(String(1024), nullable=False)
    is_default = Column(Boolean, default=False)

    media = relationship("MediaItem", back_populates="subtitles")

    def to_dict(self):
        return {
            "id": self.id,
            "media_id": self.media_id,
            "language": self.language,
            "title": self.title,
            "vtt_url": f"/api/subtitles/{self.id}",
            "is_default": self.is_default,
        }


class WatchProgress(Base):
    __tablename__ = "watch_progress"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(String(64), default="primary_user", index=True)
    media_id = Column(Integer, ForeignKey("media_items.id", ondelete="CASCADE"), nullable=False, index=True)
    position_seconds = Column(Float, default=0.0)
    duration_seconds = Column(Float, default=0.0)
    completed = Column(Boolean, default=False)
    updated_at = Column(DateTime, default=datetime.datetime.utcnow, onupdate=datetime.datetime.utcnow)

    media = relationship("MediaItem", back_populates="progress_records")

    __table_args__ = (
        Index("idx_user_media_unique", "user_id", "media_id", unique=True),
    )

    def to_dict(self):
        return {
            "id": self.id,
            "user_id": self.user_id,
            "media_id": self.media_id,
            "position_seconds": self.position_seconds,
            "duration_seconds": self.duration_seconds,
            "completed": self.completed,
            "updated_at": self.updated_at.isoformat() if self.updated_at else None,
        }


class TorrentJob(Base):
    __tablename__ = "torrent_jobs"

    id = Column(Integer, primary_key=True, index=True)
    hash = Column(String(128), unique=True, index=True, nullable=False)
    name = Column(String(512), nullable=False)
    magnet_uri = Column(Text, nullable=True)
    state = Column(String(64), default="downloading", index=True)  # downloading, post_processing, uploading, completed, error
    progress = Column(Float, default=0.0)
    download_speed = Column(BigInteger, default=0)
    upload_speed = Column(BigInteger, default=0)
    eta_seconds = Column(Integer, default=0)
    error_message = Column(Text, nullable=True)
    added_at = Column(DateTime, default=datetime.datetime.utcnow)
    completed_at = Column(DateTime, nullable=True)

    def to_dict(self):
        return {
            "id": self.id,
            "hash": self.hash,
            "name": self.name,
            "state": self.state,
            "progress": self.progress,
            "download_speed": self.download_speed,
            "upload_speed": self.upload_speed,
            "eta_seconds": self.eta_seconds,
            "error_message": self.error_message,
            "added_at": self.added_at.isoformat() if self.added_at else None,
            "completed_at": self.completed_at.isoformat() if self.completed_at else None,
        }
