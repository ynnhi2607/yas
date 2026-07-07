#!/usr/bin/env bash
set -euo pipefail

ISTIO_NAMESPACE="${ISTIO_NAMESPACE:-istio-system}"

helm uninstall istiod -n "$ISTIO_NAMESPACE" || true
helm uninstall istio-base -n "$ISTIO_NAMESPACE" || true
kubectl delete namespace "$ISTIO_NAMESPACE" --ignore-not-found
