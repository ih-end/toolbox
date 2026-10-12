# syntax=docker/dockerfile:1
ARG ALPINE_VERSION=latest

# ---- Stage 1: download and verify static binaries ----
FROM alpine:${ALPINE_VERSION} AS binaries
ARG TARGETARCH
# "latest" resolves the newest stable release at build time; set an explicit version to pin.
ARG KUBECTL_VERSION=latest
ARG HELM_VERSION=latest
ARG TERRAFORM_VERSION=latest

RUN apk add --no-cache curl jq unzip
WORKDIR /out
RUN set -eux; \
    ARCH="${TARGETARCH:-$(apk --print-arch | sed 's/x86_64/amd64/;s/aarch64/arm64/')}"; \
    KUBECTL_VERSION="$([ "${KUBECTL_VERSION}" = latest ] && curl -fsSL https://dl.k8s.io/release/stable.txt || echo "${KUBECTL_VERSION}")"; \
    HELM_VERSION="$([ "${HELM_VERSION}" = latest ] && curl -fsSL https://get.helm.sh/helm-latest-version || echo "${HELM_VERSION}")"; \
    TERRAFORM_VERSION="$([ "${TERRAFORM_VERSION}" = latest ] && curl -fsSL https://checkpoint-api.hashicorp.com/v1/check/terraform | jq -er .current_version || echo "${TERRAFORM_VERSION}")"; \
    echo "kubectl=${KUBECTL_VERSION} helm=${HELM_VERSION} terraform=${TERRAFORM_VERSION}"; \
    \
    curl -fsSLO "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${ARCH}/kubectl"; \
    echo "$(curl -fsSL "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${ARCH}/kubectl.sha256")  kubectl" | sha256sum -c -; \
    \
    curl -fsSLO "https://get.helm.sh/helm-${HELM_VERSION}-linux-${ARCH}.tar.gz"; \
    curl -fsSL "https://get.helm.sh/helm-${HELM_VERSION}-linux-${ARCH}.tar.gz.sha256sum" | sha256sum -c -; \
    tar -xzf "helm-${HELM_VERSION}-linux-${ARCH}.tar.gz" --strip-components=1 "linux-${ARCH}/helm"; \
    \
    TF_ZIP="terraform_${TERRAFORM_VERSION}_linux_${ARCH}.zip"; \
    curl -fsSLO "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/${TF_ZIP}"; \
    curl -fsSL "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_SHA256SUMS" | grep " ${TF_ZIP}\$" | sha256sum -c -; \
    unzip -q "${TF_ZIP}" terraform; \
    \
    chmod 0755 kubectl helm terraform

# ---- Stage 2: Azure CLI in a venv (needs a compiler; build tools stay out of the final image) ----
FROM alpine:${ALPINE_VERSION} AS azure-cli
ARG AZURE_CLI_VERSION=
RUN apk add --no-cache python3 python3-dev py3-pip gcc musl-dev libffi-dev openssl-dev cargo make
RUN python3 -m venv /opt/az \
    && /opt/az/bin/pip install --no-cache-dir --upgrade pip \
    && /opt/az/bin/pip install --no-cache-dir "azure-cli${AZURE_CLI_VERSION:+==${AZURE_CLI_VERSION}}" \
    && /opt/az/bin/pip uninstall -y pip \
    && find /opt/az -type d -name __pycache__ -prune -exec rm -rf {} +

# ---- Stage 3: final image ----
FROM alpine:${ALPINE_VERSION}

LABEL org.opencontainers.image.title="toolbox" \
      org.opencontainers.image.description="Alpine-based image for CI/CD jobs and Kubernetes/infrastructure debugging" \
      org.opencontainers.image.source="https://github.com/ih-end/toolbox"

RUN apk upgrade --no-cache \
    && apk add --no-cache \
        bash bash-completion ca-certificates tzdata \
        curl jq yq-go git openssh-client-default openssl gnupg \
        python3 \
        bind-tools iputils netcat-openbsd tcpdump mtr \
        gettext-envsubst coreutils findutils grep sed gawk tar gzip unzip less \
        procps htop vim nano ripgrep k9s \
    && addgroup -g 10001 toolbox \
    && adduser -D -u 10001 -G toolbox -s /bin/bash toolbox \
    && mkdir /workspace && chown toolbox:toolbox /workspace

COPY --from=binaries /out/kubectl /out/helm /out/terraform /usr/local/bin/
COPY --from=azure-cli /opt/az /opt/az
RUN ln -s /opt/az/bin/az /usr/local/bin/az

ENV AZURE_CONFIG_DIR=/home/toolbox/.azure \
    KUBECONFIG=/home/toolbox/.kube/config \
    TF_IN_AUTOMATION=1 \
    HELM_CACHE_HOME=/tmp/helm/cache \
    HELM_CONFIG_HOME=/tmp/helm/config \
    HELM_DATA_HOME=/tmp/helm/data

USER 10001:10001
WORKDIR /workspace
CMD ["bash"]
