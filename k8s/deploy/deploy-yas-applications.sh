#!/bin/bash
set -x

# Auto restart when change configmap or secret
helm repo add stakater https://stakater.github.io/stakater-charts
helm repo update

read -rd '' DOMAIN \
< <(yq -r '.domain' ./cluster-config.yaml)

INGRESS_CONTROLLER_IP=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.spec.clusterIP}')

helm dependency build ../charts/backoffice-bff
helm upgrade --install backoffice-bff ../charts/backoffice-bff \
--namespace yas --create-namespace \
--set backend.ingress.host="backoffice.$DOMAIN" \
--set backend.hostAliases[0].ip="$INGRESS_CONTROLLER_IP" \
--set backend.hostAliases[0].hostnames[0]="identity.$DOMAIN"

helm dependency build ../charts/backoffice-ui
helm upgrade --install backoffice-ui ../charts/backoffice-ui \
--namespace yas --create-namespace

sleep 60

helm dependency build ../charts/storefront-bff
helm upgrade --install storefront-bff ../charts/storefront-bff \
--namespace yas --create-namespace \
--set backend.ingress.host="storefront.$DOMAIN" \
--set backend.hostAliases[0].ip="$INGRESS_CONTROLLER_IP" \
--set backend.hostAliases[0].hostnames[0]="identity.$DOMAIN"

helm dependency build ../charts/storefront-ui
helm upgrade --install storefront-ui ../charts/storefront-ui \
--namespace yas --create-namespace

sleep 60

helm upgrade --install swagger-ui ../charts/swagger-ui \
--namespace yas --create-namespace \
--set ingress.host="api.$DOMAIN"

sleep 20

for chart in {"cart","customer","inventory","media","order","product","search","tax"} ; do
    helm dependency build ../charts/"$chart"
    helm upgrade --install "$chart" ../charts/"$chart" \
    --namespace yas --create-namespace \
    --set backend.ingress.host="api.$DOMAIN" \
    --set backend.hostAliases[0].ip="$INGRESS_CONTROLLER_IP" \
    --set backend.hostAliases[0].hostnames[0]="identity.$DOMAIN"
    sleep 60
done

if [[ "${DEPLOY_SAMPLEDATA:-false}" == "true" ]]; then
    helm dependency build ../charts/sampledata
    helm upgrade --install sampledata ../charts/sampledata \
    --namespace yas --create-namespace \
    --set backend.hostAliases[0].ip="$INGRESS_CONTROLLER_IP" \
    --set backend.hostAliases[0].hostnames[0]="identity.$DOMAIN"
fi
