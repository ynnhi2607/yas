#!/usr/bin/env bash
set -euo pipefail

INGRESS_URL="${INGRESS_URL:-http://127.0.0.1}"

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
  echo "== ${host}${path} =="
  curl -sS -I -H "Host: ${host}" "${INGRESS_URL}${path}" | sed -n '1,20p'
done

cat <<'NOTE'

Evidence hints:
- HTTP 200/302 proves the app is still reachable after sidecar injection.
- x-envoy-upstream-service-time or x-envoy-decorator-operation proves traffic passed through Envoy sidecar.
NOTE
