# Hướng Dẫn Cho Thành Viên Cùng Nhóm

Tài liệu này dùng cho bạn cùng nhóm khi cần code tiếp, chạy Jenkins, kiểm tra GCP/ArgoCD và lấy hình viết báo cáo.

## 1. Nguyên tắc khi dùng chung Jenkins

Được làm:

- Đăng nhập Jenkins bằng account chung của nhóm.
- Bấm `Build Now` hoặc `Build with Parameters`.
- Xem console log, test report, coverage, Sonar/Snyk stage.
- Chạy lại build khi code trên branch đã push lên GitHub.
- Lấy screenshot Jenkins pipeline để viết báo cáo.

Không được làm nếu chưa báo cả nhóm:

- Không sửa, xóa, tạo mới Jenkins credentials.
- Không đổi token DockerHub, Snyk, SonarCloud, GitHub/GitOps.
- Không sửa cấu hình job Jenkins, script path, branch source, webhook.
- Không tắt stage Snyk/Sonar/Coverage chỉ để pipeline pass.
- Không push trực tiếp vào `main`.
- Không xóa namespace, cluster, Docker image, Jenkins job.

Ghi nhớ: token đã lưu trong Jenkins thì pipeline tự dùng được. Người bấm build không cần biết token gốc.

## 2. Clone repo và làm code

```bash
git clone https://github.com/ynnhi2607/yas.git
cd yas
git checkout main
git pull origin main
```

Mỗi task tạo một branch riêng từ `main`:

```bash
git checkout -b ten-task-moi
```

Ví dụ sửa service `tax`:

```bash
git checkout -b fix-tax-demo
```

Sau khi sửa code:

```bash
git add .
git commit -m "Fix tax demo"
git push origin fix-tax-demo
```

Tạo Pull Request vào `main`. Không push trực tiếp vào `main`.

## 3. Chạy Jenkins CI để test service vừa sửa

Dùng job multibranch CI của nhóm, job đang trỏ tới:

```text
Jenkinsfile
```

Cách test:

1. Push branch lên GitHub.
2. Vào Jenkins job multibranch.
3. Chọn branch vừa push.
4. Bấm build nếu Jenkins chưa tự chạy.
5. Theo dõi các stage:
   - Secret scan
   - Test selected services
   - Quality scan
   - Dependency security scan
   - Build and push images

Kết quả mong đợi:

- Chỉ service có thay đổi mới bị test/build lại.
- Ví dụ chỉ sửa `tax/...` thì image được push dạng:

```text
ynnhi2607/yas-tax:<short-commit-id>
```

Nếu sửa file dùng chung như root `pom.xml` hoặc `common-library/...`, Jenkins có thể build nhiều backend service hơn.

## 4. Chạy Jenkins CD để deploy branch test

Dùng job CD developer build, job đang trỏ tới:

```text
Jenkinsfile.build
```

Parameter hay dùng hiện tại:

```text
NAMESPACE=yas
DOCKERHUB_USERNAME=ynnhi2607
<SERVICE>_BRANCH=<branch-cua-service>
DEPLOY_SAMPLEDATA=false
UPDATE_GITOPS=true
GITOPS_ENVIRONMENT=dev
PUSH_GITOPS=false
```

Ví dụ test branch `fix-tax-demo` cho service `tax`:

```text
TAX_BRANCH=fix-tax-demo
```

Kết quả mong đợi:

- Jenkins deploy service `tax` bằng image tag theo commit id của branch.
- Các service còn lại dùng image có sẵn từ `main/latest`.
- Console log có dòng image đã push/deploy.

Nếu muốn Jenkins tạo commit sang repo GitOps giống hình `jenkins-bot committed`, bật:

```text
UPDATE_GITOPS=true
PUSH_GITOPS=true
GITOPS_ENVIRONMENT=dev
```

Jenkins sẽ update các file trong `yas-gitops/environments/dev/services/*.yaml` và commit dạng:

```text
developer_build: update dev image tags [build #<so-build>]
```

Người commit sẽ là:

```text
jenkins-bot <jenkins@local>
```

