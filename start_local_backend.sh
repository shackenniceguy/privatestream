#!/bin/bash
set -e

# ==============================================================================
# PrivateStream Local Backend Runner (Runs FastAPI + SQLite natively)
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKEND_DIR="${SCRIPT_DIR}/backend"

cd "${BACKEND_DIR}"

echo "========================================================"
echo "🚀 Starting PrivateStream Personal Cloud Streaming API"
echo "========================================================"

# Create virtual environment if missing
if [ ! -d ".venv" ]; then
    echo "[1/4] Creating Python virtual environment in ${BACKEND_DIR}/.venv..."
    python3 -m venv .venv
fi

source .venv/bin/activate

echo "[2/4] Installing backend dependencies..."
pip install --quiet --upgrade pip
pip install --quiet -r requirements.txt

echo "[3/4] Populating test catalog and sample videos (seed_data)..."
python seed_data.py || true

echo "[4/4] Launching Uvicorn ASGI Server on http://127.0.0.1:8000..."
echo "API Docs available at: http://127.0.0.1:8000/docs"
exec uvicorn main:app --host 0.0.0.0 --port 8000 --reload
