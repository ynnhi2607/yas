#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CHARTS_DIR="${ROOT_DIR}/k8s/charts"

NAMESPACE="${NAMESPACE:-yas}"
DOCKERHUB_USERNAME="${DOCKERHUB_USERNAME:-ynnhi2607}"
MAIN_TAG="${MAIN_TAG:-latest}"
DEPLOY_CONFIG="${DEPLOY_CONFIG:-true}"
DEPLOY_SAMPLEDATA="${DEPLOY_SAMPLEDATA:-false}"
ENABLE_NODEPORT="${ENABLE_NODEPORT:-true}"

BACKEND_SERVICES=(
  product
  cart
  order
  customer
  inventory
  location
  tax
  payment
  media
  search
  storefront-bff
  backoffice-bff
)

UI_SERVICES=(
  storefront-ui
  backoffice-ui
)

optional_services=()
if [[ "${DEPLOY_SAMPLEDATA}" == "true" ]]; then
  optional_services+=(sampledata)
fi

ingress_controller_ip() {
  kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.spec.clusterIP}' 2>/dev/null || true
}

env_name() {
  local service="$1"
  echo "${service^^}_BRANCH" | tr '-' '_'
}

source_dir_for() {
  case "$1" in
    storefront-ui) echo "storefront" ;;
    backoffice-ui) echo "backoffice" ;;
    *) echo "$1" ;;
  esac
}

image_repo_for() {
  local service="$1"
  case "$service" in
    storefront-ui) echo "${DOCKERHUB_USERNAME}/yas-storefront" ;;
    backoffice-ui) echo "${DOCKERHUB_USERNAME}/yas-backoffice" ;;
    *) echo "${DOCKERHUB_USERNAME}/yas-${service}" ;;
  esac
}

default_image_repo_for() {
  local service="$1"
  case "$service" in
    storefront-ui) echo "${DOCKERHUB_USERNAME}/yas-storefront" ;;
    backoffice-ui) echo "${DOCKERHUB_USERNAME}/yas-backoffice" ;;
    media) echo "${DOCKERHUB_USERNAME}/yas-media" ;;
    sampledata) echo "${DOCKERHUB_USERNAME}/yas-sampledata" ;;
    *) echo "ghcr.io/nashtech-garage/yas-${service}" ;;
  esac
}

branch_for() {
  local service="$1"
  local var_name
  var_name="$(env_name "$service")"
  echo "${!var_name:-main}"
}

short_sha_for_branch() {
  local branch="$1"

  if [[ "$branch" =~ ^[0-9a-fA-F]{7,40}$ ]]; then
    echo "${branch:0:8}"
    return
  fi

  git -C "${ROOT_DIR}" ls-remote origin "refs/heads/${branch}" | awk '{print substr($1, 1, 8)}'
}

image_tag_for() {
  local service="$1"
  local branch="$2"
  local commit_var
  commit_var="$(env_name "$service")_COMMIT"

  if [[ -n "${!commit_var:-}" ]]; then
    echo "${!commit_var:0:8}"
    return
  fi

  if [[ "$branch" == "main" || "$branch" == "master" || -z "$branch" ]]; then
    echo "$MAIN_TAG"
    return
  fi

  local short_sha
  short_sha="$(short_sha_for_branch "$branch")"
  if [[ -z "$short_sha" ]]; then
    echo "Cannot resolve commit id for branch '${branch}' of service '${service}'." >&2
    exit 1
  fi

  echo "$short_sha"
}

image_repo_for_branch() {
  local service="$1"
  local branch="$2"
  local commit_var
  commit_var="$(env_name "$service")_COMMIT"

  if [[ -n "${!commit_var:-}" ]]; then
    image_repo_for "$service"
    return
  fi

  if [[ "$branch" == "main" || "$branch" == "master" || -z "$branch" ]]; then
    default_image_repo_for "$service"
  else
    image_repo_for "$service"
  fi
}

node_port_for() {
  case "$1" in
    storefront-ui) echo 30280 ;;
    backoffice-ui) echo 30281 ;;
    storefront-bff) echo 30282 ;;
    backoffice-bff) echo 30283 ;;
    swagger-ui) echo 30284 ;;
    *) return 1 ;;
  esac
}

build_chart_dependencies() {
  local chart="$1"
  if [[ -f "${chart}/Chart.yaml" ]]; then
    helm dependency build "$chart" >/dev/null
  fi
}

