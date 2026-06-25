# ForenShield 인프라 핸드북

> **매일 쓰는 운영 가이드** — 아키텍처, 리소스, 출퇴근, 헬스체크, 장애 대응.  
> 배포 따라하기: [deployment.md](./deployment.md) · 블록체인: [fabric.md](./fabric.md)

---

## 1. 아키텍처

```text
[브라우저] → ALB → [EKS: frontend + backend + ai-fastapi + rabbitmq]
                      │    ├─ RDS · Redis · S3
                      │    ├─ RabbitMQ → AI 분석
                      │    └─ HTTP → [EC2 Fabric Gateway :8088] → Hyperledger Fabric
                      └── VPN → [On-Prem GPU :8000]
```

| 구분 | 위치 |
|------|------|
| 웹/API | EKS `forenshield`, Argo CD GitOps |
| 블록체인 | EC2 `forenshield-fabric-poc` |
| AI | EKS `ai-fastapi` + On-Prem GPU |

---

## 2. 현재 리소스

| 항목 | 값 |
|------|-----|
| Region / Account | `ap-northeast-2` · `877044078824` |
| EKS | `forenshield` / namespace `forenshield` |
| 도메인 | `https://forensheildjangdochi.com` |
| RDS | `forenshield-db.chcswakki5dc.ap-northeast-2.rds.amazonaws.com:5432` |
| S3 | `forenshield-evidence-877044078824` |
| Fabric EC2 | `i-08f10733c96e387fc` · **`10.0.10.224`** |
| Fabric SG | `sg-0992309b24773bb7f` (8088 ← cluster SG `sg-072ccb770bbf72e1c`) |

블록체인 ConfigMap (`config/k8s/app-config.yaml`):

```yaml
BLOCKCHAIN_ANCHOR_ENABLED: "true"
BLOCKCHAIN_ANCHOR_MODE: "http"
BLOCKCHAIN_ANCHOR_URL: "http://10.0.10.224:8088/api/v1/anchor"
```

**검증 완료:** EVD-74 `ANCHORED`

---

## 3. 공통 설정 (매 터미널)

**Git Bash:**

```bash
export PATH="$PATH:/c/Program Files/Amazon/AWSCLIV2"
export AWS_PROFILE=forenshield
export AWS_REGION=ap-northeast-2
export CLUSTER_NAME=forenshield
aws sts get-caller-identity
aws eks update-kubeconfig --name forenshield --region ap-northeast-2
```

**PowerShell:**

```powershell
$env:Path += ";C:\Program Files\Amazon\AWSCLIV2"
$env:AWS_PROFILE = "forenshield"
$env:AWS_REGION = "ap-northeast-2"
$env:CLUSTER_NAME = "forenshield"
aws sts get-caller-identity
```

---

## 4. 헬스체크

```bash
kubectl get pods -n forenshield
kubectl exec -n forenshield deploy/backend -- env | grep BLOCKCHAIN
kubectl exec -n forenshield deploy/backend -- curl -sf http://10.0.10.224:8088/health
curl.exe -I https://forensheildjangdochi.com/
```

EC2 (SSM): `curl -s http://localhost:8088/health` · `docker ps | grep peer`

---

## 5. 출근 (Startup)

> **순서:** RDS → EKS 노드 → RabbitMQ Ready → backend → Fabric EC2

### 5.1 RDS

```powershell
aws rds start-db-instance --db-instance-identifier forenshield-db
aws rds wait db-instance-available --db-instance-identifier forenshield-db
```

### 5.2 EKS Node Group

```powershell
aws eks update-nodegroup-config --cluster-name forenshield --nodegroup-name frontend-ng   --scaling-config minSize=1,desiredSize=1,maxSize=2
aws eks update-nodegroup-config --cluster-name forenshield --nodegroup-name backend-ng    --scaling-config minSize=1,desiredSize=2,maxSize=4
aws eks update-nodegroup-config --cluster-name forenshield --nodegroup-name ai-fastapi-ng --scaling-config minSize=1,desiredSize=1,maxSize=2
aws eks update-kubeconfig --name forenshield --region ap-northeast-2
kubectl get nodes -w
kubectl get pods -n forenshield
```

