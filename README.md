GitOps is a practice where a Git repository acts as the single source of truth
for your infrastructure, automatically syncing and self-healing your live
system to match whatever code is merged into Git.

This reposotitory uses Kubernetes with FluxCD.
You should be familiar with the basics of these technologies.
The example repo was used as reference:
[fluxcd/flux2-kustomize-helm-example](https://github.com/fluxcd/flux2-kustomize-helm-example)

The entry point for FluxCD is `clusters/production`.
From there it uses Kustomization files to find the manifests.

Installation
============

## Longhorn

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

Usage
=====

## Check changes

The diff command is used to do a server-side dry-run on flux resources
and print the difference.

```zsh
flux diff kustomization my-app --path apps/${APP}
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

## Flux is not applying changes

The most common cause is that newly created manifests are no specified in
Kustomization files. To verify that Flux applied the latest git commit:
 
```zsh
flux get kustomizations
```

The output should look something like this:

```
NAME             	REVISION          	SUSPENDED	READY	MESSAGE
flux-system      	main@sha1:b8fc2d1f	False    	True 	Applied revision: main@sha1:b8fc2d1f	
infra-configs    	main@sha1:b8fc2d1f	False    	True 	Applied revision: main@sha1:b8fc2d1f	
infra-controllers	main@sha1:b8fc2d1f	False    	True 	Applied revision: main@sha1:b8fc2d1f
```
