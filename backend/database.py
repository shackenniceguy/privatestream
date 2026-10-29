import os
from pathlib import Path
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine
from sqlalchemy.orm import declarative_base

# Determine SQLite database path
DEFAULT_DB_URL = "sqlite+aiosqlite:////data/db/privatestream.db"
DATABASE_URL = os.getenv("DATABASE_URL", DEFAULT_DB_URL)

# Fallback to local working directory if system directory /data/db doesn't exist
if DATABASE_URL.startswith("sqlite+aiosqlite:////data/db"):
    db_dir = Path("/data/db")
    try:
        db_dir.mkdir(parents=True, exist_ok=True)
    except (PermissionError, OSError):
        fallback_dir = Path("./data")
        fallback_dir.mkdir(parents=True, exist_ok=True)
        DATABASE_URL = f"sqlite+aiosqlite:///{fallback_dir.resolve()}/privatestream.db"

engine = create_async_engine(
    DATABASE_URL,
    echo=False,
    connect_args={"check_same_thread": False} if "sqlite" in DATABASE_URL else {},
)

AsyncSessionLocal = async_sessionmaker(
    bind=engine,
    class_=AsyncSession,
    expire_on_commit=False,
    autoflush=False,
    autocommit=False,
)

Base = declarative_base()


async def get_db():
    """FastAPI async dependency yielding database session."""
    async with AsyncSessionLocal() as session:
        try:
            yield session
        finally:
            await session.close()


async def init_db():
    """Initializes database schema creating all required tables."""
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
