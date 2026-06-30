[Restic](https://restic.net/) is my preferred tool to create incremental backups
and store them in S3 Object Storage.

Setup
=====

## S3 Object Storage in Garage

```bash
sudo docker compose up -d
```

Run setup script and complete steps shown at the end:

```bash
./setup_garage.sh
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
