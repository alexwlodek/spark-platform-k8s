#!/usr/bin/env bash
set -euo pipefail

CLUSTER_NAME="${CLUSTER_NAME:-spark-dev}"
KIND_IMAGE="${KIND_IMAGE:-kindest/node:v1.29.4}"
KIND_CONFIG="${KIND_CONFIG:-scripts/kind-config.yaml}"
KIND_DELETE_EXISTING="${KIND_DELETE_EXISTING:-0}"

require() { command -v "$1" >/dev/null 2>&1 || { echo "Missing dependency: $1" >&2; exit 1; }; }
require kind
require kubectl

if kind get clusters | grep -qx "${CLUSTER_NAME}"; then
  if [[ "${KIND_DELETE_EXISTING}" == "1" ]]; then
    echo "kind cluster '${CLUSTER_NAME}' exists -> deleting (KIND_DELETE_EXISTING=1)"
    kind delete cluster --name "${CLUSTER_NAME}"
  else
    echo "kind cluster '${CLUSTER_NAME}' already exists -> reusing"
  fi
fi

if ! kind get clusters | grep -qx "${CLUSTER_NAME}"; then
  echo "Creating kind cluster '${CLUSTER_NAME}' (${KIND_IMAGE})..."
  kind create cluster \
    --name "${CLUSTER_NAME}" \
    --image "${KIND_IMAGE}" \
    --config "${KIND_CONFIG}"
fi

kubectl config use-context "kind-${CLUSTER_NAME}" >/dev/null

echo "Installing ingress-nginx (kind recommended manifest)..."
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml

echo "Waiting for ingress-nginx controller..."
kubectl -n ingress-nginx rollout status deployment/ingress-nginx-controller --timeout=180s

echo "✅ kind cluster ready: kind-${CLUSTER_NAME}"
