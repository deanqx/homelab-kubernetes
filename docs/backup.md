[Restic](https://restic.net/) is my preferred tool to create incremental backups
and store them in S3 Object Storage.

Setup
=====

Recommended location is `/srv/backup-storage`.

`docker-compose.yaml`:

```yaml
services:
  caddy:
    # https://hub.docker.com/_/caddy/
    image: caddy:2
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
      - "443:443/udp"
      - "3900:3900"
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile:ro
      - caddy_data:/data
      - caddy_config:/config
  garage-s3:
    # https://hub.docker.com/r/dxflrs/garage/tags
    image: dxflrs/garage:v2.3.0
    restart: unless-stopped
    # listening on port 3900
    volumes:
      - ./garage.toml:/etc/garage.toml
      # volume needs speed
      - ./garage_s3/meta:/var/lib/garage/meta
      # volume needs space
      - ./garage_s3/data:/var/lib/garage/data
volumes:
  caddy_data:
  caddy_config:
```

`Caddyfile`:

```
backup.deanqx.com:3900 {
  reverse_proxy garage-s3:3900
}
```

`garage.toml`:

```toml
metadata_dir = "/var/lib/garage/meta"
data_dir = "/var/lib/garage/data"
db_engine = "lmdb"
metadata_auto_snapshot_interval = "6h"

replication_factor = 1
compression_level = 2

rpc_bind_addr = "[::]:3901"
rpc_public_addr = "[::1]:3901"
# openssl rand -hex 32
rpc_secret = "280b0f171c918c2088b76751fdad2812ca1c6b006d29eff41c2865a08cd2934e"

[s3_api]
api_bind_addr = "[::]:3900"
s3_region = "garage"
```

## S3 Server with Garage

```sh
sudo docker compose up -d
```

In the following an alias is used for `garage`:

```sh
alias garage="docker compose exec garage-s3 /garage"
```

```sh
garage node id
```

Output:

```
64cc87709556109bd326653a60ae4a3108df1f8952c9b5592004ce0bfba1d6bb@[::1]:3901
```

Copy the node ID which is the part before `@`, in this case `64cc8770955`.

```sh
garage layout assign [NODE_ID] -c [STORAGE_CAPACITY] -z [ZONE]
```

## Prepare backup storage in Garage

Create access key for backup script and an admin key.
Store `Key ID` and `Secret Key` securely.

```sh
garage key create admin
garage key create home-assistant
```

```sh
garage bucket create home-assistant
```

Output:

```
Bucket: 5ed137a323e2b862fbb87a52a6386a3055a065edbd6d6ac84c37aaade36e49d8
```

Allow the backup script key and the admin key to access the bucket.

```sh
garage bucket allow [BUCKET_ID] --read --write --key [KEY_ID]
```

## Backup script for VM

`home_assistant_backup.yaml`:

```sh
#!/usr/bin/env bash

VM_NAME="haos"
# Can be found with `virsh edit $VM_NAME`
VM_DISK="sda"
IMAGE_DIR="/var/lib/libvirt/images"
XML_CONFIG_PATH="/tmp/${VM_NAME}_config.xml"
SECRETS_PATH="$(dirname "${BASH_SOURCE[0]}")/backup_secrets.sh"
SNAPSHOT_PATH="$IMAGE_DIR/${VM_NAME}.qcow2"
REDIRECT_COW_PATH="$IMAGE_DIR/${VM_NAME}-active.qcow2"

# Exit on error, uninitialized variable or pipefail
set -euo pipefail

if [ "${EUID}" -ne 0 ]; then
  echo "error: This script must be run with root permission." >&2
  exit 1
fi

function cleanup {
  if [ -f "$REDIRECT_COW_PATH" ]; then
    echo "=> Merge VM snapshot"
    virsh blockcommit $VM_NAME $VM_DISK --pivot --delete
  fi
}

trap cleanup EXIT

if [ -f "$REDIRECT_COW_PATH" ]; then
  cleanup
fi

echo "=> Load secrets from \`$SECRETS_PATH\`"
# export AWS_ACCESS_KEY_ID=
# export AWS_SECRET_ACCESS_KEY=
# export RESTIC_REPOSITORY="s3:http://example:3900/home-assistant"
# # openssl rand -hex 32
# export RESTIC_PASSWORD=
source "$SECRETS_PATH"

echo "=> Test connection to Restic repo"
if ! restic snapshots >/dev/null 2>&1; then
  echo "=> Repository \`$RESTIC_REPOSITORY\` not found"
  echo "=> Init repository"
  restic init
fi

echo "=> Dump VM XML configuration to \`$XML_CONFIG_PATH\`"
virsh dumpxml $VM_NAME > "$XML_CONFIG_PATH"

echo "=> Create snapshot of VM and redirect writes to \`$REDIRECT_COW_PATH\`"
# --quiesce: libvirt will try to use guest agent to freeze and unfreeze guest
# virtual machine’s mounted file systems
virsh snapshot-create-as $VM_NAME --disk-only --atomic --quiesce \
  --diskspec $VM_DISK,file="$REDIRECT_COW_PATH"

echo "=> Creating backup with Restic (Print progress every 10s)"
RESTIC_PROGRESS_FPS=0.1 restic backup "$XML_CONFIG_PATH" "$SNAPSHOT_PATH" 2>&1 | sed -u 's/\r/\n/g'

echo "=> Merge VM snapshot"
virsh blockcommit $VM_NAME $VM_DISK --pivot --delete

echo "=> Delete \`$XML_CONFIG_PATH\`"
rm $XML_CONFIG_PATH

echo "=> Delete old Restic backups"
restic forget --prune \
  --keep-daily 7 \
  --keep-weekly 4 \
  --keep-monthly 3

echo "=> Check Restic repo integrity"
restic check

echo "=> Completed successfully!"
```

Create a script that stores the secrets, in this case
   `home_assistant_backup_secrets.sh`:

```sh
export AWS_ACCESS_KEY_ID=
export AWS_SECRET_ACCESS_KEY=
export RESTIC_REPOSITORY="s3:http://example:3900/home-assistant"
# openssl rand -hex 32
export RESTIC_PASSWORD=
```

In this case the script accesses VMs and therefore needs root privileges.
To prevent malicious modifications only root is allowed to edit the files.

```sh
sudo chown root:root home_assistant_backup.sh home_assistant_backup_secrets.sh
sudo chmod 700 home_assistant_backup.sh home_assistant_backup_secrets.sh
```

Configure [systemd Timer](https://wiki.archlinux.org/title/Systemd/Timers)

Restore Backup
==============

1. Load S3 credentials in the shell as environment variables.

when using Fish as shell:

```sh
source (sudo cat /usr/local/sbin/home_assistant_backup_secrets.sh | psub)
```

when using Bash as shell:

```sh
source <(sudo cat /usr/local/sbin/home_assistant_backup_secrets.sh)
```

2. List snapshots stored in Restic.

```bash
restic snapshots
```

```bash
restic restore 405bc91b4c --target /tmp/ha_restore
```

```
/tmp/ha_restore/tmp/haos_config.xml
/tmp/ha_restore/var/lib/libvirt/images/haos.qcow2
```

```bash
sudo virsh shutdown haos
sudo virsh domstate haos | grep shut
```

```bash
cd /var/lib/libvirt/images
sudo mv haos.qcow2 haos.qcow2.bak
sudo virsh define /tmp/ha_restore/tmp/haos_config.xml
sudo mv /tmp/ha_restore/var/lib/libvirt/images/haos.qcow2 .
sudo chown root:root haos.qcow2
sudo chmod 600 haos.qcow2
```

```bash
sudo virsh start haos
```

