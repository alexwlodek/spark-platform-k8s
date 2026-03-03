#!/usr/bin/env bash
set -euo pipefail

ES_NAMESPACE="${ES_NAMESPACE:-external-secrets}"
CREDENTIALS_SECRET_NAME="${CREDENTIALS_SECRET_NAME:-awssm-credentials}"

require() { command -v "$1" >/dev/null 2>&1 || { echo "Missing dependency: $1" >&2; exit 1; }; }
require kubectl

AWS_ACCESS_KEY_ID_VALUE="${AWS_ACCESS_KEY_ID:-}"
AWS_SECRET_ACCESS_KEY_VALUE="${AWS_SECRET_ACCESS_KEY:-}"
AWS_SESSION_TOKEN_VALUE="${AWS_SESSION_TOKEN:-}"

if [[ -z "${AWS_ACCESS_KEY_ID_VALUE}" || -z "${AWS_SECRET_ACCESS_KEY_VALUE}" ]]; then
  cat >&2 <<'EOF'
Missing AWS credentials.
Set environment variables and run again:
  export AWS_ACCESS_KEY_ID=...
  export AWS_SECRET_ACCESS_KEY=...
Optional:
  export AWS_SESSION_TOKEN=...
EOF
  exit 1
fi

kubectl get ns "${ES_NAMESPACE}" >/dev/null 2>&1 || kubectl create ns "${ES_NAMESPACE}" >/dev/null

kubectl -n "${ES_NAMESPACE}" create secret generic "${CREDENTIALS_SECRET_NAME}" \
  --from-literal=access-key-id="${AWS_ACCESS_KEY_ID_VALUE}" \
  --from-literal=secret-access-key="${AWS_SECRET_ACCESS_KEY_VALUE}" \
  --from-literal=session-token="${AWS_SESSION_TOKEN_VALUE}" \
  --dry-run=client -o yaml | kubectl apply -f - >/dev/null

echo "Updated ${ES_NAMESPACE}/${CREDENTIALS_SECRET_NAME} for External Secrets Operator."
