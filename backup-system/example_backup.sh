#!/usr/bin/env bash

# Exit on error, uninitialized variable or pipefail
set -euo pipefail

BACKUP_DIR=/srv/home_assistant
BACKUP_SQLITE_PATH=$BACKUP_DIR/config/home-assistant_v2.db.bak
ACTIVE_SQLITE_PATH=$BACKUP_DIR/config/home-assistant_v2.db

if [ "${EUID}" -ne 0 ]; then
    echo "error: This script must be run root permission." >&2
    exit 1
fi

echo "=> Changing directory to \`$BACKUP_DIR\`"
cd "$BACKUP_DIR"

echo "=> Loading secrets from \`.env\` file"
# export AWS_ACCESS_KEY_ID=
# export AWS_SECRET_ACCESS_KEY=
# export RESTIC_REPOSITORY="s3:http://example:3900/home-assistant"
# openssl rand -hex 32
# export RESTIC_PASSWORD=
source .env

if ! restic snapshots >/dev/null 2>&1; then
    echo "=> Repository not found. Initializing"
    restic init
fi

echo "=> Creating snapshot of sqlite database"
sqlite3 $ACTIVE_SQLITE_PATH ".backup $SQLITE_BACKUP_PATH"

echo "=> Creating backup with Restic"
restic backup . \
    --exclude="*log*" \
    --exclude="home-assistant_v2.db" \
    --exclude="home-assistant_v2.db-shm" \
    --exclude="home-assistant_v2.db-wal" \
    --exclude="home-assistant_v2.db.old"

echo "=> Cleaning up temporary database snapshot"
rm $BACKUP_SQLITE_PATH

echo "=> Deleting old snapshots"
restic forget \
    --keep-daily 7 \
    --keep-weekly 4 \
    --keep-monthly 3 \
    --prune

echo "=> Checking repository integrity"
restic check

echo "=> Completed backup successfully!"
