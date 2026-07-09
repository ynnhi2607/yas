#!/usr/bin/env bash
set -euo pipefail

DOMAIN="${DOMAIN:-yas.local.com}"
GRAFANA_USERNAME="${GRAFANA_USERNAME:-admin}"
GRAFANA_PASSWORD="${GRAFANA_PASSWORD:-admin}"
POSTGRESQL_USERNAME="${POSTGRESQL_USERNAME:-yasadminuser}"
POSTGRESQL_PASSWORD="${POSTGRESQL_PASSWORD:-admin}"

cd "$(dirname "$0")"

helm repo add grafana https://grafana.github.io/helm-charts
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts
helm repo update

kubectl create namespace observability --dry-run=client -o yaml | kubectl apply -f -

helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
  --namespace observability \
  --values ./observability/prometheus.values.yaml \
  --set grafana.ingress.hosts[0]="grafana.${DOMAIN}" \
  --set grafana.adminUser="${GRAFANA_USERNAME}" \
  --set grafana.adminPassword="${GRAFANA_PASSWORD}" \
  --set grafana.grafana\\.ini.database.user="${POSTGRESQL_USERNAME}" \
  --set grafana.grafana\\.ini.database.password="${POSTGRESQL_PASSWORD}"

helm upgrade --install tempo grafana/tempo \
  --namespace observability \
  --values ./observability/tempo.values.yaml

helm upgrade --install opentelemetry-operator open-telemetry/opentelemetry-operator \
  --namespace observability \
  --set admissionWebhooks.certManager.enabled=false \
  --set admissionWebhooks.autoGenerateCert.enabled=true

helm upgrade --install opentelemetry-collector ./observability/opentelemetry \
  --namespace observability

helm upgrade --install grafana-operator oci://ghcr.io/grafana-operator/helm-charts/grafana-operator \
  --version v5.0.2 \
  --namespace observability

helm upgrade --install grafana ./observability/grafana \
  --namespace observability \
  --set hostname="grafana.${DOMAIN}" \
  --set grafana.username="${GRAFANA_USERNAME}" \
  --set grafana.password="${GRAFANA_PASSWORD}" \
  --set postgresql.username="${POSTGRESQL_USERNAME}" \
  --set postgresql.password="${POSTGRESQL_PASSWORD}"

kubectl rollout status deployment/prometheus-grafana -n observability --timeout=300s || true
kubectl get pods,svc -n observability

cat <<EOF

Observability stack installed.

Next, sync GitOps observability addons to install Loki, Promtail, and Grafana datasources:
  cd ~/yas-gitops
  ./scripts/apply-apps.sh observability

Grafana:
  http://grafana.${DOMAIN}

Useful checks:
  kubectl get pods -n observability
  kubectl get svc -n observability | grep -E 'prometheus|grafana|loki|tempo|opentelemetry'
  kubectl port-forward -n observability svc/prometheus-grafana 3000:80 --address 0.0.0.0
EOF
