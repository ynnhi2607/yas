# YAS Demo Runbook

File nay ghi lai cach bat/tat moi lan can demo YAS tren Minikube.

## Link demo

- Storefront: http://storefront.yas.local.com
- Backoffice: http://backoffice.yas.local.com
- Swagger UI: http://api.yas.local.com/swagger-ui/
- Keycloak admin: http://identity.yas.local.com/admin
- pgAdmin: http://pgadmin.yas.local.com
- AKHQ: http://akhq.yas.local.com
- Kibana: http://kibana.yas.local.com

Backoffice can user co role `ADMIN`.

- Keycloak master admin: `admin / admin`
- Realm `Yas` admin test: `admin / admin`
- User `nhi` da duoc gan realm role `ADMIN`

## Mo lai sau khi bat may

Chay trong WSL tai thu muc repo:

```bash
cd ~/KHTN/devops/yas
minikube start
kubectl get pods -A
```

Doi cac pod quan trong ve `Running` hoac `Completed`.

Kiem tra nhanh namespace chinh:

```bash
kubectl get pods -n yas
kubectl get pods -n keycloak
kubectl get pods -n kafka
kubectl get pods -n elasticsearch
```

## Bat duong vao tu browser Windows

Theo yeu cau do an, co the dung NodePort cua ingress-nginx:

```bash
kubectl get svc -n ingress-nginx ingress-nginx-controller
./scripts/cd/print_demo_urls.sh
```

Neu dung NodePort, Windows hosts nen tro toi Minikube IP, vi du:

```text
192.168.49.2 storefront.yas.local.com
192.168.49.2 backoffice.yas.local.com
192.168.49.2 api.yas.local.com
192.168.49.2 identity.yas.local.com
```

Mo bang dang:

```text
http://storefront.yas.local.com:<nodeport>
http://backoffice.yas.local.com:<nodeport>
http://api.yas.local.com:<nodeport>/swagger-ui/
```

Neu Windows da co `netsh portproxy` port 80 -> 18080, chi can mo port-forward:

```bash
kubectl port-forward -n ingress-nginx svc/ingress-nginx-controller 18080:80 --address 0.0.0.0
```

Lenh nay phai de chay trong terminal. Khi terminal nay dong thi link demo se khong vao duoc nua.

Neu bao `address already in use`, nghia la port-forward cu van dang chay. Thu mo link demo luon, hoac tim terminal cu roi dung lai bang `Ctrl+C`.

Neu chua cau hinh `netsh portproxy`, co the mo tam bang port:

- http://storefront.yas.local.com:18080
- http://backoffice.yas.local.com:18080
- http://api.yas.local.com:18080/swagger-ui/

Luu y: OAuth/Keycloak de on dinh nhat khi dung link khong co port, tuc la nen co `netsh portproxy`.

## Windows hosts file

File Windows:

```text
C:\Windows\System32\drivers\etc\hosts
```

Nen co cac dong nay neu dung `netsh portproxy`:

```text
127.0.0.1 storefront.yas.local.com
127.0.0.1 backoffice.yas.local.com
127.0.0.1 api.yas.local.com
127.0.0.1 identity.yas.local.com
127.0.0.1 akhq.yas.local.com
127.0.0.1 pgadmin.yas.local.com
127.0.0.1 kibana.yas.local.com
```

Neu muon dung truc tiep Minikube IP thay vi portproxy, thay `127.0.0.1` bang ket qua:

```bash
minikube ip
```

Tren may hien tai Minikube IP thuong la `192.168.49.2`, nhung IP co the doi sau khi tao lai cluster.

## Tao lai Windows portproxy neu mat

Chay PowerShell bang Run as Administrator:

```powershell
netsh interface portproxy add v4tov4 listenaddress=127.0.0.1 listenport=80 connectaddress=127.0.0.1 connectport=18080
netsh interface portproxy show all
```

Sau do trong WSL van can chay:

```bash
kubectl port-forward -n ingress-nginx svc/ingress-nginx-controller 18080:80 --address 0.0.0.0
```

## Test nhanh

```bash
kubectl get pods -n yas
```

Cac service demo nen `1/1 Running`:

- storefront-ui
- storefront-bff
- backoffice-ui
- backoffice-bff
- swagger-ui
- product
- cart
- order
- customer
- inventory
- media
- tax
- search

Test Swagger API docs:

```bash
curl -H "Host: api.yas.local.com" http://127.0.0.1:18080/media/v3/api-docs
```

Neu tra JSON co `"openapi":"3.1.0"` la OK.

## Cach tat truoc khi shutdown may

1. Dung port-forward bang `Ctrl+C` trong terminal dang chay lenh nay:

```bash
kubectl port-forward -n ingress-nginx svc/ingress-nginx-controller 18080:80 --address 0.0.0.0
```

2. Tam dung Minikube de tiet kiem RAM/CPU:

```bash
minikube stop
```

Sau do co the shutdown Windows/WSL binh thuong.

Khong can deploy lai sau moi lan tat may. Lan sau chi can `minikube start` va bat lai port-forward.

## Khi nao moi can deploy lai

Chi deploy lai khi:

- Chay `minikube delete`
- Tao cluster moi
- Sua Helm chart/config va muon apply update
- Xoa namespace/release

Neu chi `minikube stop` roi `minikube start`, du lieu va deployment van con.

## Lenh deploy lai rieng cac phan hay dung

Deploy lai Swagger UI:

```bash
helm upgrade --install swagger-ui k8s/charts/swagger-ui --namespace yas
```

Deploy lai YAS configuration:

```bash
helm upgrade --install yas-configuration k8s/charts/yas-configuration --namespace yas
kubectl rollout restart deployment/storefront-bff deployment/backoffice-bff -n yas
```

Deploy lai Kafka chart:

```bash
helm upgrade --install kafka-cluster k8s/deploy/kafka/kafka-cluster --namespace kafka
```

## CD Jenkins cho do an

Phan CD/Jenkins nam trong file:

```text
docs/CD_JENKINS_RUNBOOK.md
```

File quan trong:

```text
jenkins/Jenkinsfile.developer_build
jenkins/Jenkinsfile.delete_developer_env
scripts/cd/developer_build.sh
scripts/cd/delete_developer_env.sh
```

Chay thu CD local:

```bash
TAX_BRANCH=dev_tax_service ./scripts/cd/developer_build.sh
```

Xoa deploy:

```bash
./scripts/cd/delete_developer_env.sh
```

## Loi thuong gap

`ERR_CONNECTION_REFUSED` hoac `ERR_CONNECTION_TIMED_OUT`:

- Kiem tra port-forward co dang chay khong.
- Kiem tra Windows hosts file dung IP/chua.
- Kiem tra `minikube start` da chay chua.

`address already in use` khi port-forward:

- Port `18080` dang co process khac dung.
- Thu mo link demo xem co san chua.
- Neu can, dung terminal port-forward cu bang `Ctrl+C`.

Backoffice `403 Access Denied`:

- Login user co realm role `ADMIN`.
- Thu incognito hoac clear site data cua `backoffice.yas.local.com` va `identity.yas.local.com`.

Swagger UI bao invalid OpenAPI version:

- Dam bao image Swagger UI dang la `swaggerapi/swagger-ui:v5.17.14`.
- Hard refresh `Ctrl+F5`.
