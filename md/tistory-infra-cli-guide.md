# ForenShield AWS 인프라 — CLI로 뭘 왜 만들었는지 (콘솔 대응표)

> **프로젝트:** ForenShield AI  
> **리전:** `ap-northeast-2` (서울)  
> **구축 방식:** AWS CLI (Git Bash / PowerShell)  
> **계정:** `877044078824` · 프로필 `forenshield`  
> **도메인:** `forensheildjangdochi.com`

티스토리용으로 **Step 1~11** 까지 "이게 뭐고, 왜 필요하고, CLI로 뭘 쳤고, 콘솔에서는 어디서 하냐" 를 한 장씩 정리했습니다.

---

## 전체 구축 순서

```text
[1] IAM
 └─ [2] VPC / Subnet / IGW
      └─ [3] NAT Gateway
           └─ [4] Security Group
                └─ [5] VPC Endpoint (S3, ECR)
                     └─ [6] S3 버킷
                          └─ [7] RDS + ElastiCache
                               └─ [8] ECR 레포지토리
                                    └─ [9] Site-to-Site VPN
                                         └─ [10] EKS Cluster
                                              └─ [11] EC2 Node Groups
                                                   └─ [12] Route 53      
                                                        └─ [13] ALB
                                                             └─ [14] CloudWatch
```

**원칙:** 위에서 아래로. 상위가 없으면 하위가 안 됩니다.

---

## 공통 설정 (모든 Step 전 1회)

### 뭘 하는가

AWS CLI가 **어느 계정·어느 리전**에 명령을 보낼지 고정합니다.

### CLI

```bash
export PATH="$PATH:/c/Program Files/Amazon/AWSCLIV2"
export AWS_PROFILE=forenshield
export AWS_REGION=ap-northeast-2
export PROJECT=forenshield

export ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export AZ_A=$(aws ec2 describe-availability-zones --query 'AvailabilityZones[0].ZoneName' --output text)
export AZ_B=$(aws ec2 describe-availability-zones --query 'AvailabilityZones[1].ZoneName' --output text)
```

### 콘솔

- 우측 상단 **리전:** Asia Pacific (Seoul)
- IAM → Users → 본인 사용자 → Access Key 발급
- `aws configure --profile forenshield` 로 로컬에 저장

---

## Step 1 — IAM

### 뭔가요?

AWS 리소스가 **누구 권한으로** 동작할지 정하는 역할(Role)·정책(Policy)입니다.  
EKS는 "클러스터용 Role", "워커 노드용 Role"이 **필수**입니다.

### 왜 하나요?

| Role | 누가 씀 | 왜 |
|------|---------|-----|
| `forenshield-eks-cluster-role` | EKS Control Plane | 클러스터 관리 AWS API 호출 |
| `forenshield-eks-node-role` | EC2 Worker Node | Pod가 ECR pull, SSM, CNI 등 사용 |

### CLI로 한 것

```bash
# EKS Cluster Role
aws iam create-role --role-name forenshield-eks-cluster-role \
  --assume-role-policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"eks.amazonaws.com"},"Action":"sts:AssumeRole"}]}'
aws iam attach-role-policy --role-name forenshield-eks-cluster-role \
  --policy-arn arn:aws:iam::aws:policy/AmazonEKSClusterPolicy

# EKS Node Role
aws iam create-role --role-name forenshield-eks-node-role \
  --assume-role-policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"ec2.amazonaws.com"},"Action":"sts:AssumeRole"}]}'
aws iam attach-role-policy --role-name forenshield-eks-node-role --policy-arn arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy
aws iam attach-role-policy --role-name forenshield-eks-node-role --policy-arn arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy
aws iam attach-role-policy --role-name forenshield-eks-node-role --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly
aws iam attach-role-policy --role-name forenshield-eks-node-role --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore
```

### 콘솔

**IAM** → **Roles** → **Create role**
- Trusted entity: `EKS` / `EC2`
- Policy: 위 AWS 관리형 정책 attach

### 검증

```bash
aws iam get-role --role-name forenshield-eks-cluster-role --query 'Role.Arn' --output text
```

---

## Step 2 — VPC / Subnet / Internet Gateway

### 뭔가요?

ForenShield 전용 **격리된 네트워크**입니다. 서브넷 종류별로 역할을 나눕니다.

