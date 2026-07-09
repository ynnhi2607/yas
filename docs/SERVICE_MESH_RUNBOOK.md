# Service Mesh Runbook

Tài liệu này dùng cho phần service mesh của Project 02. Repo chọn Istio vì dễ chứng minh được các ý chính trong báo cáo: sidecar proxy, namespace injection, service-to-service traffic và mTLS policy.

## 1. Mục tiêu

Phần này triển khai Istio cho môi trường `yas-dev` và `yas-staging`.

Giữ nguyên:

- Nginx ingress hiện tại.
- Các URL đang dùng: `storefront-dev.yas.local.com`, `backoffice-dev.yas.local.com`, `api-dev.yas.local.com`, `storefront-staging.yas.local.com`, ...
- ArgoCD sync app như cũ.
- Jenkins build/deploy như cũ.

Hướng hiện tại giống repo tham khảo của Thu: public traffic đi qua Istio ingressgateway, workload trong namespace ứng dụng có sidecar, và policy được quản lý bằng GitOps. Repo dùng:

- `PeerAuthentication` mode `STRICT`: service-to-service trong namespace app bắt buộc dùng mTLS.
- `DestinationRule` mode `ISTIO_MUTUAL` cho `*.namespace.svc.cluster.local`: traffic service-to-service trong namespace có sidecar sẽ dùng Istio mutual TLS.
- `DestinationRule` mode `DISABLE` cho các service nền ngoài mesh như PostgreSQL, Redis, Kafka, Keycloak, Elasticsearch.
- `AuthorizationPolicy` allow-list: public workload chỉ nhận traffic từ `istio-ingressgateway`, internal workload chỉ nhận từ service account được phép.

## 2. Cài Istio

Chạy trên GCP VM:

```bash
cd ~/yas/k8s/deploy
chmod +x service-mesh/*.sh
./service-mesh/install-istio.sh
```

Kết quả mong đợi:

```bash
kubectl get pods -n istio-system
```

`istiod` phải ở trạng thái `Running`.

## 3. Bật mesh cho dev và staging

```bash
cd ~/yas/k8s/deploy
MESH_NAMESPACES="yas-dev yas-staging" ./service-mesh/enable-mesh.sh
```

Script sẽ:

- Gắn label `istio-injection=enabled` cho namespace.
- Tạo `PeerAuthentication` mode `PERMISSIVE`.
- Tạo `DestinationRule` mode `ISTIO_MUTUAL` cho service-to-service traffic trong namespace.
- Restart deployment để pod mới có thêm container `istio-proxy`.

Kiểm tra nhanh:

```bash
./service-mesh/verify-mesh.sh
```

Trong phần `Containers`, mỗi pod app nên có dạng:

```text
service-name-xxxxx    service-name istio-proxy
```

Kiểm tra policy:

```bash
kubectl get peerauthentication,destinationrule -n yas-dev
kubectl get peerauthentication,destinationrule -n yas-staging
```

Kết quả mong đợi có:

```text
peerauthentication.security.istio.io/default
destinationrule.networking.istio.io/default-istio-mutual
```

## 4. Bật Gateway/VirtualService kiểu Thu

Để có thêm bằng chứng giống repo tham khảo của Thu, bật Istio Gateway và VirtualService. Khi chỉ test nhanh, có thể port-forward `istio-ingressgateway`. Khi bật STRICT mTLS hoặc muốn mở web qua port 80 như demo chính, phải chuyển public entrypoint từ Nginx ingress sang Istio ingressgateway để tránh tình trạng request lúc đi Nginx, lúc đi Istio.

```bash
cd ~/yas/k8s/deploy
./service-mesh/install-istio.sh
MESH_NAMESPACES="yas-dev yas-staging" ./service-mesh/apply-gateway-routes.sh
./service-mesh/test-istio-gateway.sh
```

Script tạo:

- `Gateway` `yas-gateway`.
- `VirtualService` route storefront/backoffice/api theo host dev và staging.
- Retry policy cho `tax` và `product`.
- Header policy cho Elasticsearch để tránh lỗi client/search khi đi qua mesh.

Kiểm tra tài nguyên:

```bash
kubectl get gateway,virtualservice -n yas-dev
kubectl get gateway,virtualservice -n yas-staging
```

Chuyển public port 80/443 sang Istio giống hướng của Thu:

```bash
cd ~/yas/k8s/deploy
./service-mesh/switch-public-gateway.sh
```

Script sẽ:

