#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MESH_NAMESPACES="${MESH_NAMESPACES:-yas-dev yas-staging}"

for namespace in $MESH_NAMESPACES; do
  kubectl get namespace "$namespace" >/dev/null
  kubectl label namespace "$namespace" istio-injection=enabled --overwrite

  cat <<YAML | kubectl apply -f -
apiVersion: security.istio.io/v1
kind: PeerAuthentication
metadata:
  name: default
  namespace: ${namespace}
spec:
  mtls:
    mode: PERMISSIVE
YAML

  kubectl rollout restart deployment -n "$namespace"
done

for namespace in $MESH_NAMESPACES; do
  kubectl rollout status deployment -n "$namespace" --timeout=600s || true
done

"$SCRIPT_DIR/verify-mesh.sh"
