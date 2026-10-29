# PrivateStream ("Private Netflix") 🍿

A complete, production-ready, end-to-end personal streaming platform built with **FastAPI**, **qBittorrent-nox**, hardened **rclone VFS mount**, **Telegram Bot (aiogram 3.x)**, and a cross-platform **Flutter** client.

---

## 🏛 Platform Architecture

```
                                  [ Telegram Bot ]
                                         │
                                  (.torrent / magnet)
                                         ▼
[ Flutter App ] ──(Upload)──► [ FastAPI API ] ──► [ qBittorrent-nox ]
                                                         │
                                             (Strict SSD Staging)
                                                         ▼
                                              /data/local_downloads
                                                         │
                                                 (100% Downloaded)
                                                         ▼
                                              [ Ingestor Pipeline ]
                                                ├─ ffprobe (DAR / Codecs / Subtitles)
                                                ├─ ffmpeg (Extract .vtt tracks)
                                                ├─ TMDB API (ru-RU / en-US metadata)
                                                └─ Anti-Ban Sequential Upload
                                                         │
                                             (rclone move --tpslimit 4)
                                                         ▼
                                            Google Drive (gdrive:/Media)
                                                         │
                                            (Anti-Ban VFS Cache Mount)
                                                         ▼
                                                    /mnt/gdrive
                                                         │
[ Flutter App ] ◄──(Range 206 / Offline Sync)──── [ FastAPI API ]
```

---

## 🚀 Key Features

### 1. Dual-Input Zero-Touch Torrent Ingestion
- **Telegram Bot (`aiogram 3.x`)**: Send `.torrent` files or `magnet:?xt=...` links directly to your private bot (secured via `ALLOWED_USER_ID`).
- **Flutter App Direct Upload**: Ingest media from mobile or desktop via `POST /api/torrents/add`.
- **Strict Anti-Ban SSD Staging**: Torrents are strictly downloaded to local SSD storage (`/data/local_downloads`). Torrents are **never** written directly to Google Drive mount, eliminating random chunk write bans.
- **Automated Post-Processing**:
  - Single-pass `ffprobe` to detect Display Aspect Ratio (`16:9`, `9:16`, `4:3`, `3:4`, `21:9`), duration, resolution, and audio/video codecs.
  - Automatic extraction of embedded subtitle streams to `.vtt` format.
  - Automatic metadata enrichment from TMDB API in Russian (`ru-RU`) and English (`en-US`).
  - Rate-limited sequential `rclone move` to Google Drive with `--drive-chunk-size 128M --tpslimit 4 --transfers 1 --checkers 2`.
  - Zero-API catalog browsing powered by async SQLite database.

### 2. Universal Orientation & Aspect-Ratio Engine
- Universal responsive layout supporting all screen ratios:
  - **Portrait Mobile (`9:16`, `9:20`)**: Bottom navigation bar with glassmorphic styling, compact card stacks.
  - **Foldables & Tablets (`3:4`, `4:3`, `1:1`)**: Navigation rail, 3-column media grid.
  - **Widescreen Desktop & TV (`16:9`, `16:10`, `21:9`)**: Cinematic hero banner, 4-6 column adaptive grid, extended sidebar.
- **Hardware-Accelerated Player (`media_kit` / `libmpv`)**:
  - **Orientation Lock Toggle**: Instant switching between `Portrait Lock`, `Landscape Lock`, and `Auto-Rotate`.
  - **Live Aspect Ratio & Fit Switcher**: Cycle seamlessly through `Original`, `16:9`, `9:16` (Vertical full-screen without turning device), `4:3`, `3:4`, `21:9`, `Fit (Contain)`, `Crop / Fill (Cover)`, and `Stretch (Fill)`.
  - **Touch Gestures**: Left vertical drag for brightness, right vertical drag for volume, double tap left/right for 10s seek, long press for 2x playback speed.

### 3. Full Offline Mode ("Smart Downloads")
- In-app resumable file downloads via HTTP `Range` headers using `Dio`.
- Saves video, artwork, and `.vtt` subtitles to local device storage (`getApplicationSupportDirectory()`).
- Offline-first library viewing with zero network dependency.
- Local watch progress queuing with automated background synchronization to server upon network reconnection.

---

## 📁 Repository Structure

```
privatestream/
├── docker-compose.yml              # Multi-container stack (rclone, qbittorrent, ingestor, api)
├── .env.example                    # Environment variables template
├── config/
│   └── rclone-entrypoint.sh        # Hardened Anti-Ban Google Drive mount script
├── backend/
│   ├── Dockerfile                  # Multi-stage image with ffmpeg, ffprobe, rclone
│   ├── requirements.txt            # Python dependencies
│   ├── database.py                 # Async SQLAlchemy engine & session factory
│   ├── models.py                   # MediaItem, SubtitleTrack, WatchProgress, TorrentJob models
│   ├── tmdb.py                     # Clean filename parser & TMDB API enricher
│   ├── ingestor.py                 # Torrent watcher, post-processor & Telegram bot
│   └── main.py                     # FastAPI server (Range 206, Remuxing, Catalog, Sync)
└── flutter_client/
    ├── pubspec.yaml                # Flutter dependencies (Riverpod, Dio, MediaKit, SQLite)
    ├── lib/
    │   ├── main.dart               # App initialization, MediaKit & SQLite FFI setup
    │   ├── core/
    │   │   ├── theme.dart          # Dark Cyberpunk/Netflix theme
    │   │   └── responsive_shell.dart # Universal layout engine (9:16 to 21:9)
    │   ├── models/
    │   │   ├── media_item.dart     # Catalog & subtitle models with DAR helpers
    │   │   └── download_task.dart  # Offline task model with SQLite serialization
    │   ├── services/
    │   │   ├── api_service.dart    # Dio HTTP client & WebSocket connector
    │   │   └── offline_sync_service.dart # Resumable downloader & offline progress sync
    │   └── screens/
    │       ├── home_screen.dart    # Hero banner, continue watching & categorized rows
    │       ├── details_screen.dart # Media details, offline download button & tracks
    │       ├── player_screen.dart  # Custom MediaKit player with HUD & aspect ratio cycling
    │       └── downloads_screen.dart # Cloud Torrents Queue & On-Device Downloads tabs
    └── test/
        ├── widget_test.dart        # Smoke test with provider overrides
        └── responsive_and_models_test.dart # Unit tests for aspect ratios and models
```

---

## 🛠 Setup & Deployment

### 1. Configure Environment Variables
Copy `.env.example` to `.env` and fill in your credentials:
```bash
cp .env.example .env
```
Key parameters:
- `TMDB_API_KEY`: Your TheMovieDatabase v3 API key.
- `TELEGRAM_BOT_TOKEN`: Token from [@BotFather](https://t.me/BotFather).
- `ALLOWED_USER_ID`: Your Telegram numeric user ID.
- `RCLONE_REMOTE_NAME`: Name of your rclone Google Drive remote (default: `gdrive`).

### 2. Start the Backend Services with Docker Compose
```bash
docker compose up -d --build
```
This starts:
1. `privatestream-rclone`: Mounts `gdrive:/Media` to `/mnt/gdrive` with 80GB VFS local cache.
2. `privatestream-qbittorrent`: Isolated torrent client downloading strictly to local SSD.
3. `privatestream-ingestor`: Background post-processing pipeline and Telegram bot listener.
4. `privatestream-api`: FastAPI streaming server exposed on port `8000`.

### 3. Launch the Flutter Client
```bash
cd flutter_client
flutter pub get
flutter run -d linux   # Or -d windows, -d macos, -d chrome, or connect Android/iOS device
```

---

## 📡 API Endpoints Summary

| Method | Endpoint | Description |
|---|---|---|
| `GET` | `/api/catalog` | Zero-API browsing filtered by genre, search, aspect ratio (`vertical`, `horizontal`) |
| `GET` | `/api/media/{id}` | Full metadata, native aspect ratio, audio codecs, and subtitle tracks |
| `GET` | `/api/stream/{id}` | HTTP 206 Partial Content Range streaming with 4MB chunk alignment |
| `GET` | `/api/stream/{id}?remux=1` | On-the-fly `ffmpeg` remuxing to fragmented MP4 (AAC audio) |
| `GET` | `/api/download/{id}` | Resumable file downloads for Flutter Offline Manager |
| `GET` | `/api/subtitles/{id}` | Serves extracted `.vtt` subtitles |
| `POST` | `/api/progress/sync` | Batch watch progress sync with conflict resolution |
| `POST` | `/api/torrents/add` | Staged torrent ingestion via magnet link or `.torrent` file |
| `GET` | `/api/torrents/list` | List active torrent jobs, download speed, ETA |
| `DELETE` | `/api/torrents/{hash}`| Cancel and remove torrent |
| `WS` | `/ws/torrents` | Real-time WebSocket broadcasting download progress |

