#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFESTS_DIR="${SCRIPT_DIR}/manifests"

require() { command -v "$1" >/dev/null 2>&1 || { echo "Missing dependency: $1" >&2; exit 1; }; }
require kubectl

echo "Deleting drill resources..."
kubectl delete -f "${MANIFESTS_DIR}/sparkapplication-bad-image.yaml" --ignore-not-found
kubectl delete -f "${MANIFESTS_DIR}/prometheusrule-bad-image.yaml" --ignore-not-found

echo "Done."
