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

## 1 Firewall

Cilium is used as firewall for the host system and services like SSH on port 22
are automatically detected.


Open port `6443` and `10250` in the host firewall
([See Kubernetes Ports](https://kubernetes.io/docs/reference/networking/ports-and-protocols/)).

## 2 K3s Setup

SSH into your server and install K3s.

```zsh
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

```zsh
sudo cp /etc/rancher/k3s/k3s.yaml ~
sudo chown $(whoami):users ~/k3s.yaml
```

Delete `~/k3s.yaml` after completing the next step.

**On your local machine:**

```zsh
scp <SERVER>:k3s.yaml ~/.kube/config
sed -i 's/127.0.0.1/<SERVER_HOSTNAME>/' ~/.kube/config
```

Verify connection to Kubernetes.

**Note:** Because there is no CNI installed yet, your nodes will show as
NotReady if you run kubectl get nodes. This is completely normal and
will be fixed as soon as Cilium is installed.

```zsh
kubectl get nodes
```

## 3 Cilium Installation

Cilium is the networking, security, and observability engine for this
Kubernetes cluster.

**Warning:** Make sure to disable `checkReversePath` in your Firewall.

Because this Guide uses the new Gateway API of Kubernetes we need to install
the necessary CRDs (Custom Resource Definitions).
The following example uses version `1.5.1`, you can find the latest here
[latest](https://github.com/kubernetes-sigs/gateway-api/releases).
Cilium requires the Experimental CRDs

```zsh
kubectl apply --server-side -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.5.1/experimental-install.yaml
```

Now Cilium is getting installed.
Modify `--version` to the [latest](https://github.com/cilium/cilium/releases).

```zsh
cilium-cli install --version 1.19.4 \
  --set gatewayAPI.enabled=true \
  --set hostFirewall.enabled=true \
  --set l2announcements.enabled=true \
  --set bpf.masquerade=true \
  --set kubeProxyReplacement=true \
  --set ipam.operator.clusterPoolIPv4PodCIDRList="{10.42.0.0/16}" \
  --set k8sClientRateLimit.qps=20 \
  --set k8sClientRateLimit.burst=40
```

- `l2announcements.enabled=true`: Enables the Layer 2 Layer Load Balancer
  feature, allowing Cilium to respond to ARP requests and host Virtual IPs
  on your local network.

- `hostFirewall.enabled=true`: Use Cilium as host firewall.

- `bpf.masquerade=true`: Enable native IP masquerade support in eBPF.

- `kubeProxyReplacement=true`: Tells Cilium to fully replace kube-proxy using
  high-performance eBPF routing instead of legacy iptables.

- `ipam.operator.clusterPoolIPv4PodCIDRList="{10.42.0.0/16}"`:
  Sets the IP address range assigned to Pods, precisely matching k3s's
  default internal network.

- `k8sClientRateLimit.qps=20 & --set k8sClientRateLimit.burst=40`:
  Increases how fast Cilium is allowed to talk to the Kubernetes API.
  This prevents Cilium from being throttled due to the high volume of
  rapid lease updates required by L2 announcements.

### Validate the Installation

To validate that Cilium has been properly installed, you can run:

```zsh
cilium-cli status --wait
```

All Pods should now be ready (like `coredns` and `metrics-server`):

```zsh
kubectl -n kube-system get pod
```


Run the following command to validate that your cluster has proper network
connectivity:

```zsh
cilium-cli connectivity test
```

To prevent future problems make sure that all tests pass. If some tests fail
try turning off (= 0) reverse path filtering on the server:

```zsh
sysctl net.ipv4.conf.all.rp_filter
sysctl net.ipv4.conf.default.rp_filter
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

## 4 FluxCD Deployment

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
kubectl apply -f clusters/production/flux-network-policy.yaml
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

## 5 Generate encryption key for secrets

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

## 6 Longhorn storage

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

## 7 Verify working installation

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
