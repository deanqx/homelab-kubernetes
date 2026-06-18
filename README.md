Homelab Kubernetes Cluster
==========================

_A project written by a human_

This repository contains the Kubernetes manifests to control my homelab server
cluster.

- Main Repository: [Codeberg deanqx/homelab-kubernetes](https://codeberg.org/deanqx/homelab-kubernetes)
- Mirror: [GitHub deanqx/homelab-kubernetes](https://github.com/deanqx/homelab-kubernetes)
- Host system config: [Codeberg deanqx/homelab-nixos](https://codeberg.org/deanqx/homelab-nixos)

Overview
========

## Technologies

- k3s: compliant lightweight version of Kubernetes which is used to orchestrate
  the cluster.
- Cilium: CNI (Container Network Interface), completely replaces the host
  firewall and kube-proxy.
- Flux CD: GitOps for Kubernetes
- SeaweedFS and Garage: S3 object storage
- Longhorn: replicated block storage over multiple nodes
- PostgreSQL: Database
- Redis: Key-Value Cache
- Grafana Stack: Monitoring

## Getting started

GitOps is a practice where a Git repository acts as the single source of truth
for your infrastructure, automatically syncing and self-healing your live
system to match whatever code is merged into Git.

This repository uses Kubernetes with Flux.
You should be familiar with the basics of these technologies.
The [fluxcd/flux2-kustomize-helm-example](https://github.com/fluxcd/flux2-kustomize-helm-example)
repo was used as overall reference. And
[fluxcd/flux2-monitoring-example](https://github.com/fluxcd/flux2-monitoring-example)
for the monitoring setup:

The entry point for Flux is `clusters/production`.
From there it uses Kustomization files to find the Kubernetes `.yaml` manifests.

## Deployed in Cluster

### Monitoring

- Grafana: web interface for monitoring data from Prometheus and Loki
- Prometheus: collects and stores metrics like CPU usage over time
- Loki by Grafana: stores logs with S3 in SeaweedFS
- Alloy by Grafana: collects logs and sends them to Loki

### Nextcloud

[Nextcloud](https://nextcloud.com) is self-hosted replacement for personal cloud
providers like Google Drive or Microsoft OneDrive. It offers many apps
implemented in the web interface which can replace Microsoft apps
like Word and Teams.

- Entry: Cilium is used as reverse-proxy and Cert-Manager for https.
- Storage: Longhorn
- Database: PostgreSQL
- Cache: Redis

### External

- [Home Assistant](https://www.home-assistant.io/): Controls my smart home
  devices. Cilium is used as reverse-proxy and Cert-Manager for https.

## Backup Strategy

These are the goals (following the 3-2-1 Backup Rule):

1. Create backups automatically.
2. Verify regularly for completeness.
3. Keep at least three copies of the data.
4. Keep backups on two different devices or media.
5. Store at least one copy in an offsite location to protect against physical
   disasters.
6. Use incremental storing.
7. Decouple from main architecture like Kubernetes (deleting the cluster should
   not result in a deletion of the Backups).
8. Principle of least privilege: forbid backup application to delete backups.

### Kubernetes Cluster

Backups are work in progress.

Using Kubernetes CronJob to trigger the creation of a new backup.

- Postgres: `pg_dump` is triggered by a K8s CronJob. Applications do not have to
  halt because of a concept called MVCC (Multi-Version Concurrency Control).

- Longhorn: Native backup solution and sent to S3.
  Triggered by Longhorn's RecurringJob.

- S3: rclone is triggered by a K8s CronJob

### Docker

- Volumes: Restic to a S3, scheduled via Host Cron.

Installation
============

View documentation in [./docs/installation.md](./docs/installation.md).

Upgrading
=========

```bash
flux install --components-extra=source-watcher \
--export > ./clusters/production/flux-system/gotk-components.yaml
```

Developing
==========

## Generate encryption key for secrets

```bash
age-keygen | kubectl create secret generic sops-age \
--namespace=flux-system \
--from-file=age.agekey=/dev/stdin
```

Example output:

```
Public key: age1x282vrqywk5nt9t9s8rpe3dcp3p7k76kay47tw9v4yt653dca99qgddhdn
```

Update the public key value `creation_rules.age` in the config for the
`sops` CLI located at `.sops.yaml`.

```yaml
creation_rules:
  - path_regex: ...
    encrypted_regex: ...
    age: age1x282vrqywk5nt9t9s8rpe3dcp3p7k76kay47tw9v4yt653dca99qgddhdn
```

Commit the `sops` config containing the public key:

```bash
git add .sops.yaml
git commit -m 'ops: add public key for secrets generation'
```

Secrets can now be created following the
[create secrets section](#create-secrets).

## Create secrets

To regenerate an existing secret use `scripts/generate_secrets.sh`.

In this example a password for PostgreSQL with a length of 25 characters
is generated and encrypted.

```bash
kubectl -n default create secret generic postgresql \
--namespace=nextcloud \
--from-literal=username=nextcloud \
--from-literal=admin-password=$(pwgen -sBcn 25 1) \
--from-literal=user-password=$(pwgen -sBcn 25 1) \
--from-literal=replication-password=$(pwgen -sBcn 25 1) \
--from-literal=metrics-password=$(pwgen -sBcn 25 1) \
--dry-run=client \
-o yaml > apps/production/nextcloud/database/postgresql-secret.yaml
```

Alternatively the password could be imported from ZX2C4 `pass`:

```bash
kubectl -n default create secret generic grafana \
--namespace=monitoring \
--from-literal=username=admin \
--from-literal=password=$(pass homelab/admin@monitor | head -n 1) \
--dry-run=client \
-o yaml > monitoring/production/grafana-secret.yaml
```

Encrypt the created secrets using the `sops` CLI:

```bash
sops --encrypt --in-place apps/production/nextcloud/database/postgresql-secret.yaml
# or
sops --encrypt --in-place monitoring/production/grafana-secret.yaml
```

Update `apps/production/nextcloud/database/kustomization.yaml` to include the
new secrets. Make sure to add the secret before the HelmRelease.

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - postgresql-secret.yaml
  - ...
```

The script at `scripts/generate_secrets.sh` should be updated.

## Check changes

The diff command is used to do a server-side dry-run on flux resources
and print the difference.

```bash
flux diff kustomization my-app --path apps/<app>
```

`my-app` refers to the deployment in the cluster.

## Apply changes in the cluster

```bash
git add -A
git commit -m "feat: ..."
git push
```

## Run Integration Tests

After changes are applied run the integration tests.

```bash
flux get kustomization
```

```bash
docker build -t homelab-tests tests
docker run --rm homelab-tests
```

Troubleshooting
===============

## Undo faulty change

```bash
git revert <working-commit-hash>
```

## Kubernetes

### Check Deployment Status

All pods should be healthy and without recent restarts.

```bash
kubectl get pod -A
```

### Logs

Let's say Cilium is in a crash loop.
`ds/` is an alias for `daemonset/`:

```bash
kubectl -n kube-system logs ds/cilium
```

If the previous pod crashed and therefore recently restarted:

```bash
kubectl -n kube-system logs ds/cilium --previous
```

If the logs don't contain useful information try `describe`:

```bash
kubectl -n kube-system describe ds/cilium
```

### Interactive Shell inside Pod

```bash
kubectl -n nextcloud exec -it deploy/nextcloud -- bash
```

## FluxCD

It is recommended that the Flux CLI is installed on your local machine.

[Official Troubleshooting cheatsheet](https://fluxcd.io/flux/cheatsheets/troubleshooting/)

### Check Deployment Status

`ks` is an alias for `kustomization`:

```bash
flux get ks
```

Check if Helm installations were successful.
`hr` is an alias for `helmrelease`:

```bash
flux get hr -A
```

## Longhorn Storage

When deployments are deleted and created again they often leave claimed volumes
behind.

The following command should only return the volumes that are used. It also
gives helpful information about the health of the volumes.

```bash
kubectl -n longhorn-system get volume
```

If not, delete them carefully:

```bash
kubectl -n longhorn-system delete volume pvc-...
```

## S3 Object Storage

I recommend the Minio CLI over the AWS CLI because the AWS CLI is build for AWS
services. The Minio CLI on the other hand is made for self-hosted S3.

### List Buckets

Run port forwarding in the background.

```bash
kubectl -n monitoring port-forward svc/seaweedfs-s3 8333
```

```bash
mcli homelab_monitoring ls
```

### Backup Server

Verbose output for Garage (S3):

```bash
docker compose exec -e RUST_LOG=garage=debug s3_object_storage /garage status
```
