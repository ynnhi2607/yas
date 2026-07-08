#!/usr/bin/env bash
set -euo pipefail

MESH_NAMESPACES="${MESH_NAMESPACES:-yas-dev yas-staging}"

principal() {
  local namespace="$1"
  local service_account="$2"
  printf 'cluster.local/ns/%s/sa/%s' "$namespace" "$service_account"
}

for namespace in $MESH_NAMESPACES; do
  kubectl get namespace "$namespace" >/dev/null

  for public_service in storefront-ui backoffice-ui storefront-bff backoffice-bff swagger-ui yas-dev-swagger-ui yas-staging-swagger-ui; do
    cat <<YAML | kubectl apply -f -
apiVersion: security.istio.io/v1
kind: AuthorizationPolicy
metadata:
  name: allow-public-${public_service}
  namespace: ${namespace}
  labels:
    app.kubernetes.io/part-of: yas-service-mesh
spec:
  action: ALLOW
  selector:
    matchLabels:
      app.kubernetes.io/name: ${public_service}
  rules:
    - {}
YAML
  done

  cat <<YAML | kubectl apply -f -
---
apiVersion: security.istio.io/v1
kind: AuthorizationPolicy
metadata:
  name: allow-health-checks
  namespace: ${namespace}
  labels:
    app.kubernetes.io/part-of: yas-service-mesh
spec:
  action: ALLOW
  rules:
    - to:
        - operation:
            paths:
              - /
              - /health
              - /actuator/health
              - /actuator/health/*
              - /actuator/prometheus
YAML

  cat <<YAML | kubectl apply -f -
apiVersion: security.istio.io/v1
kind: AuthorizationPolicy
metadata:
  name: allow-to-product
  namespace: ${namespace}
  labels:
    app.kubernetes.io/part-of: yas-service-mesh
spec:
  action: ALLOW
  selector:
    matchLabels:
      app.kubernetes.io/name: product
  rules:
    - from:
        - source:
            principals:
              - "$(principal "$namespace" storefront-bff)"
              - "$(principal "$namespace" backoffice-bff)"
              - "$(principal "$namespace" cart)"
              - "$(principal "$namespace" order)"
              - "$(principal "$namespace" search)"
              - "$(principal "$namespace" inventory)"
---
apiVersion: security.istio.io/v1
kind: AuthorizationPolicy
metadata:
  name: allow-to-cart
  namespace: ${namespace}
  labels:
    app.kubernetes.io/part-of: yas-service-mesh
spec:
  action: ALLOW
  selector:
    matchLabels:
      app.kubernetes.io/name: cart
  rules:
    - from:
        - source:
            principals:
              - "$(principal "$namespace" storefront-bff)"
              - "$(principal "$namespace" order)"
---
apiVersion: security.istio.io/v1
kind: AuthorizationPolicy
metadata:
  name: allow-to-customer
  namespace: ${namespace}
  labels:
    app.kubernetes.io/part-of: yas-service-mesh
spec:
  action: ALLOW
  selector:
    matchLabels:
      app.kubernetes.io/name: customer
  rules:
    - from:
        - source:
            principals:
              - "$(principal "$namespace" storefront-bff)"
              - "$(principal "$namespace" backoffice-bff)"
              - "$(principal "$namespace" order)"
---
apiVersion: security.istio.io/v1
kind: AuthorizationPolicy
metadata:
  name: allow-to-order
  namespace: ${namespace}
  labels:
    app.kubernetes.io/part-of: yas-service-mesh
spec:
  action: ALLOW
  selector:
    matchLabels:
      app.kubernetes.io/name: order
  rules:
    - from:
        - source:
            principals:
              - "$(principal "$namespace" storefront-bff)"
              - "$(principal "$namespace" backoffice-bff)"
YAML

  cat <<YAML | kubectl apply -f -
apiVersion: security.istio.io/v1
kind: AuthorizationPolicy
metadata:
  name: allow-to-tax
  namespace: ${namespace}
  labels:
    app.kubernetes.io/part-of: yas-service-mesh
spec:
  action: ALLOW
  selector:
    matchLabels:
      app.kubernetes.io/name: tax
  rules:
    - from:
        - source:
            principals:
              - "$(principal "$namespace" order)"
              - "$(principal "$namespace" storefront-bff)"
              - "$(principal "$namespace" backoffice-bff)"
---
apiVersion: security.istio.io/v1
kind: AuthorizationPolicy
metadata:
  name: allow-to-search
  namespace: ${namespace}
  labels:
    app.kubernetes.io/part-of: yas-service-mesh
spec:
  action: ALLOW
  selector:
    matchLabels:
      app.kubernetes.io/name: search
  rules:
    - from:
        - source:
            principals:
              - "$(principal "$namespace" storefront-bff)"
              - "$(principal "$namespace" backoffice-bff)"
---
apiVersion: security.istio.io/v1
kind: AuthorizationPolicy
metadata:
  name: allow-to-inventory
  namespace: ${namespace}
  labels:
    app.kubernetes.io/part-of: yas-service-mesh
spec:
  action: ALLOW
  selector:
    matchLabels:
      app.kubernetes.io/name: inventory
  rules:
    - from:
        - source:
            principals:
              - "$(principal "$namespace" storefront-bff)"
              - "$(principal "$namespace" backoffice-bff)"
              - "$(principal "$namespace" order)"
---
apiVersion: security.istio.io/v1
kind: AuthorizationPolicy
metadata:
  name: allow-to-media
  namespace: ${namespace}
  labels:
    app.kubernetes.io/part-of: yas-service-mesh
spec:
  action: ALLOW
  selector:
    matchLabels:
      app.kubernetes.io/name: media
  rules:
    - from:
        - source:
            principals:
              - "$(principal "$namespace" storefront-bff)"
              - "$(principal "$namespace" backoffice-bff)"
              - "$(principal "$namespace" product)"
              - "$(principal "$namespace" cart)"
YAML

  cat <<YAML | kubectl apply -f -
apiVersion: security.istio.io/v1
kind: AuthorizationPolicy
metadata:
  name: allow-to-sampledata
  namespace: ${namespace}
  labels:
    app.kubernetes.io/part-of: yas-service-mesh
spec:
  action: ALLOW
  selector:
    matchLabels:
      app.kubernetes.io/name: sampledata
  rules:
    - from:
        - source:
            principals:
              - "$(principal "$namespace" storefront-bff)"
              - "$(principal "$namespace" backoffice-bff)"
---
apiVersion: security.istio.io/v1
kind: AuthorizationPolicy
metadata:
  name: deny-all-by-default
  namespace: ${namespace}
  labels:
    app.kubernetes.io/part-of: yas-service-mesh
spec:
  action: ALLOW
YAML
done

echo "Applied Istio AuthorizationPolicy allow-list to: ${MESH_NAMESPACES}"
echo "Public entrypoints remain open; internal services are restricted by service account principals."
