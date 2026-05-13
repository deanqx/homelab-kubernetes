GitOps is a practice where a Git repository acts as the single source of truth
for your infrastructure, automatically syncing and self-healing your live system
to match whatever code is merged into Git.

This reposotitory uses Kubernetes with FluxCD.
You should be familiar with the basics of these technologies.
The example repo was used as reference: [fluxcd/flux2-kustomize-helm-example](https://github.com/fluxcd/flux2-kustomize-helm-example)

# Installation

## Longhorn

install iscsi

check preflight
https://longhorn.io/docs/1.11.2/advanced-resources/longhornctl/

curl -L https://github.com/longhorn/cli/releases/download/${LonghornVersion}/longhornctl-${OS}-${ARCH} -o longhornctl
chmod +x longhornctl
sudo -E ./longhornctl install preflight
sudo -E ./longhornctl check preflight

# Usage

git add -A
git commit -m "feat: ..."
git push

# Troubleshooting

git revert ...