deploy_backend_service() {
  local service="$1"
  local branch tag repo chart ingress_ip
  branch="$(branch_for "$service")"
  tag="$(image_tag_for "$service" "$branch")"
  repo="$(image_repo_for_branch "$service" "$branch")"
  chart="${CHARTS_DIR}/${service}"
  ingress_ip="$(ingress_controller_ip)"

  build_chart_dependencies "$chart"

  echo "Deploy ${service}: branch=${branch}, image=${repo}:${tag}"
  local helm_args=(
    upgrade --install "$service" "$chart"
    --namespace "$NAMESPACE" \
    --create-namespace \
    --set "backend.image.repository=${repo}" \
    --set "backend.image.tag=${tag}"
  )

  if [[ -n "$ingress_ip" ]]; then
    helm_args+=(
      --set "backend.hostAliases[0].ip=${ingress_ip}"
      --set "backend.hostAliases[0].hostnames[0]=identity.yas.local.com"
    )
  fi

  if [[ "$ENABLE_NODEPORT" == "true" ]] && node_port_for "$service" >/dev/null; then
    helm_args+=(
      --set "backend.service.type=NodePort"
      --set "backend.service.nodePort=$(node_port_for "$service")"
    )
  fi

  helm "${helm_args[@]}"
}

deploy_ui_service() {
  local service="$1"
  local branch tag repo chart
  branch="$(branch_for "$service")"
  tag="$(image_tag_for "$service" "$branch")"
  repo="$(image_repo_for_branch "$service" "$branch")"
  chart="${CHARTS_DIR}/${service}"

  build_chart_dependencies "$chart"

  echo "Deploy ${service}: branch=${branch}, image=${repo}:${tag}"
  local helm_args=(
    upgrade --install "$service" "$chart"
    --namespace "$NAMESPACE" \
    --create-namespace \
    --set "ui.image.repository=${repo}" \
    --set "ui.image.tag=${tag}"
  )

  if [[ "$ENABLE_NODEPORT" == "true" ]] && node_port_for "$service" >/dev/null; then
    helm_args+=(
      --set "ui.service.type=NodePort"
      --set "ui.service.nodePort=$(node_port_for "$service")"
    )
  fi

  helm "${helm_args[@]}"
}

print_urls() {
  echo
  echo "Deployment finished."
  echo
  echo "Ingress URLs:"
  echo "  http://storefront.yas.local.com"
  echo "  http://backoffice.yas.local.com"
  echo "  http://api.yas.local.com/swagger-ui/"
  if [[ "$ENABLE_NODEPORT" == "true" ]]; then
    echo
    echo "NodePort URLs:"
    echo "  storefront-ui:  http://<vm-ip>:30280"
    echo "  backoffice-ui:  http://<vm-ip>:30281"
    echo "  storefront-bff: http://<vm-ip>:30282"
    echo "  backoffice-bff: http://<vm-ip>:30283"
    echo "  swagger-ui:     http://<vm-ip>:30284/swagger-ui"
  fi
  echo
  echo "If the VM IP changed, update your hosts file or run:"
  echo "  HOST_IP=<vm-ip> ./scripts/cd/print_demo_urls.sh"
}

cd "$ROOT_DIR"

if [[ "${DEPLOY_CONFIG}" == "true" ]]; then
  build_chart_dependencies "${CHARTS_DIR}/yas-configuration"
  helm upgrade --install yas-configuration "${CHARTS_DIR}/yas-configuration" \
    --namespace "$NAMESPACE" \
    --create-namespace
fi

for service in "${BACKEND_SERVICES[@]}" "${optional_services[@]}"; do
  deploy_backend_service "$service"
done

for service in "${UI_SERVICES[@]}"; do
  deploy_ui_service "$service"
done

swagger_args=(
  upgrade --install swagger-ui "${CHARTS_DIR}/swagger-ui"
  --namespace "$NAMESPACE"
  --create-namespace
)

if [[ "$ENABLE_NODEPORT" == "true" ]]; then
  swagger_args+=(
    --set "service.type=NodePort"
    --set "service.nodePort=$(node_port_for swagger-ui)"
  )
fi

helm "${swagger_args[@]}"

kubectl get pods -n "$NAMESPACE"
print_urls
