# ForenShield — Settings (Step 3)

`3.settings.md` 기준 K8s Secret · ConfigMap · IRSA 파일 모음.

## 파일

| 파일 | Git | 용도 |
|------|-----|------|
| `.env.example` | ✅ | 로컬 개발 템플릿 |
| `config/infra.env.example` | ✅ | AWS 리소스 ID·엔드포인트 (비밀 없음) |
| `config/secrets.env.example` | ✅ | 비밀번호 템플릿 |
| `config/secrets.env` | ❌ | 실제 비밀번호 (직접 생성) |
| `config/k8s/*.yaml` | ✅ | ConfigMap · ServiceAccount |
| `config/iam/*.json` | ✅ | IRSA Role 정책 |

## 적용 방법

```bash
# 1) 비밀번호 파일 생성
cp config/secrets.env.example config/secrets.env
# POSTGRES_PASSWORD, REDIS_PASSWORD, RABBITMQ_PASSWORD 입력

# 2) (선택) infra.env 복사 — 기본은 infra.env.example 사용
cp config/infra.env.example config/infra.env

# 3) K8s Secret · ConfigMap · IRSA 일괄 적용
bash config/apply-settings.sh
```

## 생성되는 K8s 리소스

| 이름 | 종류 | 용도 |
|------|------|------|
| `db-credentials` | Secret | RDS |
| `redis-credentials` | Secret | ElastiCache |
| `rabbitmq-credentials` | Secret | RabbitMQ |
| `s3-config` | Secret | S3 버킷 + IRSA ARN |
| `app-config` | ConfigMap | Backend · AI 공통 |
| `frontend-config` | ConfigMap | Frontend |
| `forenshield-app` | ServiceAccount | S3 IRSA |

Pod에서 `serviceAccountName: forenshield-app` 사용.
