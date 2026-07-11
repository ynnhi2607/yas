#!/usr/bin/env bash
set -euo pipefail

csv_join() {
  local IFS=,
  echo "$*"
}

contains_service_change() {
  local service="$1"
  grep -Eq "^${service}(/|$)" .jenkins-changed-files
}

changed_files() {
  if [[ -n "${CHANGE_TARGET:-}" ]]; then
    git diff --name-only "origin/${CHANGE_TARGET}...HEAD"
  elif [[ -n "${GIT_PREVIOUS_SUCCESSFUL_COMMIT:-}" && -n "${GIT_COMMIT:-}" ]]; then
    git diff --name-only "${GIT_PREVIOUS_SUCCESSFUL_COMMIT}..${GIT_COMMIT}"
  elif [[ -n "${GIT_PREVIOUS_COMMIT:-}" && -n "${GIT_COMMIT:-}" ]]; then
    git diff --name-only "${GIT_PREVIOUS_COMMIT}..${GIT_COMMIT}"
  else
    git show --name-only --pretty="" HEAD
  fi
}

if ! changed_files > .jenkins-changed-files; then
  git -c color.ui=never show --name-only --pretty="" HEAD > .jenkins-changed-files
fi

sed -i 's#\\#/#g; s#^\./##; /^[[:space:]]*$/d' .jenkins-changed-files

read -r -a maven_modules <<< "${MAVEN_MODULES:-}"
read -r -a docker_services <<< "${DOCKER_SERVICES:-}"

rebuild_all=false
if [[ "${BUILD_ALL:-false}" == "true" ]] ||
   grep -Eq '^(pom\.xml|common-library/|checkstyle/)' .jenkins-changed-files; then
  rebuild_all=true
fi

affected_maven=()
affected_docker=()

if [[ "$rebuild_all" == "true" ]]; then
  affected_maven=("${maven_modules[@]}")
  affected_docker=("${docker_services[@]}")
else
  for module in "${maven_modules[@]}"; do
    if contains_service_change "$module"; then
      affected_maven+=("$module")
    fi
  done

  for service in "${docker_services[@]}"; do
    if contains_service_change "$service"; then
      affected_docker+=("$service")
    fi
  done
fi

image_tag="$(git rev-parse --short=8 HEAD)"

{
  printf 'AFFECTED_MODULES=%s\n' "$(csv_join "${affected_maven[@]}")"
  printf 'AFFECTED_DOCKER_MODULES=%s\n' "$(csv_join "${affected_docker[@]}")"
  printf 'IMAGE_TAG=%s\n' "$image_tag"
} > .jenkins-ci-env

echo "rebuildAll=${rebuild_all}"
echo "Changed files:"
cat .jenkins-changed-files
echo "Affected Maven modules: ${affected_maven[*]:-none}"
echo "Affected Docker services: ${affected_docker[*]:-none}"
echo "Image tag: ${image_tag}"