| 리소스 | CIDR 예시 | 용도 |
|--------|-----------|------|
| VPC | `10.0.0.0/16` | 전체 네트워크 |
| Public Subnet ×2 | `10.0.1.0/24`, `10.0.2.0/24` | ALB, NAT Gateway |
| Private Subnet ×2 | `10.0.10.0/24`, `10.0.11.0/24` | EKS Worker (Frontend/Backend/AI) |
| Data Subnet ×2 | `10.0.20.0/24`, `10.0.21.0/24` | RDS, Redis (인터넷 차단) |
| Internet Gateway | — | Public ↔ 인터넷 |

### 왜 하나요?

- 웹(ALB)만 인터넷에 노출
- DB·캐시는 Private/Data에 격리
- Multi-AZ(2a, 2b)로 장애 대비

### CLI로 한 것 (요약)

```bash
export VPC_ID=$(aws ec2 create-vpc --cidr-block 10.0.0.0/16 \
  --tag-specifications 'ResourceType=vpc,Tags=[{Key=Name,Value=forenshield-vpc}]' \
  --query 'Vpc.VpcId' --output text)

export IGW_ID=$(aws ec2 create-internet-gateway ... --query 'InternetGateway.InternetGatewayId' --output text)
aws ec2 attach-internet-gateway --internet-gateway-id $IGW_ID --vpc-id $VPC_ID

# Public / Private / Data Subnet 각 2개 + Public RT (0.0.0.0/0 → IGW)
```

**실제 생성 ID 예:** `vpc-0a074ca9d04307a9c`

### 콘솔

**VPC** → **Your VPCs** → **Create VPC**  
→ **Subnets** → **Internet gateways** → **Route tables**

### 검증

```bash
aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" \
  --query 'Subnets[*].[SubnetId,CidrBlock,Tags[?Key==`Name`].Value|[0]]' --output table
```

---

## Step 3 — NAT Gateway

### 뭔가요?

Private Subnet 안의 서버(EKS Node)가 **아웃바운드 인터넷**(ECR, 패키지 등)에 나갈 때 쓰는 **일방향 출구**입니다.

### 왜 하나요?

Private Subnet은 IGW에 직접 안 붙음 → NAT 없으면 ECR 이미지 pull 실패 → **Node Group CREATE_FAILED**.

### CLI로 한 것

```bash
export NAT_EIP=$(aws ec2 allocate-address --domain vpc --query 'AllocationId' --output text)
export NAT_GW=$(aws ec2 create-nat-gateway --subnet-id $PUB_SUBNET_A --allocation-id $NAT_EIP \
  --query 'NatGateway.NatGatewayId' --output text)
aws ec2 wait nat-gateway-available --nat-gateway-ids $NAT_GW

# Private RT: 0.0.0.0/0 → NAT
# Data RT: 인터넷 라우트 없음 (S3는 VPC Endpoint)
```

### 콘솔

**VPC** → **NAT gateways** → **Create** (Public Subnet + Elastic IP)  
→ **Route tables** → Private RT에 `0.0.0.0/0` → NAT

### 검증

```bash
aws ec2 describe-route-tables --route-table-ids $PRIV_RT \
  --query 'RouteTables[0].Routes' --output table
```

---

## Step 4 — Security Group

### 뭔가요?

가상 방화벽. **누가 어떤 포트로** 접근 가능한지 정합니다.

| SG | 인바운드 | 용도 |
|----|----------|------|
| `sg-alb` | 80, 443 ← `0.0.0.0/0` | ALB |
| `sg-eks-node` | 80, 8080 ← ALB SG | Frontend/Backend Pod |
| `sg-rds` | 5432 ← EKS Node SG | PostgreSQL |
| `sg-redis` | 6379 ← EKS Node SG | Redis |
| `sg-vpn` | 전체 ← `192.168.0.0/24` | On-Prem GPU |

### CLI로 한 것

```bash
export SG_ALB=$(aws ec2 create-security-group --group-name forenshield-sg-alb --vpc-id $VPC_ID ...)
aws ec2 authorize-security-group-ingress --group-id $SG_ALB --protocol tcp --port 443 --cidr 0.0.0.0/0
# ... 나머지 SG 동일 패턴
```

**실제 ID 예:** ALB `sg-0f875dafe0a5b59b3`

