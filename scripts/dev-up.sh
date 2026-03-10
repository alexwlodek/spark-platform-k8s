#!/usr/bin/env bash
set -euo pipefail

# One command DEV setup:
# - create kind cluster
# - install ingress-nginx
# - install Argo CD
# - apply AppProject + root app (app-of-apps)

ES_NAMESPACE="${ES_NAMESPACE:-external-secrets}"
CREDENTIALS_SECRET_NAME="${CREDENTIALS_SECRET_NAME:-awssm-credentials}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

ensure_aws_sm_auth() {
  echo "Checking AWS Secrets Manager credentials for External Secrets Operator..."

  if kubectl -n "${ES_NAMESPACE}" get secret "${CREDENTIALS_SECRET_NAME}" >/dev/null 2>&1; then
    echo "Found ${ES_NAMESPACE}/${CREDENTIALS_SECRET_NAME}."
    return 0
  fi

  if [[ -n "${AWS_ACCESS_KEY_ID:-}" && -n "${AWS_SECRET_ACCESS_KEY:-}" ]]; then
    echo "Missing ${ES_NAMESPACE}/${CREDENTIALS_SECRET_NAME}; creating it from AWS_* environment variables..."
    "${SCRIPT_DIR}/dev-aws-sm-auth.sh"
    return 0
  fi

  cat >&2 <<EOF
Missing ${ES_NAMESPACE}/${CREDENTIALS_SECRET_NAME}.

Argo CD bootstrap depends on External Secrets access to AWS Secrets Manager, so DEV setup stops here.

Provide credentials and rerun:
  export AWS_ACCESS_KEY_ID=...
  export AWS_SECRET_ACCESS_KEY=...
  # optional for temporary STS credentials
  export AWS_SESSION_TOKEN=...
  ${SCRIPT_DIR}/dev-aws-sm-auth.sh
  ${SCRIPT_DIR}/dev-up.sh
EOF
  exit 1
}

"${SCRIPT_DIR}/dev-kind-up.sh"
ensure_aws_sm_auth
"${SCRIPT_DIR}/dev-bootstrap-argocd.sh"

echo
echo "✅ DEV ready."
echo "Next:"
echo "  - UI URLs + credentials: ${SCRIPT_DIR}/dev-ui-links.sh"
echo "  - Argo CD port-forward fallback: ${SCRIPT_DIR}/dev-argocd-ui.sh"
echo "  - Apps: kubectl -n argocd get applications"
