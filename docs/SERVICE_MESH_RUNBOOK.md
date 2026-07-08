# Service Mesh Runbook

Tài liệu này dùng cho phần service mesh của Project 02. Repo chọn Istio vì dễ chứng minh được các ý chính trong báo cáo: sidecar proxy, namespace injection, service-to-service traffic và mTLS policy.

## 1. Mục tiêu

Phần này triển khai Istio cho môi trường `yas-dev` và `yas-staging`.

Giữ nguyên:

- Nginx ingress hiện tại.
- Các URL đang dùng: `storefront-dev.yas.local.com`, `backoffice-dev.yas.local.com`, `api-dev.yas.local.com`, `storefront-staging.yas.local.com`, ...
- ArgoCD sync app như cũ.
- Jenkins build/deploy như cũ.

Không bật STRICT mTLS toàn namespace ngay từ đầu vì hệ thống còn nhận traffic từ Nginx ingress không nằm trong mesh và dùng nhiều service nền ngoài mesh như PostgreSQL, Redis, Kafka, Keycloak. Để demo ổn định, repo dùng:

- `PeerAuthentication` mode `PERMISSIVE`: workload mesh vẫn nhận được traffic plain từ ingress/service nền.
- `DestinationRule` mode `ISTIO_MUTUAL` cho `*.namespace.svc.cluster.local`: traffic service-to-service trong namespace có sidecar sẽ dùng Istio mutual TLS.

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

## 4. Test lại sau khi bật mesh

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

## 5. Hình nên chụp cho báo cáo

- `kubectl get pods -n istio-system`.
- `kubectl get ns yas-dev yas-staging --show-labels`.
- Output `./service-mesh/verify-mesh.sh` có container `istio-proxy`.
- `kubectl get peerauthentication,destinationrule -n yas-dev`.
- `kubectl get peerauthentication,destinationrule -n yas-staging`.
- Output `./service-mesh/test-traffic.sh` có header `x-envoy...`.
- ArgoCD UI dạng cây cho app dev/staging.
- Browser mở được storefront/backoffice/swagger sau khi bật mesh.

## 6. Tắt mesh nếu cần rollback

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

## 7. Lưu ý tài nguyên

Istio thêm sidecar `istio-proxy` vào mỗi pod nên cluster sẽ tốn RAM/CPU hơn. Nếu VM đang yếu, chỉ mesh một namespace để demo:

```bash
MESH_NAMESPACES="yas-dev" ./service-mesh/enable-mesh.sh
```

Khi viết báo cáo, ghi rõ nhóm bật mesh ở namespace ứng dụng, còn database/message broker vẫn chạy ngoài mesh để tránh làm hỏng luồng demo chính.
