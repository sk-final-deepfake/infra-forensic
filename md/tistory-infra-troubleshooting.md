# ForenShield AWS 인프라 구축 — 막혔던 점 & 해결 정리 (전체)

> **프로젝트:** ForenShield AI (디지털 포렌식·멀티모달 AI)  
> **환경:** AWS `ap-northeast-2` (서울) · 계정 `877044078824` · CLI 프로필 `forenshield`  
> **작업 방식:** AWS CLI + **Git Bash (Windows)**  
> **도메인:** `forensheildjangdochi.com` (Route 53 Registered domains)

인프라 CLI 구축·검증 중 실제로 겪은 문제와 해결을 **발생 순서·영역별**로 정리했습니다.

---

## 목차

1. [Windows + Git Bash 함정](#1-windows--git-bash-함정)
2. [CLI 변수 · 플래그 · JSON](#2-cli-변수--플래그--json)
3. [EKS Cluster · Node Group](#3-eks-cluster--node-group)
4. [Route 53 · ACM · 도메인 (DNS)](#4-route-53--acm--도메인-dns)
5. [ALB · HTTPS · 503](#5-alb--https--503)
6. [Site-to-Site VPN (On-Prem GPU)](#6-site-to-site-vpn-on-prem-gpu)
7. [RDS · PostgreSQL · SSM 접속](#7-rds--postgresql--ssm-접속)
8. [RabbitMQ (Helm · EBS CSI)](#8-rabbitmq-helm--ebs-csi)
9. [IAM · IRSA](#9-iam--irsa)
10. [CloudWatch Log Group](#10-cloudwatch-log-group)
11. [한 줄 체크리스트](#11-한-줄-체크리스트)

---

## 1. Windows + Git Bash 함정

### ① Path conversion — `/` 로 시작하는 경로가 Windows 경로로 바뀜

**증상**

```text
aws logs create-log-group --log-group-name /aws/eks/${CLUSTER_NAME}/cluster
→ Value 'C:/Program Files/Git/aws/eks/cluster' ... validation error

curl -I https://$DOMAIN/health
→ Could not resolve host ... (또는 이상한 경로)
```

**원인:** Git Bash(MINGW)가 `/aws/...`, `/health` 를 **Unix 경로**로 보고 `C:/Program Files/Git/...` 로 변환.

**해결**

```bash
MSYS_NO_PATHCONV=1 aws logs create-log-group --log-group-name /aws/eks/forenshield/cluster
MSYS_NO_PATHCONV=1 curl -I https://forensheildjangdochi.com//health

# 또는 URL/경로 앞에 / 하나 더
aws logs create-log-group --log-group-name //aws/eks/${CLUSTER_NAME}/cluster
```

---

### ② PowerShell 문법을 Git Bash에서 실행

**증상:** `env:Path += "..."` → `command not found`

**해결**

```bash
export PATH="$PATH:/c/Program Files/Amazon/AWSCLIV2"
export AWS_PROFILE=forenshield
export AWS_REGION=ap-northeast-2
```

---

### ③ `dig` 없음

Windows Git Bash에 `dig` 기본 미설치.

```powershell
nslookup forensheildjangdochi.com 8.8.8.8
nslookup -type=NS forensheildjangdochi.com 8.8.8.8
nslookup -type=CNAME _xxxx.forensheildjangdochi.com 8.8.8.8
```

---

### ④ IAM `file://` JSON 경로 (Windows)

**증상**

```text
Unable to load paramfile file:///tmp/trust-ebs-csi.json: No such file or directory
Unable to load paramfile file://c/Final_Project/...  (드라이브 문자 C: 없음)
MalformedPolicyDocument: invalid Json
```

**원인**

- `/tmp/...` 파일을 안 만들었거나 Git Bash `/tmp` 불일치
- `file://c/Final_Project/...` → AWS CLI가 `c/` 만 경로로 인식
- heredoc `cat > /tmp/x.json` 이 CRLF/BOM 깨짐

**해결:** 프로젝트 폴더에 JSON 저장 + Git Bash 절대 경로

```bash
cd /c/Final_Project/Infra

aws iam create-role \
  --role-name forenshield-ebs-csi-role \
  --assume-role-policy-document file:///c/Final_Project/Infra/tmp/trust-ebs-csi.json

# 또는 상대 경로
--assume-role-policy-document file://tmp/trust-ebs-csi.json
```

PowerShell은 JSON을 **파일로 저장** 후 `file://c:/Final_Project/...` 사용 (인라인 JSON은 `MalformedPolicyDocument` 자주 발생).

---

### ⑤ Git Bash `$` 비밀번호 해석

**증상**

```bash
export DB_PASSWORD=admin123$
# → $ 뒤가 변수로 해석되어 admin123 만 들어감
```

**해결**

```bash
export DB_PASSWORD='admin123$'
export PGPASSWORD='admin123$'
```

---

## 2. CLI 변수 · 플래그 · JSON

### ① `$VPC_ID`, `$PUB_SUBNET_A`, `$CLUSTER_NAME` 등 empty

**증상:** ALB subnet 없음, VPN 실패, log group 이름 이상 등.

**원인:** 터미널 세션 바뀌면 `export` 초기화.

**해결**

```bash
export VPC_ID=vpc-0a074ca9d04307a9c
export CLUSTER_NAME=forenshield
export PUB_SUBNET_A=subnet-0143631cfee4a4ccc
export PUB_SUBNET_B=subnet-0c1056a50d323d9a4
echo "VPC_ID=$VPC_ID"
```

---

### ② EKS — `--version` vs `--kubernetes-version`

**증상:** 클러스터 버전 무시 / CLI 전역 플래그로 해석.

```bash
aws eks create-cluster --name forenshield --kubernetes-version 1.29 ...
```

---

### ③ RDS PostgreSQL 엔진 버전

**증상:** `Cannot find version 16.4 for postgres`

```bash
aws rds describe-db-engine-versions --engine postgres --region ap-northeast-2 \
  --query "DBEngineVersions[?starts_with(EngineVersion,'16.')].EngineVersion" --output table
# 서울 → 16.9 사용
```

---

### ④ Redis Auth Token

**증상:** `Invalid AuthToken` (너무 짧음)

**규칙:** 16~128자, `@` `"` `/` 불가.

```bash
export REDIS_AUTH_TOKEN=$(openssl rand -base64 24 | tr -d '/@+"' | head -c 32)
```

---

### ⑤ JMESPath `--query` 한글 필드명

**증상:** JMESPath parse error

**해결:** `--query` 에 영문 alias 사용 (`--query 'Reservations[*].Instances[*].InstanceId'`)

---

## 3. EKS Cluster · Node Group

### Node Group `CREATE_FAILED`

| # | 원인 | 해결 |
|---|------|------|
| 1 | Private RT에 **NAT 미연결** | NAT GW + Private RT `0.0.0.0/0 → NAT` |
| 2 | **ECR VPC Endpoint SG** | Interface Endpoint SG에 **EKS Cluster SG** TCP 443 인바운드 |

```bash
aws ec2 describe-nat-gateways --filter "Name=tag:Name,Values=forenshield-nat" ...
aws eks describe-nodegroup --cluster-name forenshield --nodegroup-name backend-ng \
  --query 'nodegroup.status' --output text
# → ACTIVE
```

---

## 4. Route 53 · ACM · 도메인 (DNS)

> **가장 시간 많이 쓴 구간.** "Route 53에 레코드 만들었는데 왜 안 되지?"

### 핵심 개념

```text
[도메인 등록]     ← .com 레지스트리 (Route 53 Domains 등)
      ↓
[NS 위임]         ← 인터넷이 어느 DNS 서버를 볼지 결정
      ↓
[Hosted Zone]     ← Route 53 안 레코드 (A, CNAME...)
      ↓
[ACM 검증]        ← 공용 DNS에서 CNAME 조회 → Issued
```

**Hosted Zone 생성 ≠ 인터넷에서 도메인 동작**

---

### 케이스별 정리

| 도메인 | 증상 | 원인 | 해결 |
|--------|------|------|------|
| `forenshield.rookies5.com` | `curl: Could not resolve host` | 상위 `rookies5.com` NS 미위임 | 등록기관에 Route 53 NS 4개 위임 |
| `forenshield.com` | ACM `PENDING_VALIDATION` | 실제 DNS = **Cloudflare**, Route 53 Zone은 외부 미사용 | Cloudflare에 ACM CNAME (DNS only) 또는 NS 변경 |
| `forensheildjangdochi.com` (초기) | 동일 | Hosted Zone만 있고 **도메인 미등록** | Route 53 **Registered domains**에서 구매 |
| `forensheildjangdochi.com` (등록 후) | ACM 계속 Pending | **Hosted Zone 2개** — CNAME을 **옛 Zone**에만 추가 | **등록 시 자동 생성 Zone**에 CNAME+A, 옛 Zone 삭제 |

### Hosted Zone 중복 (최종 도메인)

| Zone | ID | 사용 |
|------|-----|------|
| 등록 시 자동 생성 | `Z091888114TC5UULOEOX5` | ✅ 인터넷 NS |
| 수동 생성 (옛) | `Z07930811QZ35HC32L7VX` | ❌ 삭제 |

```bash
nslookup -type=NS forensheildjangdochi.com 8.8.8.8
nslookup forensheildjangdochi.com 8.8.8.8

aws acm describe-certificate \
  --certificate-arn arn:aws:acm:ap-northeast-2:877044078824:certificate/042b2105-2192-468f-ab45-5c833f4e23aa \
  --region ap-northeast-2 --query Certificate.Status --output text
# → ISSUED
```

**Route 53 Registered domains로 구매하면 NS 위임 자동** — 가장 깔끔.

---

## 5. ALB · HTTPS · 503

### `curl: Could not resolve host`

→ [섹션 4 DNS](#4-route-53--acm--도메인-dns) 참고.

---

### HTTPS 리스너 — ACM `PENDING_VALIDATION`

ACM **Issued** 전에는 HTTPS 443 리스너 생성 불가.

순서: DNS(CNAME) → ACM Issued → `aws elbv2 create-listener --protocol HTTPS ...`

---

### `HTTP/1.1 503 Service Temporarily Unavailable` + `Server: awselb/2.0`

**증상**

```bash
curl -I https://forensheildjangdochi.com/health
# HTTP/1.1 503
```

**원인:** ALB·HTTPS·DNS는 정상. **Target Group에 Healthy 타겯 0개**.

| 확인 | 결과 |
|------|------|
| ALB HTTPS 443 | ✅ |
| Target Group | ✅ 있음 |
| 등록된 타겯 | ❌ 0개 |
| EKS `forenshield` Pod | ❌ Frontend 미배포 |

```text
브라우저 → ALB ✅ → Target Group ❌ (Pod 없음) → 503
```

**해결 (순서)**

1. Frontend Pod 배포 (또는 Ingress + AWS LB Controller)
2. 수동 ALB면 `aws elbv2 register-targets` (frontend-ng EC2, port 80)
3. `/health` 가 200 반환해야 Healthy

```bash
aws elbv2 describe-target-health --target-group-arn $TG_ARN
kubectl get pods -n forenshield
```

---

## 6. Site-to-Site VPN (On-Prem GPU)

| 항목 | 값 |
|------|-----|
| CGW 공인 IP | `58.127.241.84` |
| On-Prem CIDR | `192.168.0.0/24` (**한 IP 아님**) |
| GPU Private IP | `192.168.0.66` |
| VPN ID | `vpn-0b0142909451ce096` |

### 헷갈린 점

| 착각 | 실제 |
|------|------|
| `ONPREM_CIDR=192.168.0.66` | CIDR = `192.168.0.0/24` |
| CGW Available = VPN UP | `VgwTelemetry` 터널별 Status 확인 |
| `127.0.0.1:8080` = GPU | **내 PC**. GPU는 `192.168.0.66` 또는 SSH `-L` |
| 노트북 → GPU 직접 ping | Wi-Fi/유선 격리, 공유기 포워딩 없으면 실패 |

**결과:** 터널 2 UP / 터널 1 DOWN, Private·Data RT VGW 전파 완료.

```bash
aws ec2 describe-vpn-connections --vpn-connection-ids $VPN_ID \
  --query 'VpnConnections[0].VgwTelemetry[*].[OutsideIpAddress,Status]' --output table
```

---

## 7. RDS · PostgreSQL · SSM 접속

### `SHOW DATABASES` / `SHOW TABLES` 에러

```text
ERROR: unrecognized configuration parameter "databases"
```

→ **MySQL 문법**. PostgreSQL은 `\l`, `\dt`, `\d table` 사용.  
상세: [2.PostgreSQL_명령어.md](./2.PostgreSQL_명령어.md)

---

### SSM 콘솔에서 `psql` 아무것도 안 뜸

**원인 1:** 비밀번호 프롬프트 대기 (SSM 브라우저에서 프롬프트 안 보임)

```bash
export PGPASSWORD='비밀번호'
psql -h forenshield-db.chcswakki5dc.ap-northeast-2.rds.amazonaws.com \
  -U forenshield -d forenshield -c "SELECT 1;"
```

**원인 2:** `psql` 미설치

```bash
sudo dnf install -y postgresql15
```

---

### SSM Send-Command `Status: InProgress` + Output 빈값

**원인:** 명령 직후 조회 → 아직 실행 중. 15~60초 후 재조회.

```bash
aws ssm get-command-invocation --command-id $CMD_ID --instance-id $INSTANCE_ID \
  --query '{Status:Status,Output:StandardOutputContent,Error:StandardErrorContent}'
```

**실패 시 흔한 원인:** `connection timed out` → RDS SG 문제 (아래).

---

### RDS `connection timed out` (EKS·SSM 모두)

**원인:** RDS에 **`default` SG**만 붙어 있음. EKS 노드 SG → 5432 미허용.

| 항목 | 잘못된 상태 | 수정 |
|------|-------------|------|
| RDS SG | `default` (자기 자신만) | `forenshield-sg-rds` |
| 인바운드 | 없음 | `eks-cluster-sg-forenshield` → 5432 |

```bash
aws rds modify-db-instance \
  --db-instance-identifier forenshield-db \
  --vpc-security-group-ids sg-06b984afe2c736415 \
  --apply-immediately

aws ec2 authorize-security-group-ingress \
  --group-id sg-06b984afe2c736415 \
  --protocol tcp --port 5432 \
  --source-group sg-072ccb770bbf72e1c
```

**검증**

```bash
kubectl run nc-test --rm -it --restart=Never -n forenshield --image=busybox -- \
  nc -zv forenshield-db.chcswakki5dc.ap-northeast-2.rds.amazonaws.com 5432
# → open
```

---

### RDS 접속 경로 정리

| 방법 | plugin | 용도 |
|------|--------|------|
| SSM 콘솔 + `psql` | ❌ | 셸에서 SQL |
| `kubectl run ... postgres:16` | kubectl만 | 가장 간단 |
| SSM Port Forward + DBeaver | ✅ 1회 | GUI |
| RDS Query Editor v2 | ❌ | 브라우저 SQL |

---

## 8. RabbitMQ (Helm · EBS CSI)

### EBS CSI IAM Role — `MalformedPolicyDocument` / 파일 없음

→ [섹션 1④](#④-iam-file-json-경로-windows)

`tmp/trust-ebs-csi.json` 프로젝트에 두고 `file:///c/Final_Project/Infra/...` 사용.

**이미 Role 있으면** `create-role` 다시 하지 말 것 → `EntityAlreadyExists`.

---

### Pod `Init:ImagePullBackOff` / `ErrImagePull`

```text
failed to pull image "docker.io/bitnami/rabbitmq:3.13.7-debian-12-r2": not found
```

**원인:** Bitnami 2025년부터 `docker.io/bitnami` 무료 태그 제거 → `bitnamilegacy` 로 이동.

**해결:** `tmp/rabbitmq-values.yaml` 에 추가 후 `helm upgrade`:

```yaml
global:
  security:
    allowInsecureImages: true
image:
  repository: bitnamilegacy/rabbitmq
volumePermissions:
  image:
    repository: bitnamilegacy/os-shell
```

```bash
helm upgrade rabbitmq bitnami/rabbitmq -n forenshield --version 14.6.9 \
  -f /c/Final_Project/Infra/tmp/rabbitmq-values.yaml
```

---

### Helm upgrade 했는데도 옛 이미지 pull

**원인:** `-f /tmp/rabbitmq-values.yaml` (파일 없음) 또는 `raabitmq-values.yaml` **오타** → values 미반영.

**확인**

```bash
helm get values rabbitmq -n forenshield | grep -A2 image
kubectl describe pod rabbitmq-0 -n forenshield | grep Image:
```

**해결:** `Infra/tmp/rabbitmq-values.yaml` 경로 명시 + `kubectl delete pod rabbitmq-0 -n forenshield`

---

### `kubectl get pods,pvc,svc -w` 에러

```text
error: you may only specify a single resource type
```

**원인:** `-w`(watch)는 리소스 타입 **하나만**.

```bash
kubectl get pods,pvc,svc -n forenshield -l app.kubernetes.io/name=rabbitmq   # OK (watch 없이)
kubectl get pods -n forenshield -l app.kubernetes.io/name=rabbitmq -w        # watch
```

---

### `kubectl exec rabbitmq-0` → `pods "rabbitmq-0" not found`

**원인:** 직전엔 Running이었으나 Helm release 삭제·Pod Killing 됨.

```bash
helm list -n forenshield
kubectl get pods -n forenshield -l app.kubernetes.io/name=rabbitmq
# 없으면 helm install 재실행
```

Pod 이름은 **`rabbitmq-0`** (StatefulSet). `rabbitmq` 로 exec 하면 안 됨.

---

### Helm `deployed` vs Pod Running

`STATUS: deployed` = 차트만 적용. Pod는 이미지 pull·PVC 등 별도. `kubectl get pods -w` 로 확인.

---

## 9. IAM · IRSA

### `forenshield-ebs-csi-role` — create 후 attach 순서

`attach-role-policy` 성공 후 `create-role` 재시도 → 파일 경로 에러 또는 `EntityAlreadyExists`.

→ Role 이미 있으면 **create 생략**, Add-on만:

```bash
aws eks create-addon --cluster-name forenshield \
  --addon-name aws-ebs-csi-driver \
  --service-account-role-arn arn:aws:iam::877044078824:role/forenshield-ebs-csi-role \
  --resolve-conflicts OVERWRITE
```

### `forenshield-app-s3-role` (Backend/AI S3 IRSA)

CLI 구축 시 Terraform 미적용 → `config/apply-settings.sh` 또는 `config/iam/*.json` 으로 생성.

---

## 10. CloudWatch Log Group

### Path conversion

→ [섹션 1①](#①-path-conversion---로-시작하는-경로가-windows-경로로-바뀜)

### `ResourceAlreadyExistsException`

EKS 클러스터 생성 시 `/aws/eks/forenshield/cluster` **이미 존재**.

```bash
MSYS_NO_PATHCONV=1 aws logs put-retention-policy \
  --log-group-name /aws/eks/forenshield/cluster \
  --retention-in-days 30
```

`create-log-group` 건너뛰기.

---

## 11. 한 줄 체크리스트

| 증상 | 먼저 확인 |
|------|-----------|
| `C:/Program Files/Git/...` in AWS 명령 | `MSYS_NO_PATHCONV=1` 또는 `//` prefix |
| `$VAR` empty | `echo $VAR` · 세션마다 `export` |
| EKS Node `CREATE_FAILED` | NAT + ECR Endpoint SG 443 |
| `Could not resolve host` | `nslookup` 8.8.8.8 · NS 위임 · Zone 중복 |
| ACM `PENDING_VALIDATION` | CNAME이 **공용 DNS**에 있는지 (옛 Zone 아님) |
| ALB `503 awselb` | Target Group healthy 타겯 0 → Pod/타겯 등록 |
| RDS timeout | RDS SG = `forenshield-sg-rds` + EKS SG 5432 |
| `psql` 멈춤 | `PGPASSWORD='...'` · `psql` 설치 |
| `SHOW databases` 에러 | PostgreSQL → `\l` `\dt` |
| RabbitMQ ImagePullBackOff | `bitnamilegacy/rabbitmq` · values 파일 경로 |
| `helm deployed` Pod 안 뜸 | `kubectl describe pod` · 이미지/SG/PVC |
| IAM JSON 에러 | 프로젝트 `tmp/*.json` + `file:///c/...` |
| Log group exists | retention만 설정 |
| 비밀번호 `$` | 작은따옴표 `'admin123$'` |

---

## 마무리 · 다음 단계

| 완료 | 미완 |
|------|------|
| VPC · NAT · SG · RDS · Redis · EKS · VPN | Frontend/Backend Pod 배포 |
| Route 53 도메인 · ACM Issued | ALB Target Healthy |
| RabbitMQ Pod Running | `apply-settings.sh` (Pod 배포 전) |
| RDS SG 수정 · nc 5432 open | HTTPS `/health` 200 |

**다음:** `config/secrets.env` → `bash config/apply-settings.sh` → Backend/Frontend 배포 → ALB 타겯 등록.

---

*관련 문서: [CLI 구축 가이드](./tistory-infra-cli-guide.md) · [Terraform architecture](./2.Terraform%20architecture.md) · [PostgreSQL 명령어](./2.PostgreSQL_명령어.md) · [Settings](./3.settings.md)*
