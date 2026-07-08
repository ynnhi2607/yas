#!/usr/bin/env bash
set -euo pipefail

ISTIO_NAMESPACE="${ISTIO_NAMESPACE:-istio-system}"
INGRESS_NGINX_NAMESPACE="${INGRESS_NGINX_NAMESPACE:-ingress-nginx}"
INGRESS_NGINX_SERVICE="${INGRESS_NGINX_SERVICE:-ingress-nginx-controller}"
ISTIO_GATEWAY_SERVICE="${ISTIO_GATEWAY_SERVICE:-istio-ingressgateway}"
TRAEFIK_NAMESPACE="${TRAEFIK_NAMESPACE:-kube-system}"
TRAEFIK_SERVICE="${TRAEFIK_SERVICE:-traefik}"
K3D_LOADBALANCER_CONTAINER="${K3D_LOADBALANCER_CONTAINER:-k3d-yas-cluster-serverlb}"
WAIT_SECONDS="${WAIT_SECONDS:-30}"
VERIFY_TIMEOUT_SECONDS="${VERIFY_TIMEOUT_SECONDS:-180}"

patch_service_type() {
  local namespace="$1"
  local service="$2"
  local type="$3"

  if kubectl get svc "$service" -n "$namespace" >/dev/null 2>&1; then
    kubectl patch svc "$service" -n "$namespace" -p "{\"spec\":{\"type\":\"${type}\"}}"
  else
    echo "Service not found, skipping: ${namespace}/${service}"
  fi
}

delete_svclb_pods() {
  local service="$1"
  local pods

  pods="$(kubectl get pods -n kube-system -o name | grep "svclb-${service}" || true)"
  if [[ -n "$pods" ]]; then
    printf '%s\n' "$pods" | xargs kubectl delete -n kube-system --ignore-not-found=true
  fi

  kubectl delete pod -n kube-system \
    -l "svccontroller.k3s.cattle.io/svcname=${service}" \
    --ignore-not-found=true
}

wait_no_svclb_pods() {
  local service="$1"
  local deadline=$((SECONDS + VERIFY_TIMEOUT_SECONDS))

  while (( SECONDS < deadline )); do
    if ! kubectl get pods -n kube-system -o name | grep -q "svclb-${service}"; then
      return 0
    fi
    sleep 5
  done

  echo "Timed out waiting for svclb-${service} pods to disappear." >&2
  kubectl get pods -n kube-system | grep "svclb-${service}" || true
  return 1
}

restart_k3d_loadbalancer() {
  if command -v docker >/dev/null 2>&1 && docker ps --format '{{.Names}}' | grep -qx "$K3D_LOADBALANCER_CONTAINER"; then
    echo "Restarting k3d load balancer container: ${K3D_LOADBALANCER_CONTAINER}"
    docker restart "$K3D_LOADBALANCER_CONTAINER" >/dev/null
  else
    echo "k3d load balancer container not found or docker unavailable; skipping restart."
  fi
}

echo "Switching public HTTP/HTTPS entrypoint from nginx ingress to Istio ingressgateway..."

patch_service_type "$INGRESS_NGINX_NAMESPACE" "$INGRESS_NGINX_SERVICE" ClusterIP
patch_service_type "$TRAEFIK_NAMESPACE" "$TRAEFIK_SERVICE" ClusterIP
patch_service_type "$ISTIO_NAMESPACE" "$ISTIO_GATEWAY_SERVICE" LoadBalancer

echo "Recycling k3s service load-balancer pods so port 80/443 are rebound cleanly..."
delete_svclb_pods "$INGRESS_NGINX_SERVICE"
delete_svclb_pods "$TRAEFIK_SERVICE"
delete_svclb_pods "$ISTIO_GATEWAY_SERVICE"

wait_no_svclb_pods "$INGRESS_NGINX_SERVICE"
wait_no_svclb_pods "$TRAEFIK_SERVICE"

sleep "$WAIT_SECONDS"
restart_k3d_loadbalancer
sleep 10

echo "Waiting for Istio ingressgateway to become ready..."
deadline=$((SECONDS + VERIFY_TIMEOUT_SECONDS))
while (( SECONDS < deadline )); do
  if kubectl get pod -n "$ISTIO_NAMESPACE" -l app=istio-ingressgateway >/dev/null 2>&1; then
    if kubectl wait -n "$ISTIO_NAMESPACE" --for=condition=ready pod -l app=istio-ingressgateway --timeout=5s >/dev/null 2>&1; then
      break
    fi
  fi
  sleep 5
done

if (( SECONDS >= deadline )); then
  echo "Timed out waiting for istio-ingressgateway to become ready." >&2
  exit 1
fi

echo
echo "Services:"
kubectl get svc -n "$INGRESS_NGINX_NAMESPACE" "$INGRESS_NGINX_SERVICE" 2>/dev/null || true
kubectl get svc -n "$TRAEFIK_NAMESPACE" "$TRAEFIK_SERVICE" 2>/dev/null || true
kubectl get svc -n "$ISTIO_NAMESPACE" "$ISTIO_GATEWAY_SERVICE"

echo
echo "k3s load-balancer pods:"
kubectl get pods -n kube-system | grep -E "svclb-(${INGRESS_NGINX_SERVICE}|${TRAEFIK_SERVICE}|${ISTIO_GATEWAY_SERVICE})" || true

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
  echo "== ${host}${path} via public port 80 =="

  for i in $(seq 1 10); do
    headers="$(curl -sS -D - -o /dev/null -H "Host: ${host}" "http://127.0.0.1${path}")"
    status="$(printf '%s\n' "$headers" | awk 'BEGIN{IGNORECASE=1} /^HTTP\// {print $2; exit}')"
    server="$(printf '%s\n' "$headers" | awk 'BEGIN{IGNORECASE=1} /^server:/ {print $0; exit}')"
    content_type="$(printf '%s\n' "$headers" | awk 'BEGIN{IGNORECASE=1} /^content-type:/ {print $0; exit}')"
    envoy_time="$(printf '%s\n' "$headers" | awk 'BEGIN{IGNORECASE=1} /^x-envoy-upstream-service-time:/ {print $0; exit}')"

    printf '%s %s %s %s\n' "$status" "${server:-server: <missing>}" "${content_type:-content-type: <missing>}" "${envoy_time:-x-envoy: <missing>}"

    if [[ "$server" != *"istio-envoy"* && "$envoy_time" != x-envoy-upstream-service-time:* ]]; then
      echo "Request did not pass through Istio. Check if nginx, traefik, or another load balancer still owns port 80." >&2
      exit 1
    fi
  done
done

echo
echo "Public gateway switch completed."
