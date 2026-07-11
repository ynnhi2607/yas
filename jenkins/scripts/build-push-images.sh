#!/usr/bin/env bash
set -euo pipefail

push_image_with_retry() {
  local image="$1"
  local attempt=1
  local max_attempts=5

  while [[ "$attempt" -le "$max_attempts" ]]; do
    echo "Pushing ${image} (attempt ${attempt}/${max_attempts})"
    if docker push "$image"; then
      return 0
    fi

    if [[ "$attempt" -eq "$max_attempts" ]]; then
      echo "Failed to push ${image} after ${max_attempts} attempts" >&2
      return 1
    fi

    sleep_seconds=$((attempt * 20))
    echo "Push failed for ${image}. Retrying in ${sleep_seconds}s..."
    sleep "$sleep_seconds"
    attempt=$((attempt + 1))
  done
}

image_name_for() {
  case "$1" in
    backoffice) printf 'yas-backoffice' ;;
    storefront) printf 'yas-storefront' ;;
    *) printf 'yas-%s' "$1" ;;
  esac
}

set +x
printf '%s' "$DOCKERHUB_PASSWORD" | docker login -u "$DOCKERHUB_USERNAME" --password-stdin
set -x

IFS=',' read -r -a docker_services <<< "${AFFECTED_DOCKER_MODULES:-}"

for service in "${docker_services[@]}"; do
  [[ -n "$service" ]] || continue

  if [[ ! -f "${service}/Dockerfile" ]]; then
    echo "No Dockerfile for ${service}. Skipping."
    continue
  fi

  image="${DOCKERHUB_NAMESPACE}/$(image_name_for "$service"):${IMAGE_TAG}"
  echo "Building ${image}"

  if [[ "$service" == "media" ]]; then
    rm -rf media/images
    cp -a sampledata/images media/images
  fi

  docker build --pull -t "$image" "$service"
  push_image_with_retry "$image"

  if [[ "${BRANCH_NAME:-}" == "main" ]]; then
    main_image="${image%:*}:main"
    latest_image="${image%:*}:latest"
    docker tag "$image" "$main_image"
    docker tag "$image" "$latest_image"
    push_image_with_retry "$main_image"
    push_image_with_retry "$latest_image"
  fi
done

docker logout || true
