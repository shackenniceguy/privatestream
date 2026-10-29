#!/bin/bash
set -e

# ==============================================================================
# PrivateStream 24/7 Background Service Installer & Launcher
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SYSTEMD_USER_DIR="${HOME}/.config/systemd/user"
SERVICE_FILE="${SCRIPT_DIR}/config/privatestream.service"
CLOUDFLARED_BIN="${SCRIPT_DIR}/config/bin/cloudflared"

mkdir -p "${SYSTEMD_USER_DIR}"

echo "=================================================================="
echo "⚡ Setting up PrivateStream 24/7 Autostart Background Daemon"
echo "=================================================================="

# Copy systemd unit file
cp "${SERVICE_FILE}" "${SYSTEMD_USER_DIR}/privatestream.service"

# Reload systemd and enable service
systemctl --user daemon-reload
systemctl --user enable --now privatestream.service

echo ""
echo "✓ PrivateStream background service installed and started!"
echo "Status check:"
systemctl --user status privatestream.service --no-pager || true

echo ""
echo "=================================================================="
echo "🌐 Starting Public Internet Tunnel via Cloudflare..."
echo "=================================================================="
echo "This exposes your backend (port 8000) securely with free HTTPS so"
echo "your Firebase web app (https://privatestream.web.app) and phone"
echo "can connect from anywhere in the world 24/7!"
echo ""

"${CLOUDFLARED_BIN}" tunnel --url http://127.0.0.1:8000
