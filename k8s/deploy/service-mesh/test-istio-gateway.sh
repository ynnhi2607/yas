#!/usr/bin/env bash
set -euo pipefail

ISTIO_NAMESPACE="${ISTIO_NAMESPACE:-istio-system}"
LOCAL_PORT="${LOCAL_PORT:-18080}"

kubectl get svc istio-ingressgateway -n "$ISTIO_NAMESPACE" >/dev/null

if ! nc -z 127.0.0.1 "$LOCAL_PORT" >/dev/null 2>&1; then
  echo "Starting temporary port-forward to istio-ingressgateway on 127.0.0.1:${LOCAL_PORT} ..."
  kubectl port-forward -n "$ISTIO_NAMESPACE" svc/istio-ingressgateway "${LOCAL_PORT}:80" >/tmp/yas-istio-gateway-port-forward.log 2>&1 &
  pf_pid=$!
  trap 'kill "$pf_pid" >/dev/null 2>&1 || true' EXIT
  sleep 5
fi

HOSTS=(
  storefront-dev.yas.local.com
  api-dev.yas.local.com/swagger-ui/
  storefront-staging.yas.local.com
  api-staging.yas.local.com/swagger-ui/
)

for host_path in "${HOSTS[@]}"; do
  host="${host_path%%/*}"
  path="/"
  if [[ "$host_path" == */* ]]; then
    path="/${host_path#*/}"
  fi

  echo
  echo "== ${host}${path} via istio-ingressgateway =="
  curl -sS -I -H "Host: ${host}" "http://127.0.0.1:${LOCAL_PORT}${path}" | sed -n '1,24p'
done

cat <<'NOTE'

Evidence hints:
- HTTP 200/302 proves Istio Gateway and VirtualService routing work.
- server: istio-envoy or x-envoy-* headers prove traffic entered through Istio gateway.
NOTE