### 콘솔

**VPC** → **Security groups** → **Create** → Inbound rules 탭

---

## Step 5 — VPC Endpoint (S3, ECR)

### 뭔가요?

AWS 서비스(S3, ECR)로 가는 트래픽을 **인터넷/NAT 안 거치고** VPC 내부에서 직접 연결.

| Endpoint | 타입 | 용도 |
|----------|------|------|
| S3 | Gateway (무료) | 증거·모델 버킷 접근 |
| ECR API/DKR | Interface (유료) | NAT 없이 컨테이너 이미지 pull |

### 왜 하나요?

- Data Subnet(RDS)은 NAT 없이 S3 접근 필요
- ECR Endpoint + SG 설정으로 Node Group 안정화

### CLI로 한 것

```bash
aws ec2 create-vpc-endpoint --vpc-id $VPC_ID \
  --service-name com.amazonaws.ap-northeast-2.s3 \
  --route-table-ids $PRIV_RT $DATA_RT

# ECR Interface (선택) — SG에 EKS Cluster SG 443 허용 필수!
```

### 콘솔

**VPC** → **Endpoints** → **Create endpoint**  
→ Service category: AWS services → `com.amazonaws.ap-northeast-2.s3`

---

## Step 6 — S3 버킷

### 뭔가요?

| 버킷 | 용도 |
|------|------|
| `forenshield-evidence-{계정ID}` | 증거 파일 (Object Lock WORM, 변조 방지) |
| `forenshield-models-{계정ID}` | AI 모델 가중치 (`v1.0/video/model.pt` 등) |

### 왜 하나요?

- 포렌식 증거 **무결성** (Object Lock COMPLIANCE 365일)
- AI 모델 버전별 S3 경로 분리

### CLI로 한 것

```bash
export EVIDENCE_BUCKET=forenshield-evidence-${ACCOUNT_ID}
aws s3api create-bucket --bucket $EVIDENCE_BUCKET \
  --create-bucket-configuration LocationConstraint=ap-northeast-2 \
  --object-lock-enabled-for-bucket
aws s3api put-bucket-versioning --bucket $EVIDENCE_BUCKET \
  --versioning-configuration Status=Enabled
```

### 콘솔

**S3** → **Create bucket** → Object Lock 활성화 (생성 시에만 가능)

### 키 구조

```text
forenshield-evidence/cases/{case_id}/{file_id}/original/
forenshield-models/v1.0/{image|video|audio}/model.pt
```

---

## Step 7 — RDS + ElastiCache

### 뭔가요?

| 리소스 | 사양 | 용도 |
|--------|------|------|
| RDS PostgreSQL 16.9 | `db.t3.medium`, 20GB | 사건·메타데이터 영구 저장 |
| ElastiCache Redis 7.1 | `cache.t3.medium` | 세션·캐시·임시 상태 |

### 왜 하나요?

- Backend(Spring Boot)가 DB·캐시 필요
- Data Subnet + SG로 **외부 직접 접근 차단**

### CLI로 한 것

```bash
aws rds create-db-subnet-group --db-subnet-group-name forenshield-data-subnet-group \
  --subnet-ids $DATA_SUBNET_A $DATA_SUBNET_B

aws rds create-db-instance --db-instance-identifier forenshield-db \
  --engine postgres --engine-version 16.9 \
  --db-instance-class db.t3.medium \
  --vpc-security-group-ids $SG_RDS \
  --no-publicly-accessible ...

aws elasticache create-replication-group --replication-group-id forenshield-redis \
  --engine redis --cache-node-type cache.t3.medium \
  --security-group-ids $SG_REDIS \
  --transit-encryption-enabled --auth-token "$REDIS_AUTH_TOKEN"
```

### 콘솔

**RDS** → **Create database** → PostgreSQL, VPC forenshield, Private  
**ElastiCache** → **Redis** → Subnet group, Security group

### 검증

```bash
aws rds describe-db-instances --db-instance-identifier forenshield-db \
  --query 'DBInstances[0].Endpoint.Address' --output text
```

---

## Step 8 — ECR 레포지토리

### 뭔가요?

Docker 이미지 저장소. CI/CD에서 빌드한 이미지를 EKS가 pull 합니다.

