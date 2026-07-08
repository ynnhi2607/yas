#!/usr/bin/env bash
set -euo pipefail

MESH_NAMESPACES="${MESH_NAMESPACES:-yas-dev yas-staging}"

for namespace in $MESH_NAMESPACES; do
  kubectl label namespace "$namespace" istio-injection- || true
  kubectl delete peerauthentication default -n "$namespace" --ignore-not-found
  kubectl delete peerauthentication -n "$namespace" -l app.kubernetes.io/part-of=yas-service-mesh --ignore-not-found
  kubectl delete destinationrule -n "$namespace" -l app.kubernetes.io/part-of=yas-service-mesh --ignore-not-found
  kubectl delete destinationrule default-istio-mutual keycloak-no-tls postgres-no-tls redis-no-tls kafka-no-tls elasticsearch-no-tls -n "$namespace" --ignore-not-found
  kubectl delete authorizationpolicy -n "$namespace" -l app.kubernetes.io/part-of=yas-service-mesh --ignore-not-found
  kubectl delete gateway -n "$namespace" -l app.kubernetes.io/part-of=yas-service-mesh --ignore-not-found
  kubectl delete virtualservice -n "$namespace" -l app.kubernetes.io/part-of=yas-service-mesh --ignore-not-found
  kubectl rollout restart deployment -n "$namespace"
done

for namespace in $MESH_NAMESPACES; do
  kubectl rollout status deployment -n "$namespace" --timeout=600s || true
done
