#!/usr/bin/env bash
set -euo pipefail

MESH_NAMESPACES="${MESH_NAMESPACES:-yas-dev yas-staging}"
MTLS_MODE="${MTLS_MODE:-PERMISSIVE}"

for namespace in $MESH_NAMESPACES; do
  kubectl get namespace "$namespace" >/dev/null

  cat <<YAML | kubectl apply -f -
apiVersion: security.istio.io/v1
kind: PeerAuthentication
metadata:
  name: default
  namespace: ${namespace}
spec:
  mtls:
    mode: ${MTLS_MODE}
---
apiVersion: networking.istio.io/v1
kind: DestinationRule
metadata:
  name: default-istio-mutual
  namespace: ${namespace}
spec:
  host: "*.${namespace}.svc.cluster.local"
  trafficPolicy:
    tls:
      mode: ISTIO_MUTUAL
YAML
done

echo "Applied Istio mesh policies to: ${MESH_NAMESPACES}"
echo "PeerAuthentication mode: ${MTLS_MODE}"
