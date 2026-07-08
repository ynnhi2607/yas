#!/usr/bin/env bash
set -euo pipefail

MESH_NAMESPACES="${MESH_NAMESPACES:-yas-dev yas-staging}"
BACKEND_SERVICES="${BACKEND_SERVICES:-backoffice-bff storefront-bff cart customer inventory media order product search tax}"

cat <<'WARN'
WARNING:
STRICT mTLS rejects plain traffic from workloads outside the mesh. Use this only after
Istio Gateway/VirtualService and AuthorizationPolicy have been applied and tested.
If nginx ingress must remain the public path, keep PERMISSIVE instead.

Set CONFIRM_STRICT=true to continue.
WARN

if [[ "${CONFIRM_STRICT:-false}" != "true" ]]; then
  exit 1
fi

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
    mode: STRICT
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
---
apiVersion: networking.istio.io/v1
kind: DestinationRule
metadata:
  name: keycloak-no-tls
  namespace: ${namespace}
spec:
  host: "keycloak-service.keycloak.svc.cluster.local"
  trafficPolicy:
    tls:
      mode: DISABLE
---
apiVersion: networking.istio.io/v1
kind: DestinationRule
metadata:
  name: postgres-no-tls
  namespace: ${namespace}
spec:
  host: "*.postgres.svc.cluster.local"
  trafficPolicy:
    tls:
      mode: DISABLE
---
apiVersion: networking.istio.io/v1
kind: DestinationRule
metadata:
  name: redis-no-tls
  namespace: ${namespace}
spec:
  host: "*.redis.svc.cluster.local"
  trafficPolicy:
    tls:
      mode: DISABLE
---
apiVersion: networking.istio.io/v1
kind: DestinationRule
metadata:
  name: kafka-no-tls
  namespace: ${namespace}
spec:
  host: "*.kafka.svc.cluster.local"
  trafficPolicy:
    tls:
      mode: DISABLE
---
apiVersion: networking.istio.io/v1
kind: DestinationRule
metadata:
  name: elasticsearch-no-tls
  namespace: ${namespace}
spec:
  host: "*.elasticsearch.svc.cluster.local"
  trafficPolicy:
    tls:
      mode: DISABLE
YAML

  for service in $BACKEND_SERVICES; do
    cat <<YAML | kubectl apply -f -
apiVersion: security.istio.io/v1
kind: PeerAuthentication
metadata:
  name: ${service}-metrics
  namespace: ${namespace}
  labels:
    app.kubernetes.io/part-of: yas-service-mesh
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: ${service}
  mtls:
    mode: STRICT
  portLevelMtls:
    8090:
      mode: DISABLE
YAML
  done
done

echo "Applied STRICT mTLS policies to: ${MESH_NAMESPACES}"
echo "Rollback to PERMISSIVE with: MTLS_MODE=PERMISSIVE MESH_NAMESPACES=\"${MESH_NAMESPACES}\" ./service-mesh/apply-policies.sh"
