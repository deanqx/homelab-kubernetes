Installation
============

## 0 Prerequisites (Local Machine)

Install the required CLI tools on your personal system:

```bash
sudo pacman --needed -S kubectl helm flux cilium-cli sops age pwgen
```

Cilium is used as firewall for the host system, any host firewall like
`iptables` or `nftables` have to be disabled. All host ports are currently not
restricted.

## 1 K3s Setup

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

After deploying k3s, copy `/etc/rancher/k3s/k3s.yaml` to your local
machine `~/kube/config` as described in the following. This config contains
the Kubernetes API access key and a CA certificate for TLS.

**On the server:**

```bash
sudo cp /etc/rancher/k3s/k3s.yaml ~
sudo chown $(whoami):users ~/k3s.yaml
```

Delete `~/k3s.yaml` after completing the next step.

**On your local machine:**

```bash
scp <SERVER_HOSTNAME>:k3s.yaml ~/.kube/config
sed -i 's/127.0.0.1/<SERVER_HOSTNAME>/' ~/.kube/config
```

Verify connection to Kubernetes.

**Note:** Because there is no CNI installed yet, your nodes will show as
NotReady if you run `kubectl get nodes`. This is completely normal and
will be fixed as soon as Cilium is installed.

```bash
kubectl get nodes
```

## 2 Cilium Deployment

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
into a temporary file `cilium_values.yaml`. Some values may have to be adjusted
for the current setup.

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

## 3 FluxCD Deployment

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

Next complete
[Generate encryption key for secrets](#generate-encryption-key-for-secrets).

## 4 Longhorn storage

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

## 5 Verify working installation

All Kustomizations should be ready now.

```bash
flux get kustomization
```

## 6 Create S3 Buckets

Loki the log database requires S3 and the buckets have to created manually.

Run port forwarding in the background.

```bash
kubectl -n monitoring port-forward svc/seaweedfs-s3 8333
```

I recommend the Minio CLI over the AWS CLI because the AWS CLI is build for AWS
services. The Minio CLI on the other hand is made for self-hosted S3.

```bash
mcli mb homelab_monitoring/chunks
mcli mb homelab_monitoring/ruler
```

## 7 Setup Backup Server

### Setup S3

```bash
cd backup-system
```

**Warning:** The files `docker-compose.yaml` and `garage.toml` contain secrets,
these have to be regenerated for production use.

```bash
sudo docker compose up -d
sudo docker compose logs
```

The script serves as an example and should not be used directly in a production
environment without reviewing it first:

```bash
./setup_garage.sh
```

Copy extract these values from `backup-system/docker-compose.yaml`:

```bash
export GARAGE_DEFAULT_ACCESS_KEY=GK0d12a14e9397dd5e222b7b4d
export GARAGE_DEFAULT_SECRET_KEY=pcyhu9yhzJUCsa4yX37twEC3c
```

```bash
mcli alias set homelab_backup http://localhost:3900 \
$GARAGE_DEFAULT_ACCESS_KEY \
$GARAGE_DEFAULT_SECRET_KEY
```

```bash
mcli ls homelab_backup
```

If no errors occurred S3 is ready for the next steps.
