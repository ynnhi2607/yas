#!/usr/bin/env bash
set -euo pipefail

MESH_NAMESPACES="${MESH_NAMESPACES:-yas-dev yas-staging}"

domain_prefix_for_namespace() {
  case "$1" in
    yas-dev) printf 'dev' ;;
    yas-staging) printf 'staging' ;;
    yas) printf 'prod' ;;
    *) printf '%s' "$1" ;;
  esac
}

host_for_namespace() {
  local namespace="$1"
  local app="$2"

  case "$namespace" in
    yas-dev) printf '%s-dev.yas.local.com' "$app" ;;
    yas-staging) printf '%s-staging.yas.local.com' "$app" ;;
    yas) printf '%s.yas.local.com' "$app" ;;
    *) printf '%s-%s.yas.local.com' "$app" "$namespace" ;;
  esac
}

swagger_service_for_namespace() {
  case "$1" in
    yas-dev) printf 'yas-dev-swagger-ui' ;;
    yas-staging) printf 'yas-staging-swagger-ui' ;;
    yas) printf 'swagger-ui' ;;
    *) printf 'swagger-ui' ;;
  esac
}

for namespace in $MESH_NAMESPACES; do
  kubectl get namespace "$namespace" >/dev/null

  storefront_host="$(host_for_namespace "$namespace" storefront)"
  backoffice_host="$(host_for_namespace "$namespace" backoffice)"
  api_host="$(host_for_namespace "$namespace" api)"
  swagger_service="$(swagger_service_for_namespace "$namespace")"

  cat <<YAML | kubectl apply -f -
apiVersion: networking.istio.io/v1
kind: Gateway
metadata:
  name: yas-gateway
  namespace: ${namespace}
  labels:
    app.kubernetes.io/part-of: yas-service-mesh
spec:
  selector:
    istio: ingressgateway
  servers:
    - port:
        number: 80
        name: http
        protocol: HTTP
      hosts:
        - ${storefront_host}
        - ${backoffice_host}
        - ${api_host}
---
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: yas-web
  namespace: ${namespace}
  labels:
    app.kubernetes.io/part-of: yas-service-mesh
spec:
  hosts:
    - ${storefront_host}
    - ${backoffice_host}
    - ${api_host}
  gateways:
    - yas-gateway
  http:
    - match:
        - authority:
            regex: '^${storefront_host}(:[0-9]+)?$'
          uri:
            prefix: /api
        - authority:
            regex: '^${storefront_host}(:[0-9]+)?$'
          uri:
            prefix: /oauth2
        - authority:
            regex: '^${storefront_host}(:[0-9]+)?$'
          uri:
            prefix: /login
        - authority:
            regex: '^${storefront_host}(:[0-9]+)?$'
          uri:
            prefix: /logout
      route:
        - destination:
            host: storefront-bff.${namespace}.svc.cluster.local
            port:
              number: 80
      timeout: 30s
      retries:
        attempts: 3
        perTryTimeout: 5s
        retryOn: 5xx,reset,connect-failure
    - match:
        - authority:
            regex: '^${storefront_host}(:[0-9]+)?$'
      route:
        - destination:
            host: storefront-ui.${namespace}.svc.cluster.local
            port:
              number: 3000
      timeout: 30s
    - match:
        - authority:
            regex: '^${backoffice_host}(:[0-9]+)?$'
          uri:
            prefix: /api
        - authority:
            regex: '^${backoffice_host}(:[0-9]+)?$'
          uri:
            prefix: /oauth2
        - authority:
            regex: '^${backoffice_host}(:[0-9]+)?$'
          uri:
            prefix: /login
        - authority:
            regex: '^${backoffice_host}(:[0-9]+)?$'
          uri:
            prefix: /logout
      route:
        - destination:
            host: backoffice-bff.${namespace}.svc.cluster.local
            port:
              number: 80
      timeout: 30s
      retries:
        attempts: 3
        perTryTimeout: 5s
        retryOn: 5xx,reset,connect-failure
    - match:
        - authority:
            regex: '^${backoffice_host}(:[0-9]+)?$'
      route:
        - destination:
            host: backoffice-ui.${namespace}.svc.cluster.local
            port:
              number: 3000
      timeout: 30s
    - match:
        - authority:
            regex: '^${api_host}(:[0-9]+)?$'
          uri:
            prefix: /swagger-ui
      route:
        - destination:
            host: ${swagger_service}.${namespace}.svc.cluster.local
            port:
              number: 8080
      timeout: 30s
    - match:
        - authority:
            regex: '^${api_host}(:[0-9]+)?$'
      route:
        - destination:
            host: storefront-bff.${namespace}.svc.cluster.local
            port:
              number: 80
      timeout: 30s
---
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: tax-retry
  namespace: ${namespace}
  labels:
    app.kubernetes.io/part-of: yas-service-mesh
spec:
  hosts:
    - tax
    - tax.${namespace}.svc.cluster.local
  http:
    - route:
        - destination:
            host: tax.${namespace}.svc.cluster.local
            port:
              number: 80
      timeout: 30s
      retries:
        attempts: 3
        perTryTimeout: 5s
        retryOn: 5xx,retriable-4xx,connect-failure,reset
---
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: product-retry
  namespace: ${namespace}
  labels:
    app.kubernetes.io/part-of: yas-service-mesh
spec:
  hosts:
    - product
    - product.${namespace}.svc.cluster.local
  http:
    - route:
        - destination:
            host: product.${namespace}.svc.cluster.local
            port:
              number: 80
      timeout: 30s
      retries:
        attempts: 3
        perTryTimeout: 5s
        retryOn: 5xx,connect-failure,reset
---
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: elasticsearch-header-fix
  namespace: ${namespace}
  labels:
    app.kubernetes.io/part-of: yas-service-mesh
spec:
  hosts:
    - elasticsearch-es-http.elasticsearch.svc.cluster.local
    - elasticsearch-es-http.elasticsearch
  http:
    - match:
        - method:
            regex: '^(HEAD|GET)$'
      route:
        - destination:
            host: elasticsearch-es-http.elasticsearch.svc.cluster.local
            port:
              number: 9200
      headers:
        request:
          set:
            Accept: application/json
          remove:
            - Content-Type
    - route:
        - destination:
            host: elasticsearch-es-http.elasticsearch.svc.cluster.local
            port:
              number: 9200
      headers:
        request:
          set:
            Accept: application/json
            Content-Type: application/json
YAML
done

echo "Applied Istio Gateway, VirtualService, retry, and Elasticsearch header policies to: ${MESH_NAMESPACES}"
echo "Use test-istio-gateway.sh to test through istio-ingressgateway without replacing nginx ingress."
