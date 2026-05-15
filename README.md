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

Give public key (`/tmp/flux_ssh.pub`) in Git repository read permission.

```zsh
cat /tmp/flux_ssh.pub
```

Install FluxCD on the cluster and apply the repository.

```zsh
flux bootstrap git \
  --url=ssh://git@codeberg.org/deanqx/homelab-kubernetes.git \
  --branch=main \
  --private-key-file=/tmp/flux_ssh \
  --path=clusters/production
```

## 3 Generate encryption key for secrets

```zsh
sudo pacman --needed -S gnupg sops
```

Generate GPG RSA key pair without password.

```zsh
export KEY_NAME="homelab"
export KEY_COMMENT="flux secrets"

gpg --batch --full-generate-key <<EOF
%no-protection
Key-Type: 1
Key-Length: 4096
Subkey-Type: 1
Subkey-Length: 4096
Expire-Date: 0
Name-Comment: ${KEY_COMMENT}
Name-Real: ${KEY_NAME}
EOF
```

The output shows the footprint of the new key.

```
gpg: revocation certificate stored as
'~/.gnupg/openpgp-revocs.d/E583935F5865EDC23D5181A91E3CEBDDA65179A0.rev'
```

The footprint isn't secret and it's no problem for it to show up in your shell
history.

```zsh
export KEY_FP=E583935F5865EDC23D5181A91E3CEBDDA65179A0
```

Create the `sops-gpg` secret in Kubernetes which contains the private key.

```zsh
gpg --export-secret-keys --armor "${KEY_FP}" |
kubectl create secret generic sops-gpg \
--namespace=flux-system \
--from-file=sops.asc=/dev/stdin
```

Store the public key in the Git repository so the DevOps team can encrypt
secrets. They can't decrypt them with the public key.

```zsh
gpg --export --armor "${KEY_FP}" > ./clusters/production/.sops.pub.asc
```

Commit the public key

```zsh
git add ./clusters/production/.sops.pub.asc
git commit -m 'ops: add public key for secrets generation'
```

You can now delete the private key from your personal computer.

```zsh
gpg --delete-secret-keys "${KEY_FP}"
```

Developing
==========

## 1 Create secrets

```zsh
gpg --import ./clusters/production/.sops.pub.asc
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

You can check if the OCIRepository is not even loaded, OCI is sometimes used
for Helm.

```zsh
flux get sources oci -A
```
