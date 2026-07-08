#!/usr/bin/env bash
set -euo pipefail

ISTIO_NAMESPACE="${ISTIO_NAMESPACE:-istio-system}"
INSTALL_ISTIO_GATEWAY="${INSTALL_ISTIO_GATEWAY:-true}"

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

if [[ "$INSTALL_ISTIO_GATEWAY" == "true" ]]; then
  helm upgrade --install istio-ingressgateway istio/gateway \
    --namespace "$ISTIO_NAMESPACE" \
    --wait \
    --timeout=10m

  kubectl rollout status deployment/istio-ingressgateway -n "$ISTIO_NAMESPACE" --timeout=300s
fi

kubectl get pods -n "$ISTIO_NAMESPACE"
