#!/usr/bin/env bash
set -euo pipefail

ISTIO_NAMESPACE="${ISTIO_NAMESPACE:-istio-system}"
MESH_NAMESPACES="${MESH_NAMESPACES:-yas-dev yas-staging}"

echo "== Istio control plane =="
kubectl get pods -n "$ISTIO_NAMESPACE"

echo
for namespace in $MESH_NAMESPACES; do
  echo "== Namespace: ${namespace} =="
  kubectl get namespace "$namespace" --show-labels
  kubectl get peerauthentication -n "$namespace" || true
  kubectl get destinationrule -n "$namespace" || true
  kubectl get authorizationpolicy -n "$namespace" || true
  kubectl get gateway,virtualservice -n "$namespace" || true
  kubectl get pods -n "$namespace"

  echo
  echo "Containers:"
  kubectl get pods -n "$namespace" -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{range .spec.containers[*]}{.name}{" "}{end}{"\n"}{end}'
  echo
done
