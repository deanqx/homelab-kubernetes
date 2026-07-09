[Restic](https://restic.net/) is my preferred tool to create incremental backups
and store them in S3 Object Storage.

Setup
=====

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

## Backup script for single server

Recommended location for these scripts:

```bash
cd /usr/local/sbin
```

1. Copy `./home_assistant_backup.sh` to the server and adjust it.

2. Create a script that stores the secrets, in this case
   `home_assistant_backup_secrets.sh`:

```bash
export AWS_ACCESS_KEY_ID=
export AWS_SECRET_ACCESS_KEY=
export RESTIC_REPOSITORY="s3:http://example:3900/home-assistant"
# openssl rand -hex 32
export RESTIC_PASSWORD=
```

3. In this case the script accesses VMs and therefore needs root privileges.
   To prevent malicious modifications only root is allowed to edit the files.

```bash
sudo chown root:root home_assistant_backup.sh home_assistant_backup_secrets.sh
sudo chmod 700 home_assistant_backup.sh home_assistant_backup_secrets.sh
```

4. Configure [systemd Timer](https://wiki.archlinux.org/title/Systemd/Timers)

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
