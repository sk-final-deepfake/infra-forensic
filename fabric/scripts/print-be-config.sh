#!/usr/bin/env bash
# EC2에서 EKS app-config 에 넣을 BLOCKCHAIN_* 값 출력
set -euo pipefail

PORT="${GATEWAY_PORT:-8088}"
PRIVATE_IP=""

if curl -sf --connect-timeout 1 http://169.254.169.254/latest/meta-data/local-ipv4 >/dev/null 2>&1; then
  PRIVATE_IP="$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)"
fi

if [[ -z "$PRIVATE_IP" ]]; then
  PRIVATE_IP="$(hostname -I | awk '{print $1}')"
fi

cat <<EOF
# EKS ConfigMap (app-config.yaml) — EC2 Fabric Gateway
BLOCKCHAIN_ANCHOR_ENABLED: "true"
BLOCKCHAIN_ANCHOR_MODE: "http"
BLOCKCHAIN_ANCHOR_URL: "http://${PRIVATE_IP}:${PORT}/api/v1/anchor"
BLOCKCHAIN_ANCHOR_NETWORK: "hyperledger-fabric-forenshield"

# 적용
kubectl apply -f config/k8s/app-config.yaml -n forenshield
kubectl rollout restart deployment/backend -n forenshield
EOF
