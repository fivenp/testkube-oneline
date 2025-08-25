FROM alpine:3.20

ARG KUBECTL_VERSION=v1.30.4
ARG HELM_VERSION=v3.18.4
ARG K3D_VERSION=v5.8.3
ARG TESTKUBE_VERSION=v2.2.2

RUN apk add --no-cache bash curl ca-certificates jq coreutils tar gzip

# kubectl
RUN curl -fsSL -o /usr/local/bin/kubectl \
  https://storage.googleapis.com/kubernetes-release/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl \
  && chmod +x /usr/local/bin/kubectl

# helm
RUN curl -fsSL https://get.helm.sh/helm-${HELM_VERSION}-linux-amd64.tar.gz \
  | tar -xz -C /tmp \
  && mv /tmp/linux-amd64/helm /usr/local/bin/helm \
  && chmod +x /usr/local/bin/helm

# k3d
RUN curl -fsSL https://github.com/k3d-io/k3d/releases/download/${K3D_VERSION}/k3d-linux-amd64 \
  -o /usr/local/bin/k3d \
  && chmod +x /usr/local/bin/k3d

# Testkube CLI
RUN set -eux; \
  mkdir -p /tmp/tk && cd /tmp/tk; \
  curl -fsSL https://github.com/kubeshop/testkube/releases/download/${TESTKUBE_VERSION}/testkube_${TESTKUBE_VERSION#v}_Linux_x86_64.tar.gz \
    -o tk.tgz || true; \
  if [ -s tk.tgz ]; then \
    tar -xzf tk.tgz; \
    if [ -f testkube ]; then install -m 0755 testkube /usr/local/bin/testkube; fi; \
    if [ -f kubectl-testkube ]; then install -m 0755 kubectl-testkube /usr/local/bin/kubectl-testkube; fi; \
  fi; \
  if ! command -v testkube >/dev/null 2>&1; then \
    echo "Falling back to install script"; \
    curl -fsSL https://raw.githubusercontent.com/kubeshop/testkube/main/scripts/install.sh | bash; \
    [ -f ./testkube ] && install -m 0755 ./testkube /usr/local/bin/testkube || true; \
    [ -f ./kubectl-testkube ] && install -m 0755 ./kubectl-testkube /usr/local/bin/kubectl-testkube || true; \
  fi; \
  command -v testkube && testkube version || true

WORKDIR /work
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENV KUBECONFIG=/root/.kube/config
ENTRYPOINT ["/entrypoint.sh"]
