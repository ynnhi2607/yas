#!/usr/bin/env bash
set -euo pipefail

ISTIO_NAMESPACE="${ISTIO_NAMESPACE:-istio-system}"

kubectl create namespace "$ISTIO_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

helm repo add istio https://istio-release.storage.googleapis.com/charts
helm repo update

helm upgrade --install istio-base istio/base \
  --namespace "$ISTIO_NAMESPACE" \
  --set defaultRevision=default \
  --wait \
  --timeout=10m

helm upgrade --install istiod istio/istiod \
  --namespace "$ISTIO_NAMESPACE" \
  --wait \
  --timeout=10m

kubectl rollout status deployment/istiod -n "$ISTIO_NAMESPACE" --timeout=300s
kubectl get pods -n "$ISTIO_NAMESPACE"
