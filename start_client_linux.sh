#!/bin/bash
set -e

# ==============================================================================
# PrivateStream Flutter Client Runner (Linux Desktop)
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLIENT_DIR="${SCRIPT_DIR}/flutter_client"

cd "${CLIENT_DIR}"

echo "========================================================"
echo "🎬 Launching PrivateStream Flutter Desktop Application"
echo "========================================================"

flutter run -d linux