| Node Group | min | desired | max |
|------------|-----|---------|-----|
| frontend-ng | 1 | 1 | 2 |
| backend-ng | 1 | 2 | 4 |
| ai-fastapi-ng | 1 | 1 | 2 |

### 5.3 Fabric EC2

1. EC2 **start** (terminate 금지)
2. Private IP 확인 — 변경 시 `app-config.yaml` 갱신 + Argo sync
3. SSM → Fabric + Gateway:

```bash
cd ~/forenshield-fabric-runtime/fabric-samples/test-network
./network.sh up createChannel -c forenshield-evidence -ca
./network.sh deployCC -ccn anchor -ccp ~/forenshield-infra/fabric/chaincode/anchor -ccl go -c forenshield-evidence
cd ~/forenshield-infra/fabric && bash scripts/start-gateway.sh
```

> `network.sh down`은 ledger 삭제 → DB `ANCHORED`와 불일치. 퇴근 시 **EC2 stop**만.

---

## 6. 퇴근 (Shutdown)

> **순서:** EKS 노드 0 → RDS stop → Fabric Gateway 종료 → EC2 stop

### 6.1 EKS

```powershell
foreach ($ng in @("frontend-ng", "backend-ng", "ai-fastapi-ng")) {
  aws eks update-nodegroup-config --cluster-name forenshield --nodegroup-name $ng `
    --scaling-config minSize=0,desiredSize=0,maxSize=4
}
aws rds stop-db-instance --db-instance-identifier forenshield-db
```

**유지:** VPC · EKS 클러스터 · S3 · ECR · Argo CD 매니페스트  
**끄지 않음:** EKS control plane · NAT · ElastiCache (Stop API 없음)

### 6.2 Fabric EC2

```bash
pkill -f "node.*gateway" || true
# network.sh down 하지 말 것
```

### 6.3 절대 하지 말 것

| 명령 | 결과 |
|------|------|
| `delete-db-instance` | DB 데이터 삭제 |
| `delete-cluster` | EKS 전체 삭제 |
| `s3 rb --force` | 증거 파일 삭제 |

---

## 7. 배포 흐름

```text
코드 push → GitHub Actions → ECR → infra-forensic (image tag) → Argo CD → EKS
```

롤백: infra-forensic에서 image tag revert → push → Argo sync. 상세: [deployment.md § CI/CD](./deployment.md#부록-cicd--argocd)

---

## 8. 트러블슈팅

| 증상 | 원인 | 해결 |
|------|------|------|
| backend CrashLoop | RabbitMQ 미준비 | RDS→노드→MQ→backend 순서 |
| Gateway timeout | SG 소스 오류 | fabric SG 8088 ← **cluster SG** `sg-072ccb770bbf72e1c` |
| `evidenceId required` | 구버전 backend | `0c22475` 이상 배포 |
| `CLUSTER_NAME is required` | env 미설정 | `export CLUSTER_NAME=forenshield` |
| 앵커 FAILED | Fabric/Gateway down | EC2 up + deployCC + gateway |
| DB vs ledger 불일치 | `network.sh down` | down 금지, EC2 stop |
| IP 변경 후 앵커 실패 | EC2 재시작 | IP 확인 → ConfigMap |
| Argo OutOfSync | infra 미반영 | Git push + Refresh |
| `InvalidClientTokenId` | wrong profile | `AWS_PROFILE=forenshield` |
| Pod Pending | 노드 부족 | nodes Ready 대기 |
| Backend CrashLoop (RDS) | RDS stopped | RDS available 후 rollout restart |

```powershell
kubectl rollout restart deployment/backend -n forenshield
kubectl rollout restart deployment/frontend -n forenshield
```

---

## 9. 체크리스트

**퇴근:** Node 0 · RDS stopped · Fabric EC2 stop  
**출근:** RDS available · Node Ready 4 · Pod Running · 사이트/health OK · Gateway health 200

---

*마지막 업데이트: 2026-06-24*
