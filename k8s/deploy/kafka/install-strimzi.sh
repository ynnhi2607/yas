#!/bin/bash
set -euo pipefail

STRIMZI_VERSION="${STRIMZI_VERSION:-0.45.2}"
STRIMZI_NAMESPACE="${STRIMZI_NAMESPACE:-kafka}"
RESET_STRIMZI_CRDS="${RESET_STRIMZI_CRDS:-false}"

STRIMZI_CRDS=(
  kafkabridges.kafka.strimzi.io
  kafkaconnectors.kafka.strimzi.io
  kafkaconnects.kafka.strimzi.io
  kafkamirrormaker2s.kafka.strimzi.io
  kafkamirrormakers.kafka.strimzi.io
  kafkanodepools.kafka.strimzi.io
  kafkarebalances.kafka.strimzi.io
  kafkas.kafka.strimzi.io
  kafkatopics.kafka.strimzi.io
  kafkausers.kafka.strimzi.io
  strimzipodsets.core.strimzi.io
)

kubectl create namespace "${STRIMZI_NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

if [[ "${RESET_STRIMZI_CRDS}" == "true" ]]; then
  echo "RESET_STRIMZI_CRDS=true: removing old Strimzi operator and CRDs before reinstall."
  helm uninstall kafka-operator -n "${STRIMZI_NAMESPACE}" >/dev/null 2>&1 || true
  kubectl scale deploy/strimzi-cluster-operator -n "${STRIMZI_NAMESPACE}" --replicas=0 >/dev/null 2>&1 || true
  kubectl delete crd "${STRIMZI_CRDS[@]}" --ignore-not-found
fi

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

curl -fsSL \
  "https://github.com/strimzi/strimzi-kafka-operator/releases/download/${STRIMZI_VERSION}/strimzi-${STRIMZI_VERSION}.tar.gz" \
  -o "${TMP_DIR}/strimzi.tar.gz"
tar -xzf "${TMP_DIR}/strimzi.tar.gz" -C "${TMP_DIR}"

INSTALL_DIR="${TMP_DIR}/strimzi-${STRIMZI_VERSION}/install/cluster-operator"
sed -i "s/namespace: .*/namespace: ${STRIMZI_NAMESPACE}/g" "${INSTALL_DIR}"/*RoleBinding*.yaml

kubectl apply -f "${INSTALL_DIR}" -n "${STRIMZI_NAMESPACE}"
kubectl rollout status deploy/strimzi-cluster-operator -n "${STRIMZI_NAMESPACE}" --timeout=300s

echo "Strimzi ${STRIMZI_VERSION} is installed in namespace ${STRIMZI_NAMESPACE}."
