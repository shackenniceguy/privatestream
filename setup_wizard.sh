#!/bin/bash
set -e

# ==============================================================================
# PrivateStream Interactive Setup Wizard: Telegram Bot & Google Drive
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/.env"
RCLONE_BIN="${SCRIPT_DIR}/config/bin/rclone"
CONFIG_DIR="${SCRIPT_DIR}/config"

echo "=================================================================="
echo "🍿 PrivateStream Setup Wizard: Telegram Bot & Google Drive"
echo "=================================================================="
echo ""

# Copy .env.example if .env doesn't exist
if [ ! -f "${ENV_FILE}" ]; then
    cp "${SCRIPT_DIR}/.env.example" "${ENV_FILE}"
fi

# ------------------------------------------------------------------------------
# STEP 1: Telegram Bot Configuration
# ------------------------------------------------------------------------------
echo "--- [1/2] TELEGRAM BOT CONFIGURATION ---"
echo "1. Open Telegram and search for @BotFather"
echo "2. Send: /newbot and choose a name & username"
echo "3. Copy the HTTP API token provided by BotFather"
echo "4. To get your numeric User ID, message @userinfobot on Telegram"
echo ""

read -rp "Enter your Telegram Bot Token (or press Enter to skip): " TG_TOKEN
if [ -n "${TG_TOKEN}" ]; then
    sed -i "s|^TELEGRAM_BOT_TOKEN=.*|TELEGRAM_BOT_TOKEN=${TG_TOKEN}|" "${ENV_FILE}"
    echo "✓ Saved TELEGRAM_BOT_TOKEN into .env"
fi

read -rp "Enter your Telegram Numeric User ID (e.g. 123456789): " TG_USER_ID
if [ -n "${TG_USER_ID}" ]; then
    sed -i "s|^ALLOWED_USER_ID=.*|ALLOWED_USER_ID=${TG_USER_ID}|" "${ENV_FILE}"
    echo "✓ Saved ALLOWED_USER_ID into .env"
fi

echo ""

# ------------------------------------------------------------------------------
# STEP 2: Google Drive Authorization (Rclone)
# ------------------------------------------------------------------------------
echo "--- [2/2] GOOGLE DRIVE STORAGE CONFIGURATION ---"
echo "Rclone will now launch an interactive authorization wizard:"
echo "1. Type 'n' (New remote) and name it: gdrive"
echo "2. Choose 'drive' (Google Drive)"
echo "3. Leave client_id & client_secret blank (or use your own GCP credentials)"
echo "4. Choose scope '1' (Full access)"
echo "5. Say 'y' to open the browser and log into your Google Account"
echo ""

read -rp "Press Enter to start Google Drive authorization (or type 's' to skip): " G_CHOICE

if [ "${G_CHOICE}" != "s" ] && [ "${G_CHOICE}" != "S" ]; then
    "${RCLONE_BIN}" config --config "${CONFIG_DIR}/rclone.conf"
    echo ""
    echo "Testing connection to Google Drive..."
    if "${RCLONE_BIN}" lsd gdrive: --config "${CONFIG_DIR}/rclone.conf" >/dev/null 2>&1; then
        echo "✓ Google Drive successfully authenticated and connected!"
    else
        echo "Notice: Could not list 'gdrive:'. Make sure the remote name in rclone config was set to 'gdrive'."
    fi
fi

echo ""
echo "=================================================================="
echo "🎉 Setup complete! All credentials saved in .env and config/rclone.conf"
echo "You can now run: docker compose up -d"
echo "=================================================================="

