# CD Jenkins Runbook

Runbook nay dung cho phan bat buoc cua do an CD.

Muc tieu:

- CI build image theo branch va tag bang commit id.
- CD job `developer_build` cho phep developer chon branch cua tung service.
- Service nao khong chon branch dev thi dung image mac dinh `latest`.
- Sau khi deploy, Jenkins co the commit image tag sang GitOps repo de ArgoCD sync.
- Sau khi deploy, Jenkins in ra link cho developer test.
- Co job xoa moi truong deploy.

## 1. Service demo giu lai

Core services:

- product
- cart
- order
- customer
- inventory
- tax
- media
- search
- storefront-bff
- storefront-ui
- backoffice-bff
- backoffice-ui
- swagger-ui
- sampledata

`sampledata` duoc GitOps quan ly trong dev/staging va co PostSync Job tu seed demo data.

## 2. CI image tag

Theo yeu cau do an, image cua branch dev can co tag la commit id cuoi cua branch.

Repo co workflow `.github/workflows/ci-demo-images.yml` build cac service demo va push len Docker Hub theo tag:

```text
<dockerhub-username>/yas-<service>:<short-commit-id>
```

Vi du:

```text
ynnhi2607/yas-tax:a1b2c3d
```

Voi UI service, workflow cung build va push:

```text
ynnhi2607/yas-storefront:<short-commit-id>
ynnhi2607/yas-backoffice:<short-commit-id>
```

`swagger-ui` khong build trong CI vi dang dung public image `swaggerapi/swagger-ui`.

## 3. Jenkins prerequisites

Neu muon lam ca CI va CD tren Jenkins, Jenkins agent can co:

- `git`
- `docker`
- `kubectl`
- `helm`
- kubeconfig tro toi cluster Minikube/K8S
- quyen push Docker Hub

Kiem tra tren Jenkins agent:

```bash
kubectl get nodes
helm version
docker version
```

Repo da co Dockerfile tao Jenkins image co san Docker CLI, kubectl, helm:

```text
jenkins/Dockerfile
```

Build Jenkins image:

```bash
docker build -t jenkins-yas-tools -f jenkins/Dockerfile .
```

Chay Jenkins container de truy cap duoc Docker socket va kubeconfig cua WSL:

```bash
docker stop jenkins-yas || true
docker rm jenkins-yas || true
docker run -d \
  --name jenkins-yas \
  --network host \
  -v jenkins_home:/var/jenkins_home \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v $HOME/.kube:/root/.kube \
  -v $HOME/.minikube:$HOME/.minikube \
  -v $HOME/.minikube:/root/.minikube \
  jenkins-yas-tools
```

Lay password Jenkins lan dau:

```bash
docker exec jenkins-yas cat /var/jenkins_home/secrets/initialAdminPassword
```

## 4. Tao Jenkins job developer_build

Tao Pipeline job ten:

```text
developer_build
```

Cau hinh:

- Definition: Pipeline script from SCM
- SCM: Git
- Repository URL: repo YAS cua nhom
- Branch: branch chua file Jenkinsfile
- Script Path:

Neu chi dung Jenkins cho CD, dung:

```text
Jenkinsfile.build
```

File `docs/jenkins-legacy/Jenkinsfile.full_ci_cd` la pipeline legacy de tham khao. Neu can demo theo de, uu tien dung `Jenkinsfile` cho CI va `Jenkinsfile.build` cho CD.

Tao Jenkins credential:

- Kind: Username with password
- ID: `dockerhub`
- Username: Docker Hub username
- Password: Docker Hub access token

Parameters chinh trong Jenkinsfile:

- `NAMESPACE`: namespace deploy, mac dinh `yas`
- `DOCKERHUB_USERNAME`: Docker Hub username/org
- `DEPLOY_SAMPLEDATA`: chi dung cho developer environment tam thoi; dev/staging dung GitOps auto-seed
- `<SERVICE>_BRANCH`: branch hoac commit cua tung service, vi du `TAX_BRANCH=dev_tax_service`
- `UPDATE_GITOPS`: tao commit update image tag trong repo GitOps
- `PUSH_GITOPS`: push commit GitOps len `origin/main`
- `GITOPS_ENVIRONMENT`: moi truong GitOps can update, `dev` hoac `staging`
- `GITOPS_CREDENTIALS_ID`: Jenkins Secret text credential chua GitHub token, mac dinh `github-token`

## 5. Cach deploy branch cua developer

Vi du developer sua service `tax` tren branch:

```text
dev_tax_service
```

Chay job `developer_build` voi:

```text
TAX_BRANCH=dev_tax_service
UPDATE_GITOPS=true
GITOPS_ENVIRONMENT=dev
PUSH_GITOPS=true
```

