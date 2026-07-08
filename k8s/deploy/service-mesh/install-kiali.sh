#!/usr/bin/env bash
set -euo pipefail

ISTIO_NAMESPACE="${ISTIO_NAMESPACE:-istio-system}"

kubectl get namespace "$ISTIO_NAMESPACE" >/dev/null

helm repo add kiali https://kiali.org/helm-charts
helm repo update

helm upgrade --install kiali-server kiali/kiali-server \
  --namespace "$ISTIO_NAMESPACE" \
  --set auth.strategy=anonymous \
  --set deployment.accessible_namespaces="{**}" \
  --wait \
  --timeout=10m

kubectl rollout status deployment/kiali -n "$ISTIO_NAMESPACE" --timeout=300s
kubectl get pods,svc -n "$ISTIO_NAMESPACE" -l app.kubernetes.io/name=kiali

cat <<'EOF'

Open Kiali from the VM with:
kubectl port-forward -n istio-system svc/kiali 20001:20001 --address 0.0.0.0

Then open:
http://<VM_EXTERNAL_IP>:20001

For safer local-only access, use:
kubectl port-forward -n istio-system svc/kiali 20001:20001
EOF
