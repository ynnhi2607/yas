#!/usr/bin/env bash
set -euo pipefail

MESH_NAMESPACES="${MESH_NAMESPACES:-yas-dev yas-staging}"

for namespace in $MESH_NAMESPACES; do
  kubectl label namespace "$namespace" istio-injection- || true
  kubectl delete peerauthentication default -n "$namespace" --ignore-not-found
  kubectl delete destinationrule default-istio-mutual -n "$namespace" --ignore-not-found
  kubectl rollout restart deployment -n "$namespace"
done

for namespace in $MESH_NAMESPACES; do
  kubectl rollout status deployment -n "$namespace" --timeout=600s || true
done