| 레포 | 용도 |
|------|------|
| `forenshield-frontend` | Nginx + Next.js |
| `forenshield-backend` | Spring Boot |
| `forenshield-backend-worker` | Worker (선택) |
| `forenshield-ai-fastapi` | AI FastAPI Pod |

### CLI로 한 것

```bash
for REPO in forenshield-frontend forenshield-backend forenshield-ai-fastapi; do
  aws ecr create-repository --repository-name $REPO \
    --image-scanning-configuration scanOnPush=true
done
```

### 콘솔

**ECR** → **Create repository** → Scan on push 활성화

---

## Step 9 — Site-to-Site VPN

### 뭔가요?

AWS VPC ↔ **On-Prem GPU 서버**(RTX 5080) 사이 **암호화 터널**.  
EKS의 AI FastAPI Pod가 GPU Gateway(`192.168.0.66:8080`)를 Private처럼 호출합니다.

### 왜 하나요?

GPU는 학교/랩 On-Prem에 있고, 클라우드 EKS에서 **VPN 경유**로 추론 요청.

### 구성

| 리소스 | 값 |
|--------|-----|
| Customer Gateway | `58.127.241.84` (On-Prem 공인 IP) |
| Virtual Private Gateway | VPC에 attach |
| VPN Connection | IPSec, Static Route |
| On-Prem CIDR | `192.168.0.0/24` |

### CLI로 한 것

```bash
export CGW_ID=$(aws ec2 create-customer-gateway --type ipsec.1 --public-ip 58.127.241.84 ...)
export VGW_ID=$(aws ec2 create-vpn-gateway --type ipsec.1 ...)
aws ec2 attach-vpn-gateway --vpn-gateway-id $VGW_ID --vpc-id $VPC_ID
export VPN_ID=$(aws ec2 create-vpn-connection --customer-gateway-id $CGW_ID --vpn-gateway-id $VGW_ID ...)

aws ec2 enable-vgw-route-propagation --route-table-id $PRIV_RT --gateway-id $VGW_ID
aws ec2 enable-vgw-route-propagation --route-table-id $DATA_RT --gateway-id $VGW_ID
```

### 콘솔

**VPC** → **Site-to-Site VPN connections** → Create  
→ Customer gateway + Virtual private gateway + Download configuration (On-Prem StrongSwan 설정용)

### 검증

```bash
aws ec2 describe-vpn-connections --vpn-connection-ids $VPN_ID \
  --query 'VpnConnections[0].VgwTelemetry[*].[OutsideIpAddress,Status]' --output table
# 터널 2 UP 확인
```

---

## Step 10 — EKS Cluster

### 뭔가요?

Kubernetes **컨트롤 플레인**(AWS가 관리). Worker(Node)는 Step 11에서 붙입니다.

| 항목 | 값 |
|------|-----|
| Cluster name | `forenshield` |
| Version | 1.31 |
| Subnet | Public + Private (API endpoint 접근) |
| Add-ons | vpc-cni, kube-proxy, coredns |
| Namespace | `forenshield` |

### CLI로 한 것

```bash
export CLUSTER_NAME=forenshield
aws eks create-cluster \
  --name $CLUSTER_NAME \
  --kubernetes-version 1.29 \
  --role-arn arn:aws:iam::${ACCOUNT_ID}:role/forenshield-eks-cluster-role \
  --resources-vpc-config subnetIds=$PRIV_SUBNET_A,$PRIV_SUBNET_B,$PUB_SUBNET_A,$PUB_SUBNET_B,endpointPublicAccess=true,endpointPrivateAccess=true

aws eks wait cluster-active --name $CLUSTER_NAME

for ADDON in vpc-cni kube-proxy coredns; do
  aws eks create-addon --cluster-name $CLUSTER_NAME --addon-name $ADDON --resolve-conflicts OVERWRITE
done

aws eks update-kubeconfig --name $CLUSTER_NAME --region ap-northeast-2
kubectl create namespace forenshield
```

### 콘솔

**EKS** → **Clusters** → **Create cluster** → IAM role 선택, VPC/Subnet, Logging 활성화  
→ **Add-ons** 탭에서 CNI/CoreDNS/kube-proxy

### 검증

```bash
kubectl get nodes   # Step 11 전에는 "No resources"
aws eks describe-cluster --name forenshield --query 'cluster.status' --output text
```

---

## Step 11 — EC2 Node Groups

