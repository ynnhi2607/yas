#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/../.."

JENKINS_IMAGE="${JENKINS_IMAGE:-jenkins-yas-tools}"
JENKINS_CONTAINER="${JENKINS_CONTAINER:-jenkins-yas}"
JENKINS_PORT="${JENKINS_PORT:-8080}"
PUBLIC_IP="${PUBLIC_IP:-}"

if ! command -v docker >/dev/null 2>&1; then
  echo "Docker is required to run Jenkins." >&2
  exit 1
fi

docker build -t "${JENKINS_IMAGE}" -f jenkins/Dockerfile .

if docker ps -a --format '{{.Names}}' | grep -qx "${JENKINS_CONTAINER}"; then
  docker rm -f "${JENKINS_CONTAINER}"
fi

docker run -d \
  --name "${JENKINS_CONTAINER}" \
  --restart unless-stopped \
  --network host \
  -v jenkins_home:/var/jenkins_home \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v "${HOME}/.kube:/root/.kube" \
  "${JENKINS_IMAGE}"

if [ -z "${PUBLIC_IP}" ] && command -v curl >/dev/null 2>&1; then
  PUBLIC_IP="$(curl -sf -H 'Metadata-Flavor: Google' \
    http://metadata.google.internal/computeMetadata/v1/instance/network-interfaces/0/access-configs/0/external-ip || true)"
fi

if [ -z "${PUBLIC_IP}" ]; then
  PUBLIC_IP="<VM_EXTERNAL_IP>"
fi

echo "Jenkins is starting at: http://${PUBLIC_IP}:${JENKINS_PORT}"
echo "If this is a first-time setup, get the initial password with:"
echo "docker exec ${JENKINS_CONTAINER} cat /var/jenkins_home/secrets/initialAdminPassword"
