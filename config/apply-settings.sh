#!/usr/bin/env bash
# ForenShield — K8s ConfigMap · Secret · IRSA 적용
# 사용:
#   cp config/secrets.env.example config/secrets.env
#   # secrets.env 에 RDS/Redis/RabbitMQ 비밀번호 입력
#   bash config/apply-settings.sh

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# infra 값 (비밀 없음)
if [[ -f config/infra.env ]]; then
  # shellcheck source=/dev/null
  source config/infra.env
elif [[ -f config/infra.env.example ]]; then
  # shellcheck source=/dev/null
  source config/infra.env.example
fi

# 비밀번호 (필수)
if [[ ! -f config/secrets.env ]]; then
  echo "ERROR: config/secrets.env 없음"
  echo "  cp config/secrets.env.example config/secrets.env"
  echo "  POSTGRES_PASSWORD, REDIS_PASSWORD, RABBITMQ_PASSWORD 입력 후 재실행"
  exit 1
fi
# shellcheck source=/dev/null
source config/secrets.env

: "${POSTGRES_PASSWORD:?POSTGRES_PASSWORD required in config/secrets.env}"
: "${REDIS_PASSWORD:?REDIS_PASSWORD required in config/secrets.env}"
: "${RABBITMQ_PASSWORD:?RABBITMQ_PASSWORD required in config/secrets.env}"
: "${JWT_SECRET_KEY:?JWT_SECRET_KEY required in config/secrets.env}"

export AWS_PROFILE="${AWS_PROFILE:-forenshield}"
export AWS_REGION="${AWS_REGION:-ap-northeast-2}"

echo "==> kubeconfig"
aws eks update-kubeconfig --name "${CLUSTER_NAME:-forenshield}" --region "$AWS_REGION" >/dev/null

echo "==> IRSA Role (forenshield-app-s3-role)"
if ! aws iam get-role --role-name forenshield-app-s3-role >/dev/null 2>&1; then
  aws iam create-role \
    --role-name forenshield-app-s3-role \
    --assume-role-policy-document "file://${ROOT}/config/iam/trust-app-s3.json"
  aws iam put-role-policy \
    --role-name forenshield-app-s3-role \
    --policy-name forenshield-app-s3-policy \
    --policy-document "file://${ROOT}/config/iam/policy-app-s3.json"
  echo "    created forenshield-app-s3-role"
else
  aws iam put-role-policy \
    --role-name forenshield-app-s3-role \
    --policy-name forenshield-app-s3-policy \
    --policy-document "file://${ROOT}/config/iam/policy-app-s3.json" 2>/dev/null || true
  echo "    role exists"
fi

echo "==> ConfigMaps"
kubectl apply -f config/k8s/app-config.yaml
kubectl apply -f config/k8s/frontend-config.yaml

echo "==> ServiceAccount (IRSA)"
kubectl apply -f config/k8s/serviceaccount-app.yaml

echo "==> Secrets"
kubectl create secret generic db-credentials \
  --namespace forenshield \
  --from-literal=POSTGRES_HOST="${RDS_ENDPOINT}" \
  --from-literal=POSTGRES_USER=forenshield \
  --from-literal=POSTGRES_PASSWORD="${POSTGRES_PASSWORD}" \
  --from-literal=POSTGRES_DB=forenshield \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret generic redis-credentials \
  --namespace forenshield \
  --from-literal=REDIS_HOST="${REDIS_ENDPOINT}" \
  --from-literal=REDIS_PASSWORD="${REDIS_PASSWORD}" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret generic rabbitmq-credentials \
  --namespace forenshield \
  --from-literal=RABBITMQ_HOST=rabbitmq.forenshield.svc.cluster.local \
  --from-literal=RABBITMQ_PORT=5672 \
  --from-literal=RABBITMQ_USER=forenshield \
  --from-literal=RABBITMQ_PASSWORD="${RABBITMQ_PASSWORD}" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret generic app-secrets \
  --namespace forenshield \
  --from-literal=JWT_SECRET_KEY="${JWT_SECRET_KEY}" \
  --dry-run=client -o yaml | kubectl apply -f -

MANIFEST_KEY="${ROOT}/config/secrets/platform-signing-key.pem"
MANIFEST_CERT="${ROOT}/config/secrets/platform-signing-cert.pem"
if [[ -f "$MANIFEST_KEY" && -f "$MANIFEST_CERT" ]]; then
  kubectl create secret generic manifest-signing-credentials \
    --namespace forenshield \
    --from-file=MANIFEST_SIGNING_PRIVATE_KEY_PEM="${MANIFEST_KEY}" \
    --from-file=MANIFEST_SIGNING_CERTIFICATE_PEM="${MANIFEST_CERT}" \
    --dry-run=client -o yaml | kubectl apply -f -
  echo "    manifest-signing-credentials applied"
else
  echo "    WARN: ${MANIFEST_KEY} 또는 ${MANIFEST_CERT} 없음 — manifest-signing-credentials 스킵"
  echo "          PEM을 config/secrets/ 에 두고 재실행하거나 kubectl로 직접 생성하세요."
fi

kubectl create secret generic s3-config \
  --namespace forenshield \
  --from-literal=AWS_ROLE_ARN="${APP_S3_ROLE_ARN:-arn:aws:iam::877044078824:role/forenshield-app-s3-role}" \
  --from-literal=S3_EVIDENCE_BUCKET="${S3_EVIDENCE_BUCKET}" \
  --from-literal=S3_MODELS_BUCKET="${S3_MODELS_BUCKET}" \
  --dry-run=client -o yaml | kubectl apply -f -

echo ""
echo "==> 완료. 확인:"
kubectl get configmap,secret,serviceaccount -n forenshield | grep -E 'app-config|frontend-config|db-credentials|redis-credentials|rabbitmq-credentials|s3-config|forenshield-app' || true