### 뭔가요?

EKS 위에서 실제 Pod가 돌아가는 **EC2 워커 노드 그룹**.

| Node Group | Instance | 수 | 배포 Pod |
|------------|----------|-----|----------|
| `frontend-ng` | t3.medium | 1 | Nginx + Next.js |
| `backend-ng` | t3.medium | 2 | Spring Boot + RabbitMQ |
| `ai-fastapi-ng` | t3.medium | 1 | AI FastAPI (GPU 연동) |

### 왜 3개로 나눴나?

- Frontend / Backend / AI **스케일·배포 분리**
- `nodeSelector`로 Pod를 특정 그룹에 고정

### CLI로 한 것

```bash
export NODE_ROLE_ARN=arn:aws:iam::${ACCOUNT_ID}:role/forenshield-eks-node-role

aws eks create-nodegroup --cluster-name forenshield --nodegroup-name frontend-ng \
  --subnets $PRIV_SUBNET_A $PRIV_SUBNET_B --instance-types t3.medium \
  --scaling-config minSize=1,maxSize=2,desiredSize=1 \
  --node-role $NODE_ROLE_ARN

# backend-ng (desired 2), ai-fastapi-ng 동일 패턴
aws eks wait nodegroup-active --cluster-name forenshield --nodegroup-name backend-ng
```

### 콘솔

**EKS** → Cluster `forenshield` → **Compute** → **Add node group**  
→ Node IAM role, Subnet(Private), Instance type, Scaling

### 검증

```bash
kubectl get nodes -L nodegroup
# 4 nodes (frontend 1 + backend 2 + ai 1) ACTIVE
```

---

## (참고) Step 12~14 — 진행 중·예정

| Step | 상태 | 내용 |
|------|------|------|
| 12 ALB | ALB 생성됨, HTTPS 리스너 대기 | `forenshield-alb`, TG `forenshield-frontend-tg` |
| 13 Route 53 | 도메인 등록 완료 | `forensheildjangdochi.com` → ALB Alias, ACM **ISSUED** |
| 14 CloudWatch | Log group 존재 | `/aws/eks/forenshield/cluster` (EKS가 자동 생성) |

### ALB HTTPS 리스너 (다음 할 일)

```bash
aws elbv2 create-listener \
  --load-balancer-arn $ALB_ARN \
  --protocol HTTPS --port 443 \
  --certificates CertificateArn=$ACM_ARN \
  --default-actions Type=forward,TargetGroupArn=$TG_ARN
```

---

## CLI vs 콘솔 — 언제 뭘 쓰나

| CLI 장점 | 콘솔 장점 |
|----------|-----------|
| 문서화·재현 가능 (명령 = 레시피) | 시각적으로 구조 파악 쉬움 |
| Terraform/IaC로 전환 용이 | Route 53 도메인 등록 UI 편함 |
| 스크립트·자동화 | VPN 터널 상태·로그 보기 편함 |

이번 프로젝트는 **`2.Terraform architecture.md`** 에 CLI 명령을 전부 적어 두고, 동일 구성을 **`terraform/`** 코드로도 만들어 둔 상태입니다.

---

## 주요 리소스 ID 모음 (메모용)

| 리소스 | ID / 값 |
|--------|---------|
| VPC | `vpc-0a074ca9d04307a9c` |
| ALB SG | `sg-0f875dafe0a5b59b3` |
| VPN | `vpn-0b0142909451ce096` |
| Hosted Zone (사용) | `Z091888114TC5UULOEOX5` |
| ACM ARN | `.../certificate/042b2105-2192-468f-ab45-5c833f4e23aa` |
| ALB DNS | `forenshield-alb-982199992.ap-northeast-2.elb.amazonaws.com` |

---

## 마무리

Step 1~11은 **"네트워크 → 데이터 → 컨테이너 실행 환경 → On-Prem GPU 연결"** 까지의 뼈대입니다.  
앱 배포(Frontend/Backend/AI Helm), RabbitMQ, Ingress는 그 다음 Sprint에서 이어집니다.

막혔던 문제는 → [트러블슈팅 정리](./tistory-infra-troubleshooting.md)

상세 CLI 전체 명령 → [2. Terraform architecture](./2.Terraform%20architecture.md)

---

*ForenShield AI · AWS 인프라 구축 일지*