- Patch `ingress-nginx-controller` về `ClusterIP`.
- Patch `traefik` về `ClusterIP` nếu cluster còn service LoadBalancer mặc định của k3s.
- Patch `istio-ingressgateway` thành `LoadBalancer`.
- Xóa các pod `svclb-*` cũ của k3s để port 80/443 chỉ bind qua Istio.
- Restart `k3d-yas-cluster-serverlb` nếu đang chạy trên k3d.
- Test nhiều lần qua public port 80 để đảm bảo response luôn có `server: istio-envoy` hoặc `x-envoy-upstream-service-time`.

Chờ traffic public ổn định rồi mới xác nhận response từ các route ổn định như `/`, `/swagger-ui/`, và static asset `/_next/static/...`.

Nếu response lúc `200` lúc `404 text/plain`, nghĩa là public port 80 vẫn đang bị chia giữa Istio và một entrypoint cũ như Nginx/Traefik. Chạy lại script trên và kiểm tra:

```bash
kubectl get svc -n ingress-nginx ingress-nginx-controller
kubectl get svc -n kube-system traefik
kubectl get svc -n istio-system istio-ingressgateway
kubectl get pods -n kube-system | grep svclb
docker ps | grep k3d-yas-cluster-serverlb
```

## 5. Test lại sau khi bật mesh

Kiểm tra ArgoCD:

```bash
kubectl get applications -n argocd
```

Kiểm tra pod:

```bash
kubectl get pods -n yas-dev
kubectl get pods -n yas-staging
```

Test URL từ máy Windows sau khi đã trỏ hosts tới IP VM:

```text
http://storefront-dev.yas.local.com
http://backoffice-dev.yas.local.com
http://api-dev.yas.local.com/swagger-ui/
http://storefront-staging.yas.local.com
http://backoffice-staging.yas.local.com
http://api-staging.yas.local.com/swagger-ui/
```

Nếu cần test bằng curl ngay trên VM:

```bash
./service-mesh/test-traffic.sh
```

Output nên có `HTTP/1.1 200 OK` hoặc redirect hợp lệ, và có header Envoy như:

```text
x-envoy-upstream-service-time
x-envoy-decorator-operation
```

## 6. Bật policy nâng cao kiểu allow-list

Mặc định `enable-mesh.sh` chỉ bật sidecar + mTLS nội bộ để demo ổn định. Nếu cần phần security giống hướng của Thu hơn, bật thêm `AuthorizationPolicy`:

```bash
cd ~/yas/k8s/deploy
MESH_NAMESPACES="yas-dev" ./service-mesh/apply-authorization-policies.sh
./service-mesh/test-traffic.sh
kubectl get authorizationpolicy -n yas-dev
kubectl get pods -n yas-dev
```

Khi dev ổn rồi mới bật staging:

```bash
MESH_NAMESPACES="yas-staging" ./service-mesh/apply-authorization-policies.sh
./service-mesh/test-traffic.sh
kubectl get authorizationpolicy -n yas-staging
```

Các policy này làm theo hướng allow-list:

- Public entrypoints vẫn mở: `storefront-ui`, `backoffice-ui`, `storefront-bff`, `backoffice-bff`, `swagger-ui`.
- Internal service chỉ nhận request từ service account được phép.
- Health endpoint vẫn được allow để Kubernetes/ArgoCD kiểm tra.
- `deny-all-by-default` chặn những request không match allow-list.

Nếu sau khi bật allow-list mà app lỗi, rollback riêng policy:

```bash
kubectl delete authorizationpolicy -n yas-dev -l app.kubernetes.io/part-of=yas-service-mesh
kubectl delete authorizationpolicy -n yas-staging -l app.kubernetes.io/part-of=yas-service-mesh
```

Sau đó test lại URL.

## 7. Bật STRICT mTLS nếu cần giống Thu hơn nữa

Repo tham khảo của Thu dùng `STRICT` mTLS. Với cluster hiện tại, chỉ bật STRICT sau khi Gateway/VirtualService và AuthorizationPolicy đã chạy ổn, vì Nginx ingress không nằm trong mesh có thể không gọi thẳng vào workload được nữa.

Test qua Istio Gateway trước:

```bash
./service-mesh/test-istio-gateway.sh
```

Bật STRICT cho dev trước:

```bash
CONFIRM_STRICT=true MESH_NAMESPACES="yas-dev" ./service-mesh/apply-strict-mtls.sh
./service-mesh/test-istio-gateway.sh
kubectl get peerauthentication,destinationrule -n yas-dev
```

Nếu dev ổn mới bật staging:

```bash
CONFIRM_STRICT=true MESH_NAMESPACES="yas-staging" ./service-mesh/apply-strict-mtls.sh
./service-mesh/test-istio-gateway.sh
kubectl get peerauthentication,destinationrule -n yas-staging
```

Rollback về PERMISSIVE:

```bash
MTLS_MODE=PERMISSIVE MESH_NAMESPACES="yas-dev yas-staging" ./service-mesh/apply-policies.sh
```

