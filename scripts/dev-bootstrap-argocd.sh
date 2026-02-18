#!/usr/bin/env bash
set -euo pipefail

CLUSTER_NAME="${CLUSTER_NAME:-spark-dev}"
ARGO_NAMESPACE="${ARGO_NAMESPACE:-argocd}"
ARGOCD_INSTALL_URL="${ARGOCD_INSTALL_URL:-https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml}"

require() { command -v "$1" >/dev/null 2>&1 || { echo "Missing dependency: $1" >&2; exit 1; }; }
require kubectl

kubectl config use-context "kind-${CLUSTER_NAME}" >/dev/null

echo "Creating namespace '${ARGO_NAMESPACE}' (if missing)..."
kubectl get ns "${ARGO_NAMESPACE}" >/dev/null 2>&1 || kubectl create ns "${ARGO_NAMESPACE}"

echo "Downloading Argo CD install manifest..."
TMP_DIR="$(mktemp -d)"
INSTALL="${TMP_DIR}/install.yaml"
curl -fsSL "${ARGOCD_INSTALL_URL}" -o "${INSTALL}"

echo "Installing Argo CD CRDs (server-side apply)..."
# Apply only CRDs first, server-side (avoids huge last-applied annotation limit)
kubectl apply --server-side -f <(awk 'BEGIN{RS="---\n"} /kind: CustomResourceDefinition/{print "---\n"$0}' "${INSTALL}")

echo "Installing the rest of Argo CD (normal apply)..."
kubectl apply -n "${ARGO_NAMESPACE}" -f <(awk 'BEGIN{RS="---\n"} $0 !~ /kind: CustomResourceDefinition/{print "---\n"$0}' "${INSTALL}")

echo "Waiting for Argo CD API server..."
kubectl -n "${ARGO_NAMESPACE}" rollout status deployment/argocd-server --timeout=240s

echo "Applying AppProject + root application..."
kubectl apply -n "${ARGO_NAMESPACE}" -f clusters/dev/projects/platform.yaml
kubectl apply -n "${ARGO_NAMESPACE}" -f clusters/dev/root.yaml

echo "✅ Argo CD bootstrapped and root app applied."
echo "Check:"
echo "  kubectl -n argocd get applications"
