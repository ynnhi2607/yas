#!/usr/bin/env bash
set -euo pipefail

ENVIRONMENT="${ENVIRONMENT:-dev}"
SERVICE="${SERVICE:?SERVICE is required}"
IMAGE_TAG="${IMAGE_TAG:?IMAGE_TAG is required}"
DOCKERHUB_USERNAME="${DOCKERHUB_USERNAME:-ynnhi2607}"
GITOPS_REPO_DIR="${GITOPS_REPO_DIR:-../yas-gitops}"
GITOPS_REPO_URL="${GITOPS_REPO_URL:-https://github.com/ynnhi2607/yas-gitops.git}"
PUSH_GITOPS="${PUSH_GITOPS:-false}"
GITOPS_USERNAME="${GITOPS_USERNAME:-}"
GITOPS_TOKEN="${GITOPS_TOKEN:-}"
GITOPS_COMMIT_USER="${GITOPS_COMMIT_USER:-jenkins-bot}"
GITOPS_COMMIT_EMAIL="${GITOPS_COMMIT_EMAIL:-jenkins@local}"

case "$ENVIRONMENT" in
  dev|staging) ;;
  *)
    echo "ENVIRONMENT must be dev or staging" >&2
    exit 1
    ;;
esac

case "$SERVICE" in
  product|cart|order|customer|inventory|location|tax|payment|media|search|storefront-bff|backoffice-bff|storefront-ui|backoffice-ui|sampledata) ;;
  *)
    echo "Unsupported service '${SERVICE}' for GitOps update" >&2
    exit 1
    ;;
esac

image_repo_for() {
  case "$1" in
    storefront-ui) echo "${DOCKERHUB_USERNAME}/yas-storefront" ;;
    backoffice-ui) echo "${DOCKERHUB_USERNAME}/yas-backoffice" ;;
    *) echo "${DOCKERHUB_USERNAME}/yas-${1}" ;;
  esac
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

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

AUTHED_GITOPS_REPO_URL="$(gitops_auth_url)"

if [[ ! -d "$GITOPS_REPO_DIR/.git" ]]; then
  git clone "$AUTHED_GITOPS_REPO_URL" "$GITOPS_REPO_DIR"
fi

if [[ -n "$GITOPS_TOKEN" && "$GITOPS_REPO_URL" == https://* ]]; then
  git -C "$GITOPS_REPO_DIR" remote set-url origin "$AUTHED_GITOPS_REPO_URL"
fi

git -C "$GITOPS_REPO_DIR" fetch origin main
git -C "$GITOPS_REPO_DIR" checkout main
git -C "$GITOPS_REPO_DIR" pull --ff-only origin main

VALUES_FILE_RELATIVE="environments/${ENVIRONMENT}/services/${SERVICE}.yaml"
VALUES_FILE="${GITOPS_REPO_DIR}/${VALUES_FILE_RELATIVE}"
if [[ ! -f "$VALUES_FILE" ]]; then
  echo "GitOps values file not found: ${VALUES_FILE}" >&2
  exit 1
fi

IMAGE_REPOSITORY="${IMAGE_REPOSITORY:-$(image_repo_for "$SERVICE")}"

sed -i "s#^\\([[:space:]]*repository:\\).*#\\1 ${IMAGE_REPOSITORY}#" "$VALUES_FILE"
sed -i "s#^\\([[:space:]]*tag:\\).*#\\1 ${IMAGE_TAG}#" "$VALUES_FILE"

git -C "$GITOPS_REPO_DIR" add "$VALUES_FILE_RELATIVE"

if git -C "$GITOPS_REPO_DIR" diff --cached --quiet; then
  echo "No GitOps change for ${SERVICE} in ${ENVIRONMENT}."
  exit 0
fi

git -C "$GITOPS_REPO_DIR" config user.name "$GITOPS_COMMIT_USER"
git -C "$GITOPS_REPO_DIR" config user.email "$GITOPS_COMMIT_EMAIL"
git -C "$GITOPS_REPO_DIR" commit -m "Deploy ${SERVICE}:${IMAGE_TAG} to ${ENVIRONMENT}"

if [[ "$PUSH_GITOPS" == "true" ]]; then
  git -C "$GITOPS_REPO_DIR" push origin main
else
  echo "GitOps commit created locally. Set PUSH_GITOPS=true to push origin main."
fi

echo "Updated ${VALUES_FILE}: ${IMAGE_REPOSITORY}:${IMAGE_TAG}"