Nếu chỉ muốn test thử không đẩy lên GitHub, để `PUSH_GITOPS=false`. Khi đó Jenkins chỉ tạo commit local trong workspace.

## 5. Kiểm tra trên GCP VM

SSH vào VM:

```text
Google Cloud Console -> Compute Engine -> VM instances -> yas-devops-vm -> SSH
```

Kiểm tra cluster:

```bash
kubectl get nodes
kubectl get pods -A
```

Kiểm tra ArgoCD và app dev/staging:

```bash
kubectl get applications -n argocd
kubectl get pods -n yas-dev
kubectl get pods -n yas-staging
```

Kết quả mong đợi:

```text
ArgoCD applications: Synced Healthy
Pods service: 1/1 Running
```

Trạng thái setup hiện tại:

```text
VM static IP: 34.87.83.182
Jenkins URL: http://34.87.83.182:8080
Jenkins container: jenkins-yas
Jenkins CD job developer_build: đã test success
```

## 5.1. Kiểm tra service mesh

Phần service mesh dùng Istio và có runbook riêng:

```text
docs/SERVICE_MESH_RUNBOOK.md
```

Lệnh kiểm tra nhanh trên VM:

```bash
cd ~/yas/k8s/deploy
./service-mesh/verify-mesh.sh
```

Khi mesh đã bật đúng, pod trong `yas-dev` và `yas-staging` sẽ có thêm container `istio-proxy`.

## 6. Mở Jenkins cho cả nhóm

Jenkins chạy trên GCP VM nên VM phải đang bật thì cả nhóm mới mở được.

Trước tiên kiểm tra External IP hiện tại của VM trong GCP Console:

```text
Compute Engine -> VM instances -> yas-devops-vm -> External IP
```

Link Jenkins của nhóm:

```text
http://34.87.83.182:8080
```

Nếu VM tắt thì link Jenkins không vào được. Khi bật VM lại, SSH vào VM và kiểm tra:

```bash
k3d cluster start yas-cluster || true
kubectl get nodes
kubectl get pods -n yas-dev
kubectl get pods -n yas-staging
docker ps | grep jenkins-yas || true
```

Nếu Jenkins chưa chạy, bật lại:

```bash
docker start jenkins-yas
```

Nếu lần đầu deploy Jenkins trên VM, chạy:

```bash
cd ~/yas
git checkout main
git pull origin main
chmod +x scripts/gcp/start-jenkins.sh
./scripts/gcp/start-jenkins.sh
```

Script này sẽ:

```text
Build Jenkins image từ jenkins/Dockerfile
Chạy container jenkins-yas ở port 8080
Mount Docker socket để Jenkins build/push image
Mount kubeconfig để Jenkins deploy/check Kubernetes
Đặt restart policy unless-stopped để bật VM lại Jenkins tự chạy lại
```

Nếu Jenkins hỏi mật khẩu lần đầu:

```bash
docker exec jenkins-yas cat /var/jenkins_home/secrets/initialAdminPassword
```

GCP firewall cần mở TCP `8080` để máy thành viên khác truy cập được, nhưng không mở cho toàn internet.

```text
GCP Console -> VPC network -> Firewall -> allow-jenkins-8080 -> Edit
Name: allow-jenkins-8080
Targets: All instances in the network
Source IPv4 ranges: <IP-public-cua-thanh-vien>/32
Protocols and ports: tcp:8080
```

Mỗi thành viên tự lấy IP public tại:

```text
https://whatismyipaddress.com/
```

Ví dụ IP public là `115.77.96.10` thì điền:

```text
115.77.96.10/32
```

Không dùng `0.0.0.0/0` cho Jenkins vì dễ bị bot scan và Google Cloud báo abuse.

Lưu ý khi dùng chung Jenkins:

- Chỉ bấm build, xem log, lấy screenshot.
- Không sửa credentials.
- Không sửa job config.
- Không tắt stage kiểm tra chất lượng/bảo mật.

## 7. Mở UI demo

Windows hosts file cần trỏ về External IP hiện tại của VM GCP. Ví dụ nếu VM đang là `34.87.83.182` thì thêm:

