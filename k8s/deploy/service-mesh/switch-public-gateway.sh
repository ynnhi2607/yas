#!/usr/bin/env bash
set -euo pipefail

ISTIO_NAMESPACE="${ISTIO_NAMESPACE:-istio-system}"
INGRESS_NGINX_NAMESPACE="${INGRESS_NGINX_NAMESPACE:-ingress-nginx}"
INGRESS_NGINX_SERVICE="${INGRESS_NGINX_SERVICE:-ingress-nginx-controller}"
ISTIO_GATEWAY_SERVICE="${ISTIO_GATEWAY_SERVICE:-istio-ingressgateway}"
WAIT_SECONDS="${WAIT_SECONDS:-30}"

echo "Switching public HTTP/HTTPS entrypoint from nginx ingress to Istio ingressgateway..."

if kubectl get svc "$INGRESS_NGINX_SERVICE" -n "$INGRESS_NGINX_NAMESPACE" >/dev/null 2>&1; then
  kubectl patch svc "$INGRESS_NGINX_SERVICE" -n "$INGRESS_NGINX_NAMESPACE" \
    -p '{"spec":{"type":"ClusterIP"}}'
else
  echo "nginx ingress service not found: ${INGRESS_NGINX_NAMESPACE}/${INGRESS_NGINX_SERVICE}"
fi

kubectl patch svc "$ISTIO_GATEWAY_SERVICE" -n "$ISTIO_NAMESPACE" \
  -p '{"spec":{"type":"LoadBalancer"}}'

echo "Recycling k3s service load-balancer pods so port 80/443 are rebound cleanly..."
kubectl delete pod -n kube-system \
  -l "svccontroller.k3s.cattle.io/svcname=${INGRESS_NGINX_SERVICE}" \
  --ignore-not-found=true
kubectl delete pod -n kube-system \
  -l "svccontroller.k3s.cattle.io/svcname=${ISTIO_GATEWAY_SERVICE}" \
  --ignore-not-found=true

sleep "$WAIT_SECONDS"

echo
echo "Services:"
kubectl get svc -n "$INGRESS_NGINX_NAMESPACE" "$INGRESS_NGINX_SERVICE" 2>/dev/null || true
kubectl get svc -n "$ISTIO_NAMESPACE" "$ISTIO_GATEWAY_SERVICE"

echo
echo "k3s load-balancer pods:"
kubectl get pods -n kube-system | grep -E "svclb-(${INGRESS_NGINX_SERVICE}|${ISTIO_GATEWAY_SERVICE})" || true

echo
echo "Verifying every public request goes through Istio Envoy..."
hosts=(
  "storefront-dev.yas.local.com:/_next/static/chunks/main-723a52f81a2b937b.js"
  "storefront-dev.yas.local.com:/"
  "api-dev.yas.local.com:/swagger-ui/"
  "storefront-staging.yas.local.com:/"
  "api-staging.yas.local.com:/swagger-ui/"
)

for host_path in "${hosts[@]}"; do
  host="${host_path%%:*}"
  path="${host_path#*:}"
  echo
  echo "== ${host}${path} =="

  for i in $(seq 1 6); do
    headers="$(curl -sS -D - -o /dev/null -H "Host: ${host}" "http://127.0.0.1${path}")"
    status="$(printf '%s\n' "$headers" | awk 'BEGIN{IGNORECASE=1} /^HTTP\// {print $2; exit}')"
    server="$(printf '%s\n' "$headers" | awk 'BEGIN{IGNORECASE=1} /^server:/ {print $0; exit}')"
    content_type="$(printf '%s\n' "$headers" | awk 'BEGIN{IGNORECASE=1} /^content-type:/ {print $0; exit}')"
    envoy_time="$(printf '%s\n' "$headers" | awk 'BEGIN{IGNORECASE=1} /^x-envoy-upstream-service-time:/ {print $0; exit}')"

    printf '%s %s %s %s\n' "$status" "${server:-server: <missing>}" "${content_type:-content-type: <missing>}" "${envoy_time:-x-envoy: <missing>}"

    if [[ "$server" != *"istio-envoy"* && "$envoy_time" != x-envoy-upstream-service-time:* ]]; then
      echo "Request did not pass through Istio. Check if nginx or another load balancer still owns port 80." >&2
      exit 1
    fi
  done
done

echo
echo "Public gateway switch completed."
