#!/usr/bin/env bash
set -euo pipefail

CLUSTER_NAME="${CLUSTER_NAME:-spark-dev}"
ARGO_NAMESPACE="${ARGO_NAMESPACE:-argocd}"

require() { command -v "$1" >/dev/null 2>&1 || { echo "Missing dependency: $1" >&2; exit 1; }; }
require kubectl

kubectl config use-context "kind-${CLUSTER_NAME}" >/dev/null

echo "Creating namespace '${ARGO_NAMESPACE}' (if missing)..."
kubectl get ns "${ARGO_NAMESPACE}" >/dev/null 2>&1 || kubectl create ns "${ARGO_NAMESPACE}"

# Install Argo CD (official install.yaml)
# Note: in MVP we install ArgoCD manually once (bootstrap). Later Argo can self-manage via Helm chart if we want.
echo "Installing Argo CD (install.yaml)..."
kubectl apply -n "${ARGO_NAMESPACE}" -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

echo "Waiting for Argo CD API server..."
kubectl -n "${ARGO_NAMESPACE}" rollout status deployment/argocd-server --timeout=240s

echo "Applying AppProject + root application..."
kubectl apply -n "${ARGO_NAMESPACE}" -f clusters/dev/projects/platform.yaml
kubectl apply -n "${ARGO_NAMESPACE}" -f clusters/dev/root.yaml

echo "✅ Argo CD bootstrapped and root app applied."
echo "Check:"
echo "  kubectl -n argocd get applications"
