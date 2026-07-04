#!/usr/bin/env bash
# EC2 reboot / start 후 Fabric peer·orderer 기동 (network.sh down 사용 금지 전제)
set -euo pipefail

WORK="${FABRIC_WORK_DIR:-$HOME/forenshield-fabric-runtime}"
SAMPLES="$WORK/fabric-samples"
TN="$SAMPLES/test-network"
CHANNEL="${FABRIC_CHANNEL:-forenshield-evidence}"
CC_NAME="${FABRIC_CHAINCODE:-anchor}"
CC_SRC="${FABRIC_CC_SRC:-$HOME/forenshield-infra/fabric/chaincode/anchor}"
LOG_DIR="${FABRIC_LOG_DIR:-$HOME/forenshield-infra/fabric/logs}"
LOG="$LOG_DIR/fabric-network.log"

mkdir -p "$LOG_DIR"
exec >>"$LOG" 2>&1
echo "=== $(date -Is) start-fabric-network ==="

if [[ ! -d "$TN" ]]; then
  echo "ERROR: test-network not found. Run: bash ~/forenshield-infra/fabric/scripts/setup-all.sh"
  exit 1
fi

export PATH="$SAMPLES/bin:$PATH"
export FABRIC_CFG_PATH="$SAMPLES/config/"

echo "Waiting for docker..."
for i in $(seq 1 60); do
  if docker info >/dev/null 2>&1; then
    break
  fi
  sleep 2
done
if ! docker info >/dev/null 2>&1; then
  echo "ERROR: docker not ready"
  exit 1
fi

cd "$TN"

if docker ps --format '{{.Names}}' | grep -q 'peer0.org1'; then
  echo "Fabric peers already running — skip"
  exit 0
fi

echo "Fabric network up + channel $CHANNEL ..."
if ! ./network.sh up createChannel -c "$CHANNEL" -ca; then
  echo "WARN: up createChannel failed — retry up -ca (ledger may already exist)"
  ./network.sh up -ca || true
fi

echo "Deploy chaincode $CC_NAME (already deployed면 실패해도 무시)..."
if [[ -d "$CC_SRC" ]]; then
  ./network.sh deployCC -ccn "$CC_NAME" -ccp "$CC_SRC" -ccl go -c "$CHANNEL" || \
    echo "WARN: deployCC failed — chaincode may already be on channel"
else
  echo "WARN: chaincode path missing: $CC_SRC"
fi

INFRA_FABRIC="${INFRA_FABRIC:-$HOME/forenshield-infra/fabric}"
if [[ -x "$INFRA_FABRIC/scripts/write-gateway-env.sh" ]]; then
  echo "Regenerating gateway/.env (crypto paths after network up)..."
  bash "$INFRA_FABRIC/scripts/write-gateway-env.sh" "$SAMPLES"
fi

echo "=== $(date -Is) done ==="