Jenkins se tu hieu: service `tax` dung branch `dev_tax_service`, cac service con lai lay theo `main` va dung image mac dinh `latest/main`.

Truoc khi chay voi `PUSH_GITOPS=true`, CI phai build va push image cua branch truoc. Vi du `TAX_BRANCH=dev_tax_service` thi DockerHub can co:

```text
ynnhi2607/yas-tax:<short-commit-id>
```

Neu image chua ton tai, Jenkins se dung lai truoc khi commit GitOps de tranh ArgoCD deploy pod `ErrImagePull`.

Script se:

1. Resolve commit id cuoi cua branch `dev_tax_service`.
2. Deploy `tax` voi image:

```text
ynnhi2607/yas-tax:<short-commit-id>
```

3. Deploy cac service con lai bang image mac dinh `latest`.
4. Commit image tag sang `yas-gitops/environments/dev/services/*.yaml`.
5. Push commit neu `PUSH_GITOPS=true`.
6. In ra URL de test.

Commit GitOps co dang:

```text
developer_build: update dev image tags [build #15]
```

Commit author:

```text
jenkins-bot <jenkins@local>
```

Neu muon chay thu ma khong day len GitHub, de:

```text
PUSH_GITOPS=false
```

## 6. Chay local de test script CD

Tu WSL:

```bash
cd ~/KHTN/devops/yas
TAX_BRANCH=dev_tax_service ./scripts/cd/developer_build.sh
```

Neu can doi Docker Hub username:

```bash
DOCKERHUB_USERNAME=mydockerhub TAX_BRANCH=dev_tax_service ./scripts/cd/developer_build.sh
```

Dev/staging se tu seed data sau khi ArgoCD sync app `sampledata`.
Voi developer environment tam thoi, co the bat `DEPLOY_SAMPLEDATA=true` neu can test seed rieng.

## 7. Link sau khi deploy

Tren VM GCP hien tai, ingress-nginx duoc expose qua port 80 cua k3d load balancer, nen URL khong can port:

```text
http://storefront.yas.local.com
http://backoffice.yas.local.com
http://api.yas.local.com/swagger-ui/
```

Co the in lai link bat ky luc nao bang:

```bash
./scripts/cd/print_demo_urls.sh
```

Neu VM IP thay doi, truyen IP moi vao script:

```bash
HOST_IP=<vm-ip> ./scripts/cd/print_demo_urls.sh
```

Dev va staging cung dung URL khong port:

```text
http://storefront-dev.yas.local.com
http://backoffice-dev.yas.local.com
http://api-dev.yas.local.com/swagger-ui/

http://storefront-staging.yas.local.com
http://backoffice-staging.yas.local.com
http://api-staging.yas.local.com/swagger-ui/
```

Neu can debug bang port-forward local:

```bash
kubectl port-forward -n ingress-nginx svc/ingress-nginx-controller 18080:80 --address 0.0.0.0
```

Khi do co the mo tam bang:

```text
http://storefront.yas.local.com:18080
http://backoffice.yas.local.com:18080
http://api.yas.local.com:18080/swagger-ui/
```

## 8. Tao Jenkins job xoa deploy

Tao Pipeline job ten:

```text
delete_developer_env
```

Cau hinh:

- Definition: Pipeline script from SCM
- SCM: Git
- Repository URL: repo YAS cua nhom
- Script Path:

```text
Jenkinsfile.destroy
```

Parameters:

- `NAMESPACE`: namespace can xoa release, mac dinh `yas`
- `DELETE_NAMESPACE`: co xoa namespace hay khong

Job nay goi:

```bash
./scripts/cd/delete_developer_env.sh
```

## 9. Evidence can chup cho bao cao

Nen chup cac man hinh:

- Docker Hub co image tag commit id, vi du `yas-tax:a1b2c3d`.
- GitHub Actions workflow `CI Demo Images` build/push thanh cong.
- Jenkins job `developer_build` voi parameter `TAX_BRANCH=dev_tax_service`.
- Console log Jenkins dong deploy image dung commit id.
- GitOps repo co commit `jenkins-bot` update image tag neu CD job bat `PUSH_GITOPS=true`.
- `kubectl get pods -n yas`.
- Link `storefront/backoffice/swagger-ui` mo duoc bang domain khong port.
- Jenkins job `delete_developer_env` chay thanh cong.

## 10. Ghi chu hien tai cua demo

Cluster local hien dang toi uu cho demo nen mot so service loi/nang da bi tat:

- payment
- payment-paypal
- promotion
- rating
- recommendation
- webhook
- location
- debezium-connect

Neu muon full stack, can fix rieng cac service nay va tang RAM/CPU cho cluster.
