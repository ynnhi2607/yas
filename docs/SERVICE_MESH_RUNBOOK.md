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
- Patch `istio-ingressgateway` thành `LoadBalancer`.
- Xóa các pod `svclb-*` cũ của k3s để port 80/443 chỉ bind qua Istio.
- Test nhiều lần để đảm bảo response luôn có `server: istio-envoy` hoặc `x-envoy-upstream-service-time`.

Nếu response lúc `200` lúc `404 text/plain`, nghĩa là port 80 vẫn đang bị chia giữa Nginx và Istio. Chạy lại script trên và kiểm tra:

```bash
kubectl get svc -n ingress-nginx ingress-nginx-controller
kubectl get svc -n istio-system istio-ingressgateway
kubectl get pods -n kube-system | grep svclb
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

## 9. Hình nên chụp cho báo cáo

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

## 10. Tắt mesh nếu cần rollback

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

## 11. Lưu ý tài nguyên

Istio thêm sidecar `istio-proxy` vào mỗi pod nên cluster sẽ tốn RAM/CPU hơn. Nếu VM đang yếu, chỉ mesh một namespace để demo:

```bash
MESH_NAMESPACES="yas-dev" ./service-mesh/enable-mesh.sh
```

Khi viết báo cáo, ghi rõ nhóm bật mesh ở namespace ứng dụng, còn database/message broker vẫn chạy ngoài mesh để tránh làm hỏng luồng demo chính.
