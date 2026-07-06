#!/usr/bin/env bash
set -euo pipefail
set -x

BOOTSTRAP_ADMIN_USERNAME="$(yq -r '.keycloak.bootstrapAdmin.username' ./cluster-config.yaml)"
BOOTSTRAP_ADMIN_PASSWORD="$(yq -r '.keycloak.bootstrapAdmin.password' ./cluster-config.yaml)"
BACKOFFICE_REDIRECT_URIS="$(yq -o=json -I=0 '.keycloak.backofficeRedirectUrl | map(. + "/*") + ["http://localhost:3000/*", "http://localhost:8087/*"]' ./cluster-config.yaml)"
STOREFRONT_REDIRECT_URIS="$(yq -o=json -I=0 '.keycloak.storefrontRedirectUrl | map(. + "/*") + ["http://localhost:8087/*"]' ./cluster-config.yaml)"

kubectl wait --for=condition=Ready pod/keycloak-0 -n keycloak --timeout=300s

kubectl exec -n keycloak keycloak-0 -- /opt/keycloak/bin/kcadm.sh config credentials \
  --server http://keycloak-service.keycloak.svc.cluster.local \
  --realm master \
  --user "$BOOTSTRAP_ADMIN_USERNAME" \
  --password "$BOOTSTRAP_ADMIN_PASSWORD"

printf '{"redirectUris":%s}\n' "$BACKOFFICE_REDIRECT_URIS" \
  | kubectl exec -i -n keycloak keycloak-0 -- /opt/keycloak/bin/kcadm.sh update \
      clients/26490047-2a91-4938-9324-371523ad1e14 \
      -r Yas \
      -f -

printf '{"redirectUris":%s}\n' "$STOREFRONT_REDIRECT_URIS" \
  | kubectl exec -i -n keycloak keycloak-0 -- /opt/keycloak/bin/kcadm.sh update \
      clients/4f64c142-0545-44bb-9446-2a18b9c9effd \
      -r Yas \
      -f -

kubectl exec -n keycloak keycloak-0 -- /opt/keycloak/bin/kcadm.sh get clients \
  -r Yas \
  -q clientId=storefront-bff \
  --fields clientId,redirectUris

kubectl exec -n keycloak keycloak-0 -- /opt/keycloak/bin/kcadm.sh get clients \
  -r Yas \
  -q clientId=backoffice-bff \
  --fields clientId,redirectUris
