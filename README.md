GitOps is a practice where a Git repository acts as the single source of truth
for your infrastructure, automatically syncing and self-healing your live
system to match whatever code is merged into Git.

This reposotitory uses Kubernetes with FluxCD.
You should be familiar with the basics of these technologies.
The example repo was used as reference:
[fluxcd/flux2-kustomize-helm-example](https://github.com/fluxcd/flux2-kustomize-helm-example)

The entry point for FluxCD is `clusters/production`.
From there it uses Kustomization files to find the manifests.

Overview
========

- Mozilla SOPS is used to encrypt secrets like database passwords.

Installation
============

## 1 Longhorn storage

### Installation

Before this repository can be deployed on the cluster,
you need to install `iscsi` with your package manager.

### Check installation requirements

[Longhorn CLI Docs](https://longhorn.io/docs/1.11.2/advanced-resources/longhornctl/)

```zsh
curl -L https://github.com/longhorn/cli/releases/download/xxx -o longhornctl
chmod +x longhornctl
sudo -E ./longhornctl install preflight
sudo -E ./longhornctl check preflight
```

## 2 Install FluxCD on the cluster

```zsh
sudo pacman --needed -S flux
```

Generate SSH Key without password and save it to a temporary location.

```zsh
ssh-keygen -t ed25519 -C "flux@homelab"
```

Output and `/tmp/flux_ssh` entered:

```
Generating public/private ed25519 key pair.
Enter file in which to save the key (/home/dean/.ssh/id_ed25519): /tmp/flux_ssh
```

Give read permissions of public key (`/tmp/flux_ssh.pub`) to Git repository.

```zsh
cat /tmp/flux_ssh.pub
```

Install FluxCD on the cluster.

```zsh
kubectl apply -f clusters/production/flux-system/gotk-components.yaml
```

Add SSH key and known hosts as secret.

```zsh
ssh-keyscan codeberg.org > /tmp/flux_known_hosts
```

```zsh
kubectl create secret generic flux-system \
  --namespace=flux-system \
  --from-file=identity=/tmp/flux_ssh \
  --from-file=known_hosts=/tmp/flux_known_hosts
```

Update the specified repository URL in `gotk-sync.yaml`, then apply it.

```zsh
kubectl apply -f clusters/production/flux-system/gotk-sync.yaml
```

## 3 Generate encryption key for secrets

```zsh
sudo pacman --needed -S age sops
```

```zsh
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

```zsh
git add ./clusters/production/.sops.yaml
git commit -m 'ops: add public key for secrets generation'
```

Secrets can now be created following the
[create secrets section](#1-create-secrets).

## 4 Verify working installation

```zsh
flux get kustomizations
```

Developing
==========

## 1 Create secrets

```zsh
sudo pacman --needed -S openssl age sops
```

In this example a password for Redis with a length of 16 characters
is generated and encrypted.

```zsh
kubectl -n default create secret generic redis \
--namespace=nextcloud \
--from-literal=redis-password=$(openssl rand -base64 48 | tr -dc 'a-zA-Z0-9' | head -c 16) \
--dry-run=client \
-o yaml > apps/production/secrets/nextcloud-redis.yaml
```

Encrypt the created secrets using the `sops` CLI.

```zsh
sops --encrypt --in-place apps/production/secrets/nextcloud-redis.yaml
```

Update `apps/production/kustomization.yaml` to include the new secrets.

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ...
  - secrets/nextcloud-postgresql.yaml
```

## 2 Check changes

The diff command is used to do a server-side dry-run on flux resources
and print the difference.

```zsh
flux diff kustomization my-app --path apps/<app>
```

`my-app` refers to the deployment in the cluster.

## 3 Apply changes in the cluster

```zsh
git add -A
git commit -m "feat: ..."
git push
```

Troubleshooting
===============

## Undo faulty cluster change

```zsh
git revert <working-commit-hash>
```

## FluxCD

It is recommended that the Flux CLI is installed on your local machine.

### View status of manifests apply process

```zsh
kubectl -n flux-system get kustomizations
kubectl -n flux-system describe kustomization <component>
```

### Changes are not applied

Keep in mind that the apply process (reconcilation) can take a few minutes.

The most common cause is that newly created manifests are no specified in
Kustomization files. To verify that Flux applied the latest git commit:

```zsh
flux get kustomizations
```

Check if Helm was successful.

```zsh
flux get helmreleases -A
```

If Helm failed too many times, it goes into a timeout state. You can restart
the installation of a app with:

```zsh
kubectl -n flux-system rollout restart deploy helm-controller
```

OCI is sometimes used for Helm. You can check if the OCIRepository isn't loaded.

```zsh
flux get sources oci -A
```
