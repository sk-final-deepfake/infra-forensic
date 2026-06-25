# 환경변수 · Secret · RDS 관리

> **관련:** [handbook.md](./handbook.md) · [deployment.md](./deployment.md) · [config/README](../config/README.md)  
> **Namespace:** `forenshield`

소스코드 하드코딩으로 인한 기밀 데이터(DB 비밀번호, S3 키 등) 유출을 방지하고, 로컬(Windows)과 배포(Docker/EKS) 환경을 **코드 수정 없이** 전환할 수 있도록 환경변수 인프라를 정립합니다.

---

## 목차

1. [작업 목적 · 범위](#1-작업-목적--범위)
2. [관리 계층 총괄](#2-관리-계층-총괄)
3. [인프라 구축용 변수 (Terraform)](#3-인프라-구축용-변수-terraform)
4. [Kubernetes Secret](#4-kubernetes-secret)
5. [Kubernetes ConfigMap](#5-kubernetes-configmap)
6. [애플리케이션별 매핑](#6-애플리케이션별-매핑)
7. [CI/CD Secrets](#7-cicd-secrets)
8. [관리 원칙 · .env.example](#8-관리-원칙--envexample)
9. [완료 기준](#9-완료-기준)

---

## 1. 작업 목적 · 범위

### 1.1 작업 목적

- DB, 스토리지, 메시지 큐, 서비스 URL 등 **핵심 접속 정보**를 환경변수로 외부화
- Spring Boot: `application.yml`의 `${VAR}` 매핑
- FastAPI: `pydantic-settings`로 시스템 환경변수 주입

### 1.2 구현 범위

| 항목 | 내용 |
|------|------|
| 환경변수 정의 | DB, S3, RabbitMQ, 서비스 URL |
| `.env.example` | 팀 공유용 템플릿 (값 없음) |
| `.gitignore` | `.env` 실파일 Git 제외 검증 |

---

## 2. 관리 계층 총괄

| 관리 계층 | 저장 위치 | 용도 | 비고 |
|-----------|-----------|------|------|
| 로컬 셸 / `.env` | 개발자 PC | AWS CLI·Terraform·스크립트 | Phase 0~3 |
| `terraform.tfvars` | Git 제외, 로컬/S3 Backend | Terraform 변수 | Phase 3 |
| K8s **Secret** | `forenshield` namespace | DB·캐시·MQ 비밀번호 | Phase 4 |
| K8s **ConfigMap** | `forenshield` namespace | 호스트·버킷명·URL | Phase 4 |
| **IRSA / IAM Role** | AWS IAM | S3 접근 (Access Key 대체) | 운영 권장 |
| **GitHub Actions Secrets** | Repository Settings | CI/CD | Phase 4 |

---

## 3. 인프라 구축용 변수 (Terraform)

| 변수명 | 설명 | 예시값 | 민감 | 저장 위치 |
|--------|------|--------|------|-----------|
| `AWS_REGION` | AWS 리전 | `ap-northeast-2` | N | 셸 / tfvars |
| `AWS_ACCOUNT_ID` | 계정 ID (12자리) | `123456789012` | N | 셸 / tfvars |
| `PROJECT` | 리소스 접두사 | `forenshield` | N | 셸 / tfvars |
| `VPC_CIDR` | VPC CIDR | `10.0.0.0/16` | N | 셸 / tfvars |
| `PUBLIC_SUBNET_A` | Public (AZ-a) | `10.0.1.0/24` | N | 셸 / tfvars |
| `PUBLIC_SUBNET_B` | Public (AZ-b) | `10.0.2.0/24` | N | 셸 / tfvars |
| `PRIVATE_SUBNET_A` | Private EKS (AZ-a) | `10.0.10.0/24` | N | 셸 / tfvars |
| `PRIVATE_SUBNET_B` | Private EKS (AZ-b) | `10.0.11.0/24` | N | 셸 / tfvars |
| `DATA_SUBNET_A` | RDS/Redis (AZ-a) | `10.0.20.0/24` | N | 셸 / tfvars |
| `DATA_SUBNET_B` | RDS/Redis (AZ-b) | `10.0.21.0/24` | N | 셸 / tfvars |
| `ONPREM_PUBLIC_IP` | GPU 서버 공인 IP | `<실제 IP>` | N | 셸 / tfvars |
| `ONPREM_PRIVATE_CIDR` | On-Prem CIDR | `192.168.0.0/24` | N | 셸 / tfvars |
| `ONPREM_GATEWAY_IP` | AI Gateway 내부 IP | `192.168.0.10` | N | 셸 / tfvars |

---

## 4. Kubernetes Secret

> Phase 1 GPU 테스트용 임시 IAM Access Key는 **테스트 후 삭제**. 운영은 **IRSA만** 사용.

### 4.1 `db-credentials`

| 키 | 설명 | 사용 Pod | 민감 |
|----|------|----------|------|
| `POSTGRES_HOST` | RDS 엔드포인트 | Backend | N |
| `POSTGRES_USER` | DB 사용자 | Backend | Y |
| `POSTGRES_PASSWORD` | DB 비밀번호 | Backend | Y |
| `POSTGRES_DB` | DB 이름 (권장) | Backend | N |

### 4.2 `redis-credentials`

| 키 | 설명 | 사용 Pod | 민감 |
|----|------|----------|------|
| `REDIS_HOST` | ElastiCache 엔드포인트 | Backend | N |
| `REDIS_PASSWORD` | Redis AUTH | Backend | Y |

### 4.3 `rabbitmq-credentials`

| 키 | 설명 | 사용 Pod | 민감 |
|----|------|----------|------|
| `RABBITMQ_USER` | RabbitMQ 사용자 | Backend, AI FastAPI | Y |
| `RABBITMQ_PASSWORD` | RabbitMQ 비밀번호 | Backend, AI FastAPI | Y |

### 4.4 `s3-config`

| 키 | 설명 | 사용 Pod | 민감 |
|----|------|----------|------|
| `AWS_ROLE_ARN` | IRSA Role ARN | Backend, AI FastAPI | N |
| `S3_EVIDENCE_BUCKET` | 증거 버킷 | Backend, AI FastAPI | N |
| `S3_MODELS_BUCKET` | 모델 버킷 | AI FastAPI | N |

---

## 5. Kubernetes ConfigMap

### 5.1 `app-config`

| 키 | 설명 | 사용 Pod | 예시값 |
|----|------|----------|--------|
| `AWS_REGION` | 리전 | Backend, AI FastAPI | `ap-northeast-2` |
| `RABBITMQ_HOST` | MQ 주소 | Backend, AI FastAPI | `rabbitmq.forenshield.svc:5672` |
| `AI_GATEWAY_URL` | GPU Gateway | AI FastAPI | `http://192.168.0.10:8000` |
| `SPRING_PROFILES_ACTIVE` | Spring 프로파일 | Backend | `prod` |
| `SERVER_PORT` | Backend 포트 | Backend | `8080` |

### 5.2 `frontend-config`

| 키 | 설명 | 사용 Pod | 예시값 |
|----|------|----------|--------|
| `NEXT_PUBLIC_API_URL` | API URL | Frontend | `https://<domain>/api` |
| `NODE_ENV` | Node 환경 | Frontend | `production` |

---

## 6. 애플리케이션별 매핑

| 서비스 | 환경변수 | 출처 | 용도 |
|--------|----------|------|------|
| **Backend** | `POSTGRES_*` | Secret `db-credentials` | RDS |
| | `REDIS_*` | Secret `redis-credentials` | 캐시 |
| | `RABBITMQ_*` | Secret + ConfigMap | 큐 |
| | `S3_EVIDENCE_BUCKET`, `AWS_REGION` | Secret / ConfigMap | S3 업로드 |
| **AI FastAPI** | `AI_GATEWAY_URL` | ConfigMap | GPU 추론 |
| | `RABBITMQ_*` | Secret + ConfigMap | 큐 consume |
| | `S3_*`, `AWS_REGION` | Secret / ConfigMap | 증거·모델 |
| **Frontend** | `NEXT_PUBLIC_API_URL` | ConfigMap (빌드 타임) | API 호출 |
| **GPU Gateway** | `AWS_REGION`, S3 버킷 | GPU `.env` / Role | S3 다운로드 |

---

## 7. CI/CD Secrets

| Secret 이름 | 설명 | 민감 |
|-------------|------|------|
| `AWS_ROLE_ARN` | OIDC AssumeRole ARN | N |
| `AWS_REGION` | ECR·EKS 리전 | N |
| `ECR_REGISTRY` | ECR URL | N |
| `EKS_CLUSTER_NAME` | 클러스터명 | N |
| `ARGOCD_*` | ArgoCD (사용 시) | Y |

> 장기 AWS Access Key **사용 금지** — OIDC + `sts:AssumeRole` 권장.

---

## 8. 관리 원칙 · .env.example

### 8.1 Secret vs ConfigMap

| 구분 | Secret | ConfigMap |
|------|--------|-----------|
| 비밀번호·토큰 | ✅ | ❌ |
| DB/Redis 호스트 | △ | ✅ |
| 버킷명·리전·URL | ❌ | ✅ |
| Git 커밋 | ❌ 절대 금지 | ❌ (K8s만) |
| 로컬 개발 | `.env.local` | `.env.example` |

### 8.2 `.env.example` 템플릿

```dotenv
# ==============================================================================
# ForenShield AI — .env.example
# 복사 후 '.env'로 저장하고 값을 입력하세요. Git 커밋 금지.
# ==============================================================================

# 1. AWS / S3
AWS_REGION=ap-northeast-2
S3_EVIDENCE_BUCKET=forenshield-evidence
S3_MODELS_BUCKET=forenshield-models
# S3 자격증명: EKS IRSA 사용 — Access Key 입력 금지

# 2. RabbitMQ
RABBITMQ_HOST=YOUR_RABBITMQ_HOST
RABBITMQ_PORT=5672
RABBITMQ_USER=YOUR_MQ_USER
RABBITMQ_PASSWORD=YOUR_MQ_PASSWORD

# 3. Service URLs
AI_SERVER_URL=http://forenshield-ai-engine:8000
API_BASE_URL=http://localhost:8080

# 4. Security
JWT_SECRET_KEY=YOUR_JWT_HEX_SIGNING_KEY_DO_NOT_LEAK
```

### 8.3 `.gitignore` 검증

프로젝트 루트 `.gitignore`에 아래가 포함되어야 합니다.

```gitignore
.env
.env.local
.env.production
terraform.tfvars
```

---

## 9. 완료 기준

- [x] 핵심 환경변수 목록이 문서·`.env.example`에 명세됨
- [x] `.env.example` 템플릿 생성 완료 ([`../.env.example`](../.env.example))
- [x] `.gitignore`에 `.env` 차단 등록 검증 완료 ([`../.gitignore`](../.gitignore))
- [x] K8s Secret · ConfigMap · IRSA 매니페스트 ([`../config/`](../config/README.md))

### 적용 (CLI 구축 환경)

```bash
cp config/secrets.env.example config/secrets.env
# POSTGRES_PASSWORD, REDIS_PASSWORD, RABBITMQ_PASSWORD 입력
bash config/apply-settings.sh
```

### 사용 스택

| 구분 | 기술 |
|------|------|
| 로컬 | Dotenv (`.env`) |
| Backend | Spring Boot `application.yml` |
| AI | Python `pydantic-settings` |
| VCS | Git `.gitignore` |

---

## 부록 A — RDS 접속 · 관리자 계정

RDS는 VPC 내부 — 로컬에서 직접 접속 대신 **kubectl debug Pod** 사용.

```powershell
kubectl get secret db-credentials -n forenshield -o json | ConvertFrom-Json | ForEach-Object {
  $_.data.PSObject.Properties | ForEach-Object {
    Write-Host "$($_.Name) = $([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($_.Value)))"
  }
}
```

| 항목 | 값 |
|------|-----|
| Host | `forenshield-db.chcswakki5dc.ap-northeast-2.rds.amazonaws.com` |
| DB / User | `forenshield` |

비밀번호에 `$` 있으면 **작은따옴표**로 감싸기.

관리자 INSERT 등 상세 SQL은 backend `users` 테이블 스키마 기준으로 `psql` Pod에서 실행.

---

## 부록 B — Git 유출 시 비밀번호 교체

`.env` 등이 GitHub에 올라갔다면 **히스토리 삭제만으로는 부족** — AWS 자격증명을 먼저 교체.

```text
① RDS POSTGRES_PASSWORD  ② Redis AUTH  ③ JWT_SECRET  ④ RabbitMQ password
→ config/secrets.env 갱신 → bash config/apply-settings.sh → Pod 재시작
→ 마지막에 Git filter-repo / .example 실값 제거
```

---

*문서 버전: 2026-06-24*
