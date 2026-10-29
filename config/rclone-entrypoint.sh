#!/bin/sh
set -e

# ==============================================================================
# Hardened Anti-Ban Google Drive Rclone VFS Mount Script
# ==============================================================================

REMOTE_NAME="${RCLONE_REMOTE_NAME:-gdrive}"
MOUNT_PATH="${RCLONE_MOUNT_PATH:-/mnt/gdrive}"
CACHE_DIR="${VFS_CACHE_DIR:-/data/vfs_cache}"

echo "[rclone-entrypoint] Initializing Google Drive Anti-Ban Mount..."
echo "[rclone-entrypoint] Target Remote: ${REMOTE_NAME}:/Media"
echo "[rclone-entrypoint] Mount Destination: ${MOUNT_PATH}"
echo "[rclone-entrypoint] VFS Cache Directory: ${CACHE_DIR}"

# Ensure mount point and cache directory exist
mkdir -p "${MOUNT_PATH}"
mkdir -p "${CACHE_DIR}"

# Verify FUSE device availability
if [ ! -e /dev/fuse ]; then
    echo "[rclone-entrypoint] ERROR: /dev/fuse is not accessible! Make sure Docker has cap_add: [SYS_ADMIN] and devices: [/dev/fuse]." >&2
    exit 1
fi

# Clean up any stale unmounts
if mountpoint -q "${MOUNT_PATH}"; then
    echo "[rclone-entrypoint] Detected existing mount point. Unmounting cleanly..."
    fusermount -uz "${MOUNT_PATH}" || true
fi

# Cleanup handler on container shutdown
cleanup() {
    echo "[rclone-entrypoint] Caught termination signal. Gracefully unmounting ${MOUNT_PATH}..."
    fusermount -uz "${MOUNT_PATH}" || true
    echo "[rclone-entrypoint] Mount unmounted. Exiting."
    exit 0
}

trap cleanup TERM INT QUIT HUP

# Launch rclone mount with strict Anti-Ban VFS caching parameters
echo "[rclone-entrypoint] Launching rclone mount daemon..."
rclone mount "${REMOTE_NAME}:/Media" "${MOUNT_PATH}" \
    --vfs-cache-mode full \
    --cache-dir "${CACHE_DIR}" \
    --vfs-cache-max-size 80G \
    --vfs-cache-max-age 48h \
    --vfs-read-chunk-size 32M \
    --vfs-read-chunk-size-limit 2G \
    --buffer-size 64M \
    --dir-cache-time 72h \
    --poll-interval 15s \
    --drive-pacer-min-sleep 100ms \
    --tpslimit 8 \
    --tpslimit-burst 1 \
    --drive-chunk-size 128M \
    --allow-other \
    --allow-non-empty \
    --umask 000 \
    --log-level INFO &

RCLONE_PID=$!

# Wait and verify mount
echo "[rclone-entrypoint] Verifying mount status..."
ATTEMPTS=0
MAX_ATTEMPTS=30

while ! mountpoint -q "${MOUNT_PATH}"; do
    ATTEMPTS=$((ATTEMPTS + 1))
    if [ ${ATTEMPTS} -ge ${MAX_ATTEMPTS} ]; then
        echo "[rclone-entrypoint] WARNING: Mount point ${MOUNT_PATH} is not active yet after 30 seconds."
        echo "[rclone-entrypoint] Waiting for rclone process ${RCLONE_PID} to complete configuration..."
        break
    fi
    sleep 1
done

if mountpoint -q "${MOUNT_PATH}"; then
    echo "[rclone-entrypoint] SUCCESS: ${MOUNT_PATH} is actively mounted with Anti-Ban VFS Caching."
fi

# Wait for rclone process to keep container running
wait ${RCLONE_PID}

