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

restic snapshots

read -p "=> Enter snapshot hash to overwrite current: " snapshot_hash

echo "=> Shutdown deployments"
docker compose down

echo "=> (Optional) Rename \`$ACTIVE_SQLITE_PATH\` to \`$ACTIVE_SQLITE_PATH.old\`"
mv $ACTIVE_SQLITE_PATH $ACTIVE_SQLITE_PATH.old || true

echo "=> Overwrite with snapshot"
restic restore $snapshot_hash --target .

echo "=> Rename \`$BACKUP_SQLITE_PATH\` to \`$ACTIVE_SQLITE_PATH\`"
mv $BACKUP_SQLITE_PATH $ACTIVE_SQLITE_PATH

echo "=> Start deployments"
docker compose up --wait

echo "=> Completed restore successfully!"
