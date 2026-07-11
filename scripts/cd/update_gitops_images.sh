#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

ENVIRONMENT="${ENVIRONMENT:-dev}"
DOCKERHUB_USERNAME="${DOCKERHUB_USERNAME:-ynnhi2607}"
MAIN_TAG="${MAIN_TAG:-latest}"
GITOPS_REPO_DIR="${GITOPS_REPO_DIR:-../yas-gitops}"
GITOPS_REPO_URL="${GITOPS_REPO_URL:-https://github.com/ynnhi2607/yas-gitops.git}"
GITOPS_PULL="${GITOPS_PULL:-true}"
PUSH_GITOPS="${PUSH_GITOPS:-false}"
GITOPS_USERNAME="${GITOPS_USERNAME:-}"
GITOPS_TOKEN="${GITOPS_TOKEN:-}"
GITOPS_COMMIT_USER="${GITOPS_COMMIT_USER:-jenkins-bot}"
GITOPS_COMMIT_EMAIL="${GITOPS_COMMIT_EMAIL:-jenkins@local}"
BUILD_LABEL="${BUILD_NUMBER:-local}"
VERIFY_GITOPS_IMAGES="${VERIFY_GITOPS_IMAGES:-true}"

SERVICES=(
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
  storefront-ui
  backoffice-ui
  sampledata
)

case "$ENVIRONMENT" in
  dev|staging) ;;
  *)
    echo "ENVIRONMENT must be dev or staging" >&2
    exit 1
    ;;
esac

env_name() {
  local service="$1"
  echo "${service^^}_BRANCH" | tr '-' '_'
}

branch_for() {
  local service="$1"
  local var_name
  var_name="$(env_name "$service")"
  echo "${!var_name:-main}"
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

short_sha_for_branch() {
  local branch="$1"

  if [[ "$branch" =~ ^[0-9a-fA-F]{7,40}$ ]]; then
    echo "${branch:0:8}"
    return
  fi

  git -C "$ROOT_DIR" ls-remote origin "refs/heads/${branch}" | awk '{print substr($1, 1, 8)}'
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

gitops_auth_url() {
  if [[ -n "$GITOPS_TOKEN" && "$GITOPS_REPO_URL" == https://* ]]; then
    local url_without_scheme username
    url_without_scheme="${GITOPS_REPO_URL#https://}"
    username="${GITOPS_USERNAME:-x-access-token}"
    echo "https://${username}:${GITOPS_TOKEN}@${url_without_scheme}"
  else
    echo "$GITOPS_REPO_URL"
  fi
}

update_values_file() {
  local values_file="$1"
  local image_repository="$2"
  local image_tag="$3"

  sed -i "s#^\\([[:space:]]*repository:\\).*#\\1 ${image_repository}#" "$values_file"
  sed -i "s#^\\([[:space:]]*tag:\\).*#\\1 ${image_tag}#" "$values_file"
}

should_verify_image() {
  local service="$1"
  local branch="$2"
  local commit_var
  commit_var="$(env_name "$service")_COMMIT"

  if [[ -n "${!commit_var:-}" ]]; then
    return 0
  fi

  [[ "$branch" != "main" && "$branch" != "master" && -n "$branch" ]]
}

verify_image_exists() {
  local image="$1"

  if [[ "$VERIFY_GITOPS_IMAGES" != "true" ]]; then
    return
  fi

  if ! command -v docker >/dev/null 2>&1; then
    echo "docker CLI is required to verify image existence: ${image}" >&2
    exit 1
  fi

  if ! docker manifest inspect "$image" >/dev/null 2>&1; then
    cat >&2 <<EOF
Image does not exist yet: ${image}

Run the CI image build first, then rerun developer_build.
The GitOps repo is not updated because ArgoCD would deploy an image that Kubernetes cannot pull.
EOF
    exit 1
  fi
}

cd "$ROOT_DIR"

AUTHED_GITOPS_REPO_URL="$(gitops_auth_url)"

if [[ ! -d "$GITOPS_REPO_DIR/.git" ]]; then
  git clone "$AUTHED_GITOPS_REPO_URL" "$GITOPS_REPO_DIR"
fi

git -C "$GITOPS_REPO_DIR" remote set-url origin "$AUTHED_GITOPS_REPO_URL"

if [[ "$GITOPS_PULL" == "true" ]]; then
  git -C "$GITOPS_REPO_DIR" fetch origin main
  git -C "$GITOPS_REPO_DIR" checkout main
  git -C "$GITOPS_REPO_DIR" pull --ff-only origin main
fi

for service in "${SERVICES[@]}"; do
  values_file_relative="environments/${ENVIRONMENT}/services/${service}.yaml"
  values_file="${GITOPS_REPO_DIR}/${values_file_relative}"

  if [[ ! -f "$values_file" ]]; then
    echo "GitOps values file not found: ${values_file}" >&2
    exit 1
  fi

  branch="$(branch_for "$service")"
  tag="$(image_tag_for "$service" "$branch")"
  repo="$(image_repo_for_branch "$service" "$branch")"

  echo "GitOps ${ENVIRONMENT}/${service}: branch=${branch}, image=${repo}:${tag}"
  if should_verify_image "$service" "$branch"; then
    verify_image_exists "${repo}:${tag}"
  fi
  update_values_file "$values_file" "$repo" "$tag"
  git -C "$GITOPS_REPO_DIR" add "$values_file_relative"
done

if git -C "$GITOPS_REPO_DIR" diff --cached --quiet; then
  echo "No GitOps image tag changes for ${ENVIRONMENT}."
  exit 0
fi

git -C "$GITOPS_REPO_DIR" config user.name "$GITOPS_COMMIT_USER"
git -C "$GITOPS_REPO_DIR" config user.email "$GITOPS_COMMIT_EMAIL"
git -C "$GITOPS_REPO_DIR" commit -m "developer_build: update ${ENVIRONMENT} image tags [build #${BUILD_LABEL}]"

if [[ "$PUSH_GITOPS" == "true" ]]; then
  git -C "$GITOPS_REPO_DIR" push origin main
else
  echo "GitOps commit created locally. Set PUSH_GITOPS=true to push origin main."
fi
