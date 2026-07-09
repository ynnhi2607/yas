#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="${NAMESPACE:-yas}"
DELETE_NAMESPACE="${DELETE_NAMESPACE:-false}"

RELEASES=(
  swagger-ui
  backoffice-ui
  storefront-ui
  backoffice-bff
  storefront-bff
  sampledata
  search
  media
  payment-paypal
  payment
  tax
  location
  inventory
  customer
  order
  cart
  product
  yas-configuration
)

echo "Deleting YAS demo releases from namespace '${NAMESPACE}'..."

for release in "${RELEASES[@]}"; do
  if helm status "$release" --namespace "$NAMESPACE" >/dev/null 2>&1; then
    echo "Uninstall ${release}"
    helm uninstall "$release" --namespace "$NAMESPACE"
  fi
done

if [[ "$DELETE_NAMESPACE" == "true" ]]; then
  echo "Deleting namespace ${NAMESPACE}"
  kubectl delete namespace "$NAMESPACE"
fi

echo "Done."
