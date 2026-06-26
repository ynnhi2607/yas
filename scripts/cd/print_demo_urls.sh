#!/usr/bin/env bash
set -euo pipefail

INGRESS_NAMESPACE="${INGRESS_NAMESPACE:-ingress-nginx}"
INGRESS_SERVICE="${INGRESS_SERVICE:-ingress-nginx-controller}"

node_port="$(kubectl get svc -n "$INGRESS_NAMESPACE" "$INGRESS_SERVICE" -o jsonpath='{.spec.ports[?(@.port==80)].nodePort}')"
minikube_ip="$(minikube ip 2>/dev/null || true)"

echo "HTTP NodePort: ${node_port}"
if [[ -n "$minikube_ip" ]]; then
  echo "Minikube IP: ${minikube_ip}"
fi

echo
echo "Add these host records on the machine that opens the browser:"
host_ip="${minikube_ip:-<worker-node-ip>}"
cat <<HOSTS
${host_ip} storefront.yas.local.com
${host_ip} backoffice.yas.local.com
${host_ip} api.yas.local.com
${host_ip} identity.yas.local.com
${host_ip} akhq.yas.local.com
${host_ip} pgadmin.yas.local.com
${host_ip} kibana.yas.local.com
HOSTS

echo
echo "Demo URLs:"
cat <<URLS
http://storefront.yas.local.com:${node_port}
http://backoffice.yas.local.com:${node_port}
http://api.yas.local.com:${node_port}/swagger-ui/
http://identity.yas.local.com:${node_port}/admin
URLS
