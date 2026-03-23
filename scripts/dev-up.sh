#!/usr/bin/env bash
set -euo pipefail

# One command DEV setup:
# - create kind cluster
# - install ingress-nginx
# - install Argo CD
# - apply AppProject + root app (app-of-apps)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

"${SCRIPT_DIR}/dev-kind-up.sh"
"${SCRIPT_DIR}/dev-secrets-apply.sh"
"${SCRIPT_DIR}/dev-bootstrap-argocd.sh"

echo
echo "✅ DEV ready."
echo "Next:"
echo "  - UI URLs + credentials: ${SCRIPT_DIR}/dev-ui-links.sh"
echo "  - Argo CD port-forward fallback: ${SCRIPT_DIR}/dev-argocd-ui.sh"
echo "  - Apps: kubectl -n argocd get applications"
