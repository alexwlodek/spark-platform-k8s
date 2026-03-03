#!/usr/bin/env bash
set -euo pipefail

CLUSTER_NAME="${CLUSTER_NAME:-data-platform-dev}"
KIND_IMAGE="${KIND_IMAGE:-kindest/node:v1.34.2}"
KIND_CONFIG="${KIND_CONFIG:-scripts/kind-config.yaml}"
KIND_DELETE_EXISTING="${KIND_DELETE_EXISTING:-0}"
KIND_PRELOAD_IMAGES="${KIND_PRELOAD_IMAGES:-ghcr.io/kubeflow/spark-operator/controller:2.4.0 ghcr.io/alexwlodek/spark-demo-job:latest ghcr.io/alexwlodek/order-generator:latest}"
KIND_PRELOAD_ENABLED="${KIND_PRELOAD_ENABLED:-0}"
KIND_PRELOAD_PULL_MISSING="${KIND_PRELOAD_PULL_MISSING:-1}"
KIND_PRELOAD_RETRIES="${KIND_PRELOAD_RETRIES:-3}"
KIND_FIX_NODE_DNS="${KIND_FIX_NODE_DNS:-0}"
KIND_FIX_NODE_DNS_FORCE="${KIND_FIX_NODE_DNS_FORCE:-0}"
KIND_NODE_DNS_SERVERS="${KIND_NODE_DNS_SERVERS:-1.1.1.1 8.8.8.8}"
KIND_WAIT_NODES_TIMEOUT="${KIND_WAIT_NODES_TIMEOUT:-300s}"
INGRESS_WAIT_TIMEOUT="${INGRESS_WAIT_TIMEOUT:-240s}"

require() { command -v "$1" >/dev/null 2>&1 || { echo "Missing dependency: $1" >&2; exit 1; }; }
require kind
require kubectl
require docker

if ! docker info >/dev/null 2>&1; then
  echo "Cannot access Docker daemon. Ensure Docker is running and your user can access /var/run/docker.sock." >&2
  exit 1
fi

preload_images() {
  if [[ "${KIND_PRELOAD_ENABLED}" != "1" ]]; then
    echo "Skipping image preload cache (KIND_PRELOAD_ENABLED=${KIND_PRELOAD_ENABLED})."
    return
  fi

  if [[ -z "${KIND_PRELOAD_IMAGES// }" ]]; then
    return
  fi

  if ! command -v docker >/dev/null 2>&1; then
    echo "Skipping image preload cache (docker CLI not found)."
    return
  fi

  local node
  local nodes=()
  while IFS= read -r node; do
    [[ -z "${node}" ]] && continue
    nodes+=("${node}")
  done < <(kind get nodes --name "${CLUSTER_NAME}")

  if [[ "${#nodes[@]}" -eq 0 ]]; then
    echo "Skipping preload: no kind nodes found in cluster '${CLUSTER_NAME}'."
    return
  fi

  local image
  for image in ${KIND_PRELOAD_IMAGES}; do
    if ! docker image inspect "${image}" >/dev/null 2>&1; then
      if [[ "${KIND_PRELOAD_PULL_MISSING}" == "1" ]]; then
        echo "Pulling missing image to local cache: ${image}"
        if ! docker pull "${image}" >/dev/null; then
          echo "WARNING: failed to pull ${image}; skipping preload."
          continue
        fi
      else
        echo "Skipping missing local image: ${image}"
        continue
      fi
    fi

    local attempt
    for node in "${nodes[@]}"; do
      attempt=1
      while true; do
        if kind load docker-image --name "${CLUSTER_NAME}" --nodes "${node}" "${image}" >/dev/null; then
          break
        fi

        if (( attempt >= KIND_PRELOAD_RETRIES )); then
          echo "ERROR: failed to preload ${image} into node ${node} after ${KIND_PRELOAD_RETRIES} attempts." >&2
          return 1
        fi

        attempt=$((attempt + 1))
        echo "Retrying preload (${attempt}/${KIND_PRELOAD_RETRIES}): ${image} -> ${node}"
        sleep 1
      done
    done
  done
}

fix_kind_node_dns() {
  if [[ "${KIND_FIX_NODE_DNS}" != "1" ]]; then
    return
  fi

  # kind node DNS rewrite caused worker CNI bootstrap issues on K8s 1.34+ in this setup.
  # Keep it opt-in with explicit force flag for troubleshooting only.
  if [[ "${KIND_IMAGE}" =~ kindest/node:v1\.(34|35|36|37|38|39)\..* ]] && [[ "${KIND_FIX_NODE_DNS_FORCE}" != "1" ]]; then
    echo "Skipping kind node DNS rewrite on ${KIND_IMAGE}. Use KIND_FIX_NODE_DNS_FORCE=1 to override."
    return
  fi

  if ! command -v docker >/dev/null 2>&1; then
    echo "Skipping kind node DNS fix (docker CLI not found)."
    return
  fi

  local node
  while IFS= read -r node; do
    [[ -z "${node}" ]] && continue
    {
      local dns
      for dns in ${KIND_NODE_DNS_SERVERS}; do
        echo "nameserver ${dns}"
      done
      echo "options ndots:0"
    } | docker exec -i "${node}" sh -c "cat > /etc/resolv.conf"
  done < <(kind get nodes --name "${CLUSTER_NAME}")
}

wait_for_nodes_ready() {
  echo "Waiting for all nodes to become Ready..."
  if ! kubectl wait --for=condition=Ready node --all --timeout="${KIND_WAIT_NODES_TIMEOUT}" >/dev/null; then
    echo "ERROR: nodes did not become Ready in ${KIND_WAIT_NODES_TIMEOUT}" >&2
    kubectl get nodes -o wide >&2 || true
    return 1
  fi
}

wait_for_ingress_admission() {
  echo "Waiting for ingress-nginx admission secret..."
  local wait_seconds loops i
  wait_seconds="${INGRESS_WAIT_TIMEOUT%s}"
  if ! [[ "${wait_seconds}" =~ ^[0-9]+$ ]]; then
    wait_seconds=240
  fi
  loops=$(( (wait_seconds + 1) / 2 ))

  for i in $(seq 1 "${loops}"); do
    if kubectl -n ingress-nginx get secret ingress-nginx-admission >/dev/null 2>&1; then
      return 0
    fi
    if (( i % 10 == 0 )); then
      kubectl -n ingress-nginx get pods,jobs >&2 || true
    fi
    sleep 2
  done

  echo "ERROR: secret ingress-nginx-admission was not created" >&2
  kubectl -n ingress-nginx get pods,jobs >&2 || true
  kubectl -n ingress-nginx get events --sort-by=.lastTimestamp | tail -n 80 >&2 || true
  return 1
}

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

wait_for_nodes_ready
fix_kind_node_dns
preload_images

echo "Installing ingress-nginx (kind recommended manifest)..."
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml

wait_for_ingress_admission

echo "Waiting for ingress-nginx controller..."
kubectl -n ingress-nginx rollout status deployment/ingress-nginx-controller --timeout=180s

echo "✅ kind cluster ready: kind-${CLUSTER_NAME}"
