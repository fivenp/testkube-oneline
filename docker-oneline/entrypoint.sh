#!/usr/bin/env bash
set -euo pipefail

CLUSTER_NAME="${CLUSTER_NAME:-tk-local}"
K3D_SERVERS="${K3D_SERVERS:-1}"
K3D_AGENTS="${K3D_AGENTS:-2}"
API_PORT="${API_PORT:-6445}"
K8S_NS="${K8S_NS:-testkube}"
WORKFLOW_FILE="${WORKFLOW_FILE:-/work/testworkflow.yaml}"
WORKFLOW_NAME="${WORKFLOW_NAME:-}"
FOLLOW_LOGS="${FOLLOW_LOGS:-true}"

echo ">> Checking docker socket..."
[ -S /var/run/docker.sock ] || { echo "ERROR: /var/run/docker.sock not mounted."; exit 1; }

echo ">> Ensure k3d cluster exists: $CLUSTER_NAME"
if k3d cluster list | grep -q "^${CLUSTER_NAME}\b"; then
  echo "   Cluster exists, skipping creation."
else
  k3d cluster create "$CLUSTER_NAME" \
    --servers "$K3D_SERVERS" \
    --agents "$K3D_AGENTS" \
    --api-port "0.0.0.0:${API_PORT}" \
    --wait
fi

# Get kubeconfig & server URL
ORIG_CFG="$(k3d kubeconfig get "$CLUSTER_NAME")"
ORIG_SERVER="$(printf "%s" "$ORIG_CFG" | awk '/server: /{print $2; exit}')"

# If API not published to host, recreate with --api-port
if printf "%s" "$ORIG_SERVER" | grep -Eq 'https://k3d-|https://127\.0\.0\.1:6443|https://localhost:6443'; then
  echo ">> Cluster API is not exposed on host. Recreating with --api-port ${API_PORT}..."
  k3d cluster delete "$CLUSTER_NAME" || true
  k3d cluster create "$CLUSTER_NAME" \
    --servers "$K3D_SERVERS" \
    --agents "$K3D_AGENTS" \
    --api-port "0.0.0.0:${API_PORT}" \
    --wait
  ORIG_CFG="$(k3d kubeconfig get "$CLUSTER_NAME")"
  ORIG_SERVER="$(printf "%s" "$ORIG_CFG" | awk '/server: /{print $2; exit}')"
fi

# Point kubeconfig at host API (so this container can reach it)
mkdir -p /root/.kube
KUBECONFIG_PATH=/root/.kube/config
HOST_API="https://host.docker.internal:${API_PORT}"
echo ">> Writing kubeconfig targeting ${HOST_API}"
printf "%s" "$ORIG_CFG" | sed -E "s#server: https?://[^ ]+#server: ${HOST_API}#g" > "${KUBECONFIG_PATH}"
export KUBECONFIG="${KUBECONFIG_PATH}"
kubectl config use-context "k3d-${CLUSTER_NAME}" >/dev/null 2>&1 || true

# Wait for API healthz
echo -n ">> Waiting for Kubernetes API to respond"
for i in {1..90}; do
  if kubectl get --raw='/healthz' >/dev/null 2>&1; then
    echo
    break
  fi
  echo -n .
  sleep 1
done
if ! kubectl get --raw='/healthz' >/dev/null 2>&1; then
  echo
  echo "Kubernetes API not reachable"
  exit 1
fi

echo ">> Kubernetes nodes:"
kubectl get nodes -o wide || true

# Ensure the plugin exists
if ! command -v kubectl-testkube >/dev/null 2>&1; then
  echo "ERROR: kubectl-testkube plugin not found in image"; exit 1
fi

echo ">> Ensuring Testkube is installed in namespace: $K8S_NS"
kubectl get ns "$K8S_NS" >/dev/null 2>&1 || kubectl create ns "$K8S_NS" >/dev/null

# Robust check: deployments with Testkube label
DEPLOY_COUNT="$(kubectl -n "$K8S_NS" get deploy -l app.kubernetes.io/part-of=testkube -o jsonpath='{.items[*].metadata.name}' 2>/dev/null | wc -w || true)"
if [ "${DEPLOY_COUNT:-0}" -gt 0 ]; then
  echo "   Testkube appears installed (${DEPLOY_COUNT} deployments)."
else
  echo ">> Installing Testkube (standalone)..."
  kubectl-testkube init demo --namespace "$K8S_NS" --no-confirm
fi

# Wait until pods exist before waiting for Ready
echo -n ">> Waiting for Testkube pods to appear"
for i in {1..120}; do
  PODS_NOW="$(kubectl -n "$K8S_NS" get pods -l app.kubernetes.io/part-of=testkube --no-headers 2>/dev/null | wc -l || true)"
  if [ "${PODS_NOW:-0}" -gt 0 ]; then
    echo
    break
  fi
  echo -n .
  sleep 1
done
if [ "${PODS_NOW:-0}" -eq 0 ]; then
  echo
  echo "No Testkube pods found after waiting."
  kubectl -n "$K8S_NS" get all || true
  exit 1
fi

echo ">> Waiting for Testkube pods to be Ready..."
if ! kubectl wait --for=condition=Ready pod -l app.kubernetes.io/part-of=testkube -n "$K8S_NS" --timeout=300s; then
  echo "Pods did not become Ready in time. Current state:"
  kubectl get pods -n "$K8S_NS" -o wide
  ONE_POD="$(kubectl -n "$K8S_NS" get pods -l app.kubernetes.io/part-of=testkube -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
  [ -n "$ONE_POD" ] && kubectl -n "$K8S_NS" describe pod "$ONE_POD" || true
  exit 1
fi

# (Optional but helpful) make sure the TestWorkflow CRD exists before we apply/run
echo -n ">> Waiting for TestWorkflow CRD to be registered"
for i in {1..90}; do
  if kubectl get crd testworkflows.tests.testkube.io >/dev/null 2>&1; then
    echo
    break
  fi
  echo -n .
  sleep 1
done

# Apply & run workflow
if [ -f "$WORKFLOW_FILE" ]; then
  echo ">> Applying workflow: $WORKFLOW_FILE"
  kubectl apply -f "$WORKFLOW_FILE"
  if [ -z "$WORKFLOW_NAME" ]; then
    WORKFLOW_NAME="$(kubectl apply -f "$WORKFLOW_FILE" --dry-run=client -o jsonpath='{.metadata.name}' 2>/dev/null || true)"
  fi
else
  echo "!! WARNING: Workflow file not found at $WORKFLOW_FILE"
fi

if [ -n "${WORKFLOW_NAME:-}" ]; then
  echo ">> Running workflow: $WORKFLOW_NAME"
  EXEC_LINE="$(kubectl-testkube run testworkflow "$WORKFLOW_NAME" --namespace "$K8S_NS" -f || true)"
  echo "$EXEC_LINE"
  EXEC_ID="$(echo "$EXEC_LINE" | awk '{print $NF}' | tr -d '\r' || true)"
  if [ -n "$EXEC_ID" ] && [ "${FOLLOW_LOGS,,}" = "true" ]; then
    echo ">> Following logs for execution: $EXEC_ID"
    kubectl-testkube watch twe "$EXEC_ID" -n "$K8S_NS" || true
  fi
else
  echo ">> No WORKFLOW_NAME resolved; skipping run."
fi
