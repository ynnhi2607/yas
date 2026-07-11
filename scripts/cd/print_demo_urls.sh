#!/usr/bin/env bash
set -euo pipefail

INGRESS_NAMESPACE="${INGRESS_NAMESPACE:-ingress-nginx}"
INGRESS_SERVICE="${INGRESS_SERVICE:-ingress-nginx-controller}"
HOST_IP="${HOST_IP:-${GCP_VM_IP:-34.87.83.182}}"

ingress_type="$(kubectl get svc -n "$INGRESS_NAMESPACE" "$INGRESS_SERVICE" -o jsonpath='{.spec.type}' 2>/dev/null || true)"

echo "Ingress service: ${INGRESS_NAMESPACE}/${INGRESS_SERVICE}"
echo "Ingress service type: ${ingress_type:-unknown}"
echo "Browser host IP: ${HOST_IP}"

echo
echo "Add these host records on the machine that opens the browser:"
cat <<HOSTS
${HOST_IP} storefront.yas.local.com
${HOST_IP} backoffice.yas.local.com
${HOST_IP} api.yas.local.com
${HOST_IP} identity.yas.local.com
${HOST_IP} akhq.yas.local.com
${HOST_IP} pgadmin.yas.local.com
${HOST_IP} kibana.yas.local.com
${HOST_IP} storefront-dev.yas.local.com
${HOST_IP} backoffice-dev.yas.local.com
${HOST_IP} api-dev.yas.local.com
${HOST_IP} storefront-staging.yas.local.com
${HOST_IP} backoffice-staging.yas.local.com
${HOST_IP} api-staging.yas.local.com
HOSTS

echo
echo "Demo URLs:"
cat <<URLS
http://storefront.yas.local.com
http://backoffice.yas.local.com
http://api.yas.local.com/swagger-ui/
http://identity.yas.local.com/admin

http://storefront-dev.yas.local.com
http://backoffice-dev.yas.local.com
http://api-dev.yas.local.com/swagger-ui/

http://storefront-staging.yas.local.com
http://backoffice-staging.yas.local.com
http://api-staging.yas.local.com/swagger-ui/
URLS

echo
echo "NodePort URLs, if the K3d cluster exposes NodePort traffic on the VM:"
cat <<URLS
Dev storefront UI:  http://${HOST_IP}:30080
Dev backoffice UI:  http://${HOST_IP}:30081
Dev storefront BFF: http://${HOST_IP}:30082
Dev backoffice BFF: http://${HOST_IP}:30083
Dev swagger UI:     http://${HOST_IP}:30084/swagger-ui

Staging storefront UI:  http://${HOST_IP}:30180
Staging backoffice UI:  http://${HOST_IP}:30181
Staging storefront BFF: http://${HOST_IP}:30182
Staging backoffice BFF: http://${HOST_IP}:30183
Staging swagger UI:     http://${HOST_IP}:30184/swagger-ui
URLS