```text
34.87.83.182 storefront.yas.local.com
34.87.83.182 backoffice.yas.local.com
34.87.83.182 api.yas.local.com
34.87.83.182 identity.yas.local.com
34.87.83.182 akhq.yas.local.com
34.87.83.182 pgadmin.yas.local.com
34.87.83.182 kibana.yas.local.com
34.87.83.182 storefront-dev.yas.local.com
34.87.83.182 backoffice-dev.yas.local.com
34.87.83.182 api-dev.yas.local.com
34.87.83.182 storefront-staging.yas.local.com
34.87.83.182 backoffice-staging.yas.local.com
34.87.83.182 api-staging.yas.local.com
```

Nếu VM dùng IP tạm thời và IP đổi sau khi bật lại, phải sửa các dòng trên sang IP mới.
Hiện tại IP `34.87.83.182` đã được reserve thành static IP `yas-devops-static-ip`, nên tắt/bật VM không cần đổi hosts nữa.

Link:

```text
http://storefront.yas.local.com
http://backoffice.yas.local.com
http://api.yas.local.com/swagger-ui/
http://identity.yas.local.com/admin
```

Các link demo này cũng cần VM đang bật. Nếu VM tắt thì web YAS, Jenkins và ArgoCD đều không vào được.

Firewall web cũng chỉ nên allow IP nhóm:

```text
default-allow-http: tcp:80, Source IPv4 ranges = IP từng thành viên dạng /32
default-allow-https: tcp:443, Source IPv4 ranges = IP từng thành viên dạng /32
```

## 8. Mở ArgoCD UI

Trên VM, chạy:

```bash
kubectl port-forward -n argocd svc/argocd-server 8081:443 --address 0.0.0.0
```

Mở trên browser:

```text
https://34.87.83.182:8081
```

Dùng port `8081` cho ArgoCD để không đụng port `8080` của Jenkins.

Lấy password:

```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
echo
```

Đăng nhập:

```text
username: admin
password: kết quả lệnh trên
```

Vào từng application để xem cây resource ArgoCD và chụp hình cho báo cáo.

Nếu muốn mở ArgoCD từ máy thành viên khác, GCP firewall cũng cần mở TCP `8081`, và source cũng chỉ nên là IP từng thành viên dạng `/32`.

## 9. SonarCloud, Snyk, DockerHub

- Jenkins đã có token để chạy pipeline, không cần tạo `.env` cho Jenkins.
- Nếu cần xem dashboard SonarCloud/Snyk thì cần được invite vào organization/project trên từng dịch vụ.
- DockerHub image public thì có thể xem/pull trực tiếp. Nếu cần push trực tiếp thì phải được add vào DockerHub organization/team hoặc dùng Jenkins.
- Không commit `.env` có token lên GitHub.

Nếu cần chạy local có token riêng, chỉ tạo file local `.env` và đảm bảo `.env` nằm trong `.gitignore`.

## 10. Ảnh cần chụp để viết báo cáo

- GitHub PR vào `main`, có reviewer và check pass.
- Jenkins CI pipeline branch service, thấy chỉ build service thay đổi.
- Jenkins console log image tag theo commit id.
- SonarCloud project dashboard.
- Snyk scan stage hoặc Snyk dashboard.
- DockerHub repository có image tag mới.
- GitOps repo có commit `jenkins-bot` update image tag nếu CD job bật `PUSH_GITOPS=true`.
- ArgoCD UI: app `Synced Healthy` và cây resource.
- `kubectl get applications -n argocd`.
- `kubectl get pods -n yas-dev` và `kubectl get pods -n yas-staging`.
- Storefront/Backoffice/Swagger UI trên GCP.

## 11. Khi gặp lỗi

- Nếu Jenkins fail ở test/coverage/Snyk/Sonar: đọc log và sửa code/config đúng nguyên nhân, không tắt gate.
- Nếu pod không `Running`: chạy `kubectl logs` và `kubectl describe pod`, không xóa cluster.
- Nếu login Keycloak/redirect lỗi: báo người phụ trách, không sửa Keycloak client bằng tay nếu chưa thống nhất.
- Nếu cần restart VM/cluster: báo cả nhóm trước.
