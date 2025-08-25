#!/usr/bin/env bash
set -euo pipefail

if [ $# -lt 1 ]; then
  echo "Usage: $0 <workflow.yaml> [--name <workflowName>] [--logs] [--no-logs] [--destroy]"
  exit 1
fi

WF_PATH="$1"; shift || true
WF_NAME=""
FOLLOW_LOGS="true"
DESTROY="false"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --name) WF_NAME="$2"; shift 2;;
    --logs) FOLLOW_LOGS="true"; shift;;
    --no-logs) FOLLOW_LOGS="false"; shift;;
    --destroy) DESTROY="true"; shift;;
    *) echo "Unknown arg: $1"; exit 1;;
  esac
done

IMG="testkube-local:latest"
if ! docker image inspect "$IMG" >/dev/null 2>&1; then
  echo ">> Building image $IMG (first run only)"
  docker build -t "$IMG" .
fi

if [ "$DESTROY" = "true" ]; then
  echo ">> Destroying cluster tk-local (if exists)..."
  docker run --rm \
    -v /var/run/docker.sock:/var/run/docker.sock \
    --add-host host.docker.internal:host-gateway \
    "$IMG" bash -lc "k3d cluster delete tk-local || true"
  exit 0
fi

WF_ABS="$(cd "$(dirname "$WF_PATH")" && pwd)/$(basename "$WF_PATH")"
[ -f "$WF_ABS" ] || { echo "ERROR: Workflow file not found: $WF_ABS"; exit 1; }

echo ">> Running workflow via container..."
docker run --rm -it \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v "$(dirname "$WF_ABS")":/work:rw \
  --add-host host.docker.internal:host-gateway \
  -e WORKFLOW_FILE="/work/$(basename "$WF_ABS")" \
  -e WORKFLOW_NAME="${WF_NAME}" \
  -e FOLLOW_LOGS="${FOLLOW_LOGS}" \
  "$IMG"
