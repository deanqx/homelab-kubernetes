Overview
========

## Technologies

- Kubernetes (k3s): compliant lightweight version of Kubernetes which is used
  to orchestrate the cluster.

- Cilium: CNI (Container Network Interface), completely replaces the host
  firewall and kube-proxy

- Flux CD: GitOps tool for Kubernetes

- Mozilla SOPS: encrypts secrets

- Longhorn: storage over multiple nodes

- Databases: like PostgreSQL or Redis

## Getting started

GitOps is a practice where a Git repository acts as the single source of truth
for your infrastructure, automatically syncing and self-healing your live
system to match whatever code is merged into Git.

This repository uses Kubernetes with FluxCD.
You should be familiar with the basics of these technologies.
The example repo was used as reference:
[fluxcd/flux2-kustomize-helm-example](https://github.com/fluxcd/flux2-kustomize-helm-example)

The entry point for FluxCD is `clusters/production`.
From there it uses Kustomization files to find the manifests.

This cluster has 3 nodes in 3 locations, to provide data integrity at all times.

## Deployed in Cluster

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

Installation
============

## 0 Prerequisites (Local Machine)

Install the required CLI tools on your personal system:

```bash
sudo pacman --needed -S kubectl helm flux cilium-cli sops age pwgen
```

## 1 Firewall

Cilium is used as firewall for the host system and services like SSH on port 22
are automatically detected.

Open port `6443` and `10250` in the host firewall
([See Kubernetes Ports](https://kubernetes.io/docs/reference/networking/ports-and-protocols/)).

## 2 K3s Setup

SSH into your server and install K3s.

```bash
curl -sfL https://get.k3s.io | sh -s - server \
  --cluster-init \
  --flannel-backend=none \
  --disable-kube-proxy \
  --disable-network-policy \
  --disable=traefik \
  --disable=servicelb
```

- `--cluster-init`: Tells K3s to initialize an internal, embedded etcd database
  on this first node. This allows you to easily join more master nodes later to
  form a High-Availability (HA) cluster without setting up an external database.

- `--disable-kube-proxy` and `--flannel-backend=none`: Disables kube-proxy and
  Flannel, the default K3s network provider (CNI). This leaves the cluster's
networking completely blank, so Cilium can take it over.

- `--disable-network-policy`: Turns off K3s's built-in network policy agent.
  Since that default agent relies on Flannel and kube-proxy, keeping it on
  would cause errors. Cilium will handle your network policies natively.
  The iptables now only contain Kubelet rules.

- `--disable=traefik`: Traefik Ingress controller is replaced with Cilium Envoy.

- `--disable=servicelb`: Disable built-in LoadBalancer controller (Klipper LB).
  Cilium will be used instead.

After deploying the config, copy the kubeconfig to your local machine.

**On the server:**

```bash
sudo cp /etc/rancher/k3s/k3s.yaml ~
sudo chown $(whoami):users ~/k3s.yaml
```

Delete `~/k3s.yaml` after completing the next step.

**On your local machine:**

```bash
scp <SERVER>:k3s.yaml ~/.kube/config
sed -i 's/127.0.0.1/<SERVER_HOSTNAME>/' ~/.kube/config
```

Verify connection to Kubernetes.

**Note:** Because there is no CNI installed yet, your nodes will show as
NotReady if you run kubectl get nodes. This is completely normal and
will be fixed as soon as Cilium is installed.

```bash
kubectl get nodes
```

## 3 Cilium Deployment

Think of Cilium as a distributed virtual switch and firewall running directly
inside the Linux kernel. Instead of relying on slow legacy routing
rules (iptables), it uses eBPF to inject bytecode into the network stack,
letting it route, NAT, and secure traffic at wire speed. By using VXLAN,
it abstracts the local Pod IP addresses, allowing your multi-location nodes
to talk to each other without needing complex BGP peering or route propagation
on your physical WAN routers.

### Gateway API Installation

Because this Guide uses the new Gateway API of Kubernetes we need to install
the necessary CRDs (Custom Resource Definitions).
The following example uses version `1.5.1`, you can find the latest here
[latest](https://github.com/kubernetes-sigs/gateway-api/releases).
Cilium requires the Experimental CRDs

```bash
kubectl apply --server-side -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.5.1/experimental-install.yaml
```

### Cilium Installation

Copy the Helm values from `infrastructure/controllers/cilium.yaml` and store it
into a temporary file `cilium_values.yaml`.

`infrastructure/controllers/cilium.yaml`:

```yaml
spec:
  values:
    cluster:
      name: default
...
```

`cilium_values.yaml`:

```yaml
cluster:
  name: default
...
```

Make sure the version is matching Flux's in `clusters/production/infrastructure.yaml`.
Optionally modify the version to the [latest](https://github.com/cilium/cilium/releases).

```bash
helm install cilium oci://ghcr.io/cilium/charts/cilium \
--version 1.19.4 --values cilium_values.yaml
```

### Validate the Installation

To validate that Cilium has been properly installed, you can run:

```bash
cilium-cli status --wait
```

All Pods should now be ready (like `coredns` and `metrics-server`):

```bash
kubectl -n kube-system get pod
```

Run the following command to validate that your cluster has proper network
connectivity:

```bash
cilium-cli connectivity test
```

To prevent future problems make sure that all tests pass. If some tests fail
try turning off (= 0) reverse path filtering on the server:

```bash
sysctl net.ipv4.conf.all.rp_filter
sysctl net.ipv4.conf.default.rp_filter
```

### GitOps Sync

In the next step Flux will be installed and to make Flux manage the Cilium
installation the configuration in the Git repository has to match.

Ensure the Cilium version and Helm values in your Git repo match your live
cluster:

```bash
cilium-cli version
helm get values cilium -n kube-system -o yaml
```

Update `infrastructure/controllers/cilium.yaml` with the correct
`OCIRepository.spec.ref.semver` and `HelmRelease.spec.values`
based on the output above.

Furthermore, the Gateway API CRDs version should also be adjusted in
`clusters/production/infrastructure.yaml`, version `1.5.1`
was used in this guide.

Before continuing push the updated `cilium.yaml` to Git.

## 4 FluxCD Deployment

### Generate Deployment Keys

Generate SSH Key without password and save it to a temporary location.

```bash
ssh-keygen -t ed25519 -C "flux@homelab"
```

Output and `/tmp/flux_ssh` entered:

```
Generating public/private ed25519 key pair.
Enter file in which to save the key (/home/dean/.ssh/id_ed25519): /tmp/flux_ssh
```

Give read permissions of public key (`/tmp/flux_ssh.pub`) to Git repository.

```bash
cat /tmp/flux_ssh.pub
```

### Set Flux Credentials

Add SSH key and known hosts as secret.

```bash
ssh-keyscan -T 240 codeberg.org | tee /tmp/flux_known_hosts
```

```bash
kubectl create namespace flux-system
kubectl create secret generic flux-system \
  --namespace=flux-system \
  --from-file=identity=/tmp/flux_ssh \
  --from-file=known_hosts=/tmp/flux_known_hosts
```

### Install Flux

```bash
kubectl apply -f clusters/production/flux-system/gotk-components.yaml
```

Check if Pods are ready:

```bash
kubectl -n flux-system get pod
```

Update the specified repository URL in `gotk-sync.yaml`, then apply it:

```bash
kubectl apply -f clusters/production/flux-system/gotk-sync.yaml
```

Check if installation was successful (all Kustomizations except `apps` should be ready):

```bash
flux get source git
flux get kustomization
```

## 5 Generate encryption key for secrets

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

## 6 Longhorn storage

### Installation

Before this repository can be deployed on the cluster,
you need to install `iscsi` with your package manager.

### Check installation requirements

[Longhorn CLI Docs](https://longhorn.io/docs/1.11.2/advanced-resources/longhornctl/)

```bash
curl -L https://github.com/longhorn/cli/releases/download/xxx -o longhornctl
chmod +x longhornctl
sudo -E ./longhornctl install preflight
sudo -E ./longhornctl check preflight
```

## 7 Verify working installation

All Kustomizations should be ready now.

```bash
flux get kustomization
```

Developing
==========

## Create secrets

In this example a password for Postgresql with a length of 16 characters
is generated and encrypted.

```bash
kubectl -n default create secret generic postgresql \
--namespace=nextcloud \
--from-literal=username=nextcloud \
--from-literal=admin-password=$(pwgen -sBcn 20 1) \
--from-literal=user-password=$(pwgen -sBcn 20 1) \
--from-literal=replication-password=$(pwgen -sBcn 20 1) \
--from-literal=metrics-password=$(pwgen -sBcn 20 1) \
--dry-run=client \
-o yaml > apps/production/nextcloud/database/postgresql-secret.yaml
```

Encrypt the created secrets using the `sops` CLI.

```bash
sops --encrypt --in-place apps/production/nextcloud/database/postgresql-secret.yaml
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

## Undo faulty cluster change

```bash
git revert <working-commit-hash>
```

## FluxCD

It is recommended that the Flux CLI is installed on your local machine.

### Changes are not applied

Keep in mind that the apply process (reconcilation) can take a few minutes.
To verify that Flux applied the latest git commit:

```bash
flux get kustomization
```

Check if Helm installations were successful:

```bash
flux get helmreleases -A
```

Alternatively you can check all Flux resources with:

```bash
flux get all -A
```

If a Helm installation failed too many times, it goes into a timeout state.
You can restart the installation of a Chart with:

```bash
kubectl -n flux-system rollout restart deploy helm-controller
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
