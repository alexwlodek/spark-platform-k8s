#!/usr/bin/env bash
set -euo pipefail

ARGO_NAMESPACE="${ARGO_NAMESPACE:-argocd}"

echo "Argo CD admin password (initial):"
kubectl -n "${ARGO_NAMESPACE}" get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' 2>/dev/null | base64 -d || true
echo
echo
echo "Port-forward: http://localhost:8081"
echo "Login: admin"
echo "Tip: Argo CD is running with server.insecure=true on DEV."

kubectl -n "${ARGO_NAMESPACE}" port-forward svc/argocd-server 8081:80
