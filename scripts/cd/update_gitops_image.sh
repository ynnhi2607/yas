#!/usr/bin/env bash
set -euo pipefail

ENVIRONMENT="${ENVIRONMENT:-dev}"
SERVICE="${SERVICE:?SERVICE is required}"
IMAGE_TAG="${IMAGE_TAG:?IMAGE_TAG is required}"
DOCKERHUB_USERNAME="${DOCKERHUB_USERNAME:-ynnhi2607}"
GITOPS_REPO_DIR="${GITOPS_REPO_DIR:-../yas-gitops}"
GITOPS_REPO_URL="${GITOPS_REPO_URL:-https://github.com/ynnhi2607/yas-gitops.git}"
PUSH_GITOPS="${PUSH_GITOPS:-false}"

case "$ENVIRONMENT" in
  dev|staging) ;;
  *)
    echo "ENVIRONMENT must be dev or staging" >&2
    exit 1
    ;;
esac

case "$SERVICE" in
  product|cart|order|customer|inventory|tax|media|search|storefront-bff|backoffice-bff|storefront-ui|backoffice-ui|sampledata) ;;
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

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

if [[ ! -d "$GITOPS_REPO_DIR/.git" ]]; then
  git clone "$GITOPS_REPO_URL" "$GITOPS_REPO_DIR"
fi

VALUES_FILE="${GITOPS_REPO_DIR}/environments/${ENVIRONMENT}/services/${SERVICE}.yaml"
if [[ ! -f "$VALUES_FILE" ]]; then
  echo "GitOps values file not found: ${VALUES_FILE}" >&2
  exit 1
fi

IMAGE_REPOSITORY="${IMAGE_REPOSITORY:-$(image_repo_for "$SERVICE")}"

python3 - "$VALUES_FILE" "$SERVICE" "$IMAGE_REPOSITORY" "$IMAGE_TAG" <<'PY'
import sys
from pathlib import Path
import yaml

path = Path(sys.argv[1])
service = sys.argv[2]
repository = sys.argv[3]
tag = sys.argv[4]

data = yaml.safe_load(path.read_text()) or {}
root_key = "ui" if service in {"storefront-ui", "backoffice-ui"} else "backend"
data.setdefault(root_key, {}).setdefault("image", {})
data[root_key]["image"]["repository"] = repository
data[root_key]["image"]["tag"] = tag

path.write_text(yaml.safe_dump(data, sort_keys=False))
PY

git -C "$GITOPS_REPO_DIR" add "$VALUES_FILE"

if git -C "$GITOPS_REPO_DIR" diff --cached --quiet; then
  echo "No GitOps change for ${SERVICE} in ${ENVIRONMENT}."
  exit 0
fi

git -C "$GITOPS_REPO_DIR" commit -m "Deploy ${SERVICE}:${IMAGE_TAG} to ${ENVIRONMENT}"

if [[ "$PUSH_GITOPS" == "true" ]]; then
  git -C "$GITOPS_REPO_DIR" push origin main
else
  echo "GitOps commit created locally. Set PUSH_GITOPS=true to push origin main."
fi

echo "Updated ${VALUES_FILE}: ${IMAGE_REPOSITORY}:${IMAGE_TAG}"
