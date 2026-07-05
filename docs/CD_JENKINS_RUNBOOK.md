# CD Jenkins Runbook

Runbook nay dung cho phan bat buoc cua do an CD.

Muc tieu:

- CI build image theo branch va tag bang commit id.
- CD job `developer_build` cho phep developer chon branch cua tung service.
- Service nao khong chon branch dev thi dung image mac dinh `latest`.
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

`sampledata` chi chay khi can seed data, sau do co the scale ve 0.

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

File `jenkins/Jenkinsfile.full_ci_cd` la pipeline legacy. Neu can demo theo de, uu tien dung `Jenkinsfile` cho CI va `Jenkinsfile.build` cho CD.

Tao Jenkins credential:

- Kind: Username with password
- ID: `dockerhub`
- Username: Docker Hub username
- Password: Docker Hub access token

Parameters chinh trong Jenkinsfile:

- `NAMESPACE`: namespace deploy, mac dinh `yas`
- `DOCKERHUB_USERNAME`: Docker Hub username/org
- `DEPLOY_SAMPLEDATA`: bat khi can seed data
- `BASE_BRANCH`: branch mac dinh cho tat ca service, thuong la `main`
- `TARGET_SERVICE`: service can build lai, vi du `tax`
- `TARGET_BRANCH`: branch cua service can test, vi du `dev_tax_service`
- `BUILD_BASE_IMAGES`: co build lai cac service o `BASE_BRANCH` hay khong, thuong de `false`
- `PUSH_LATEST_FOR_BASE`: co tag image base thanh `latest` hay khong, thuong de `false`

## 5. Cach deploy branch cua developer

Vi du developer sua service `tax` tren branch:

```text
dev_tax_service
```

Chay job `developer_build` voi:

```text
BASE_BRANCH=main
TARGET_SERVICE=tax
TARGET_BRANCH=dev_tax_service
```

Jenkins se tu hieu: chi build lai service `tax` tu branch `dev_tax_service`, cac service con lai lay theo `BASE_BRANCH=main` va dung image mac dinh `latest/main`.

Script se:

1. Resolve commit id cuoi cua branch `dev_tax_service`.
2. Deploy `tax` voi image:

```text
ynnhi2607/yas-tax:<short-commit-id>
```

3. Deploy cac service con lai bang image mac dinh `latest`.
4. In ra URL de test.

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

Neu can seed data:

```bash
DEPLOY_SAMPLEDATA=true ./scripts/cd/developer_build.sh
```

Sau khi sampledata chay xong, tat lai:

```bash
kubectl scale deployment sampledata -n yas --replicas=0
```

## 7. Link sau khi deploy

Neu ingress-nginx expose bang NodePort, Jenkins se in:

```text
http://storefront.yas.local.com:<nodeport>
http://backoffice.yas.local.com:<nodeport>
http://api.yas.local.com:<nodeport>/swagger-ui/
```

Co the in lai link bat ky luc nao bang:

```bash
./scripts/cd/print_demo_urls.sh
```

Tren cluster hien tai, `ingress-nginx-controller` dang la `NodePort`. Lay port bang:

```bash
kubectl get svc -n ingress-nginx ingress-nginx-controller
```

Neu chay local bang port-forward:

```bash
kubectl port-forward -n ingress-nginx svc/ingress-nginx-controller 18080:80 --address 0.0.0.0
```

Mo:

```text
http://storefront.yas.local.com
http://backoffice.yas.local.com
http://api.yas.local.com/swagger-ui/
```

Neu chua co Windows `netsh portproxy`, mo tam bang:

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
- Jenkins job `developer_build` voi parameter `BASE_BRANCH=main`, `TARGET_SERVICE=tax`, `TARGET_BRANCH=dev_tax_service`.
- Console log Jenkins dong deploy image dung commit id.
- `kubectl get pods -n yas`.
- `kubectl get svc -n ingress-nginx ingress-nginx-controller` hien `NodePort`.
- Link `storefront/backoffice/swagger-ui` mo duoc bang `domain:nodeport`.
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
