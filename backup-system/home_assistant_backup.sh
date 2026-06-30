#!/usr/bin/env bash

VM_NAME="haos"
# Can be found with `virsh edit $VM_NAME`
VM_DISK="sda"
IMAGE_DIR="/var/lib/libvirt/images"
XML_CONFIG_PATH="/tmp/${VM_NAME}_config.xml"
SNAPSHOT_PATH="$IMAGE_DIR/${VM_NAME}.qcow2"
REDIRECT_COW_PATH="$IMAGE_DIR/${VM_NAME}-active.qcow2"

# Exit on error, uninitialized variable or pipefail
set -euo pipefail

function cleanup {
  if [ -f "$REDIRECT_COW_PATH" ]; then
    echo "=> Merge redirected COW file and snapshot"
    virsh blockcommit $VM_NAME $VM_DISK --pivot --delete
  fi
}

trap cleanup EXIT

if [ "${EUID}" -ne 0 ]; then
  echo "error: This script must be run root permission." >&2
  exit 1
fi

echo "=> Load secrets from \`home_assistant_backup_secrets.sh\`"
# export AWS_ACCESS_KEY_ID=
# export AWS_SECRET_ACCESS_KEY=
# export RESTIC_REPOSITORY="s3:http://example:3900/home-assistant"
# # openssl rand -hex 32
# export RESTIC_PASSWORD=
source "/usr/local/sbin/home_assistant_backup_secrets.sh"

echo "=> Test connection to Restic repo"
if ! restic snapshots >/dev/null 2>&1; then
  echo "=> Repository not found. Initializing"
  restic init
fi

echo "=> Dump VM XML configuration to \`$XML_CONFIG_PATH\`"
virsh dumpxml $VM_NAME > "$XML_CONFIG_PATH"

echo "=> Create snapshot of VM and redirect writes to \`$REDIRECT_COW_PATH\`"
# --quiesce: libvirt will try to use guest agent to freeze and unfreeze guest virtual machine’s mounted file systems
virsh snapshot-create-as $VM_NAME --disk-only --atomic --quiesce \
  --diskspec $VM_DISK,file="$REDIRECT_COW_PATH"

echo "=> Creating backup with Restic"
restic backup "$XML_CONFIG_PATH" "$SNAPSHOT_PATH"

echo "=> Merge redirected COW file and snapshot"
virsh blockcommit $VM_NAME $VM_DISK --pivot --delete

echo "=> Delete \`$XML_CONFIG_PATH\`"
rm $XML_CONFIG_PATH

echo "=> Delete old snapshots"
restic forget \
  --keep-daily 7 \
  --keep-weekly 4 \
  --keep-monthly 3 \
  --prune

echo "=> Check repository integrity"
restic check

echo "=> Completed backup successfully!"