## 8. Mở Kiali GUI

Istio không có UI mặc định. Để xem service graph/cây traffic, dùng Kiali:

```bash
cd ~/yas/k8s/deploy
./service-mesh/install-kiali.sh
```

Mở Kiali từ VM:

```bash
kubectl port-forward -n istio-system svc/kiali 20001:20001 --address 0.0.0.0
```

Sau đó mở trên browser:

```text
http://<VM_EXTERNAL_IP>:20001
```

Ví dụ nếu VM đang là `34.87.83.182`:

```text
http://34.87.83.182:20001
```

Lưu ý: nếu mở public port `20001`, nên chỉ allow IP của nhóm trong firewall giống Jenkins, không mở `0.0.0.0/0`.

## 9. Observability: Grafana, Prometheus, Loki, Tempo

Phần observability dùng:

- Prometheus: metrics.
- Grafana: dashboard.
- Loki: log storage.
- Promtail: collect pod logs.
- Tempo: distributed tracing.
- OpenTelemetry Collector: nhận logs/traces và forward sang Loki/Tempo.

Cài stack nền tảng từ repo `yas`:

```bash
cd ~/yas/k8s/deploy
chmod +x ./setup-observability.sh
./setup-observability.sh
```

Sau đó apply GitOps addons giống hướng Thu:

```bash
cd ~/yas-gitops
git pull origin main
./scripts/apply-apps.sh observability
```

Kiểm tra:

```bash
kubectl get applications -n argocd | grep observability
kubectl get pods -n observability
kubectl get svc -n observability | grep -E 'prometheus|grafana|loki|tempo|opentelemetry'
```

Mở Grafana:

```bash
kubectl port-forward -n observability svc/prometheus-grafana 3000:80 --address 0.0.0.0
```

Trên browser:

```text
http://<VM_EXTERNAL_IP>:3000
```

Tài khoản mặc định nếu không override:

```text
admin / admin
```

Trong Grafana nên có datasource:

- `Prometheus`
- `Loki`
- `Tempo`

Tạo traffic để có dữ liệu:

```bash
curl -I -H "Host: storefront-dev.yas.local.com" http://127.0.0.1/
curl -I -H "Host: api-dev.yas.local.com" http://127.0.0.1/swagger-ui/
```

Evidence nên chụp:

- Grafana datasource list có Prometheus/Loki/Tempo.
- Explore Loki query `{namespace="yas-dev"}` hoặc `{namespace="yas-staging"}`.
- Prometheus targets/service monitors.
- Tempo trace/service graph nếu có traffic.
- Kiali graph cho service mesh.

## 10. Hình nên chụp cho báo cáo

- `kubectl get pods -n istio-system`.
- `kubectl get ns yas-dev yas-staging --show-labels`.
- Output `./service-mesh/verify-mesh.sh` có container `istio-proxy`.
- `kubectl get peerauthentication,destinationrule -n yas-dev`.
- `kubectl get peerauthentication,destinationrule -n yas-staging`.
- `kubectl get gateway,virtualservice -n yas-dev`.
- Output `./service-mesh/test-istio-gateway.sh`.
- `kubectl get authorizationpolicy -n yas-dev` nếu đã bật allow-list.
- Kiali Graph view có các service gọi nhau.
- Output `./service-mesh/test-traffic.sh` có header `x-envoy...`.
- ArgoCD UI dạng cây cho app dev/staging.
- Browser mở được storefront/backoffice/swagger sau khi bật mesh.
- `kubectl get pods -n observability`.
- Grafana Explore/Dashboards có Prometheus, Loki, Tempo.

## 11. Tắt mesh nếu cần rollback

Nếu mesh làm cluster nặng hoặc cần quay lại trạng thái cũ:

```bash
cd ~/yas/k8s/deploy
MESH_NAMESPACES="yas-dev yas-staging" ./service-mesh/disable-mesh.sh
```

Lệnh này chỉ tắt sidecar injection và xóa policy trong namespace app. Istio control plane vẫn còn.

Nếu muốn gỡ Istio khỏi cluster:

```bash
cd ~/yas/k8s/deploy
./service-mesh/uninstall-istio.sh
```

## 12. Lưu ý tài nguyên

Istio thêm sidecar `istio-proxy` vào mỗi pod nên cluster sẽ tốn RAM/CPU hơn. Nếu VM đang yếu, chỉ mesh một namespace để demo:

```bash
MESH_NAMESPACES="yas-dev" ./service-mesh/enable-mesh.sh
```

Khi viết báo cáo, ghi rõ nhóm bật mesh ở namespace ứng dụng, còn database/message broker vẫn chạy ngoài mesh để tránh làm hỏng luồng demo chính.
