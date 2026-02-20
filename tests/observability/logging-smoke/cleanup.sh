#!/usr/bin/env bash
set -euo pipefail

APP_NAMESPACE="${APP_NAMESPACE:-apps}"
POD_NAME="${POD_NAME:-log-smoke-drill}"

require() { command -v "$1" >/dev/null 2>&1 || { echo "Missing dependency: $1" >&2; exit 1; }; }
require kubectl

echo "Deleting drill pod..."
kubectl -n "${APP_NAMESPACE}" delete pod "${POD_NAME}" --ignore-not-found

echo "Done."
