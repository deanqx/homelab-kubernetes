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

- Cilium
- Longhorn
- Mozilla SOPS is used to encrypt secrets like database passwords.

Installation
============

## 0 Prerequisites (Local Machine)

Install the required CLI tools on your personal system:

```zsh
sudo pacman --needed -S kubectl helm flux cilium-cli sops age pwgen
```

## 1 K3s Setup

Open port `6443` and `10250` in the host firewall
([See Kubernetes Ports](https://kubernetes.io/docs/reference/networking/ports-and-protocols/)).

SSH into your server and configure K3s. In this case in form of a
NixOS configuration, important are the `extraFlags`.

```nix
services.k3s = {
  enable = true;
  role = "server";
  extraFlags = [ # installing manually
    "--flannel-backend=none"
    "--disable=traefik"
    "--disable=servicelb"
    "--disable=network-policy"
    "--disable=kube-proxy"
    "--disable=helm"
  ];
};
```

After deploying the config, copy the kubeconfig to your local machine.

**On the server:**

```zsh
sudo cp /etc/rancher/k3s/k3s.yaml ~
sudo chown $(whoami):users ~/k3s.yaml
```

**On your local machine:**

```zsh
scp <SERVER>:k3s.yaml ~/.kube/config
sed -i 's/127.0.0.1/<SERVER_HOSTNAME>/' ~/.kube/config
```

Verify connection to Kubernetes:

```zsh
kubectl get nodes
```

## 2 Cilium Installation

Cilium is the networking, security, and observability engine for this
Kubernetes cluster.

**Warning:** Make sure to disable `checkReversePath` in your Firewall.

Verify your Helm values, install Cilium with Gateway API enabled, and wait
for deployment:

```zsh
cilium-cli install --dry-run-helm-values
```

Example output:

```
cluster:
  name: default
k8sServiceHost: dean-homelab
k8sServicePort: 6443
kubeProxyReplacement: true
operator:
  replicas: 1
routingMode: tunnel
tunnelProtocol: vxlan
```

```zsh
cilium-cli install --helm-set gatewayAPI.enabled=true
cilium-cli status --wait
```

### GitOps Sync

Ensure the Cilium version and Helm values in your Git repo match your live
cluster:

```zsh
cilium-cli version
helm get values cilium -n kube-system -o yaml
```

Update `infrastructure/controllers/cilium.yaml` with the correct
`OCIRepository.spec.ref.semver` and `HelmRelease.spec.values`
based on the output above.

## 3 FluxCD Deployment

### Generate Deployment Keys

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

### Prepare Flux Secrets

Add SSH key and known hosts as secret.

```zsh
ssh-keyscan codeberg.org > /tmp/flux_known_hosts
```

```zsh
kubectl create namespace flux-system
kubectl create secret generic flux-system \
  --namespace=flux-system \
  --from-file=identity=/tmp/flux_ssh \
  --from-file=known_hosts=/tmp/flux_known_hosts
```

### Install Flux

```zsh
kubectl apply -f clusters/production/flux-system/gotk-components.yaml
```

Check if Pods are ready:

```zsh
kubectl -n flux-system get pod
```

Update the specified repository URL in `gotk-sync.yaml`, then apply it:

```zsh
kubectl apply -f clusters/production/flux-system/gotk-sync.yaml
```

Check if installation was successful (all except `apps` should be ready):

```zsh
flux get kustomization
```

## 4 Generate encryption key for secrets

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
[create secrets section](#create-secrets).

## 5 Longhorn storage

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

## 6 Verify working installation

All Kustomizations should be ready now.

```zsh
flux get kustomization
```

Developing
==========

## Create secrets

In this example a password for Postgresql with a length of 16 characters
is generated and encrypted.

```zsh
kubectl -n default create secret generic postgresql \
--namespace=nextcloud \
--from-literal=admin-password=$(pwgen -sBcn 20 1) \
--from-literal=user-password=$(pwgen -sBcn 20 1) \
--from-literal=replication-password=$(pwgen -sBcn 20 1) \
--from-literal=metrics-password=$(pwgen -sBcn 20 1) \
--dry-run=client \
-o yaml > apps/production/secrets/nextcloud-postgresql.yaml
```

Encrypt the created secrets using the `sops` CLI.

```zsh
sops --encrypt --in-place apps/production/secrets/nextcloud-postgresql.yaml
```

Update `apps/production/kustomization.yaml` to include the new secrets.
Make sure to add the secret before the HelmRelease.

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - secrets/nextcloud-postgresql.yaml
  - ...
```

## Check changes

The diff command is used to do a server-side dry-run on flux resources
and print the difference.

```zsh
flux diff kustomization my-app --path apps/<app>
```

`my-app` refers to the deployment in the cluster.

## Apply changes in the cluster

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

### Changes are not applied

Keep in mind that the apply process (reconcilation) can take a few minutes.
To verify that Flux applied the latest git commit:

```zsh
flux get kustomization
```

Check if Helm installations were successful:

```zsh
flux get helmreleases -A
```

Alternatively you can check all Flux resources with:

```zsh
flux get all -A
```

If a Helm installation failed too many times, it goes into a timeout state.
You can restart the installation of a Chart with:

```zsh
kubectl -n flux-system rollout restart deploy helm-controller
```
