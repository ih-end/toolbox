# toolbox

Alpine-based image for CI/CD jobs and Kubernetes/infrastructure debugging. Rebuilt every Sunday at 02:00 UTC on the latest `alpine` base, always with the latest stable `kubectl`, `helm`, `terraform` and Azure CLI.

## Contents

- Core: `curl`, `jq`, `yq`, `git`, `bash`, `openssl`, `gnupg`, `openssh-client`, CA certificates
- Platform: `kubectl`, `helm`, `terraform`, `az` (Azure CLI), `k9s`
- Debugging: `dig`, `ping`, `nc`, `tcpdump`, `mtr`, `htop`, `ripgrep`, `envsubst`, `vim`, `nano`

## Usage

```sh
docker run --rm -it -v "$PWD:/workspace" ghcr.io/ih-end/toolbox:latest
kubectl run toolbox --rm -it --image=ghcr.io/ih-end/toolbox:latest -- bash
```

Tags: `latest`, `YYYYMMDD-HHmmss` (unique per build), `sha-<commit>`. Images are stored in GitHub Container Registry; only the last 3 releases are kept.

## Security

- Runs as non-root (uid/gid 10001); build tools are left out of the final image.
- Downloaded binaries are SHA-256 verified.
- The pipeline smoke-tests the image, runs Trivy (fails on fixable HIGH/CRITICAL), publishes SBOM and provenance, and signs with keyless cosign.

```sh
cosign verify ghcr.io/ih-end/toolbox:latest \
  --certificate-identity-regexp 'https://github.com/ih-end/toolbox/.*' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com
```

## Build

```sh
docker build -t toolbox .
docker build --build-arg HELM_VERSION=v3.19.0 -t toolbox .   # optional pin
```

The image is `linux/amd64` only; arm64 needs a native arm runner because the Azure CLI compiles dependencies.