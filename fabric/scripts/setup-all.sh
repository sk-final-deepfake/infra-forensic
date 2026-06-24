#!/usr/bin/env bash
# ForenShield — Hyperledger Fabric PoC (Ubuntu EC2 권장 / On-Prem 가능)
# 사용법: bash scripts/setup-all.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="${FABRIC_WORK_DIR:-$HOME/forenshield-fabric-runtime}"
SAMPLES="$WORK/fabric-samples"
CHANNEL="${FABRIC_CHANNEL:-forenshield-evidence}"
CC_NAME="${FABRIC_CHAINCODE:-anchor}"
CC_SRC="$ROOT/chaincode/anchor"
FABRIC_VERSION="${FABRIC_VERSION:-2.5.12}"

echo "==> ForenShield Fabric PoC"
echo "    repo fabric dir: $ROOT"
echo "    runtime workdir: $WORK"

if ! command -v docker >/dev/null 2>&1; then
  echo "ERROR: docker 가 필요합니다. (sudo apt install docker.io)"
  exit 1
fi
if ! docker info >/dev/null 2>&1; then
  echo "ERROR: docker 권한 없음. sudo usermod -aG docker \$USER 후 재로그인"
  exit 1
fi

mkdir -p "$WORK"
if [[ ! -d "$SAMPLES" ]]; then
  echo "==> fabric-samples clone"
  git clone https://github.com/hyperledger/fabric-samples.git "$SAMPLES"
  cd "$SAMPLES" && git checkout "v${FABRIC_VERSION}" 2>/dev/null || git checkout main
fi

cd "$SAMPLES"
if [[ ! -x bin/peer ]]; then
  echo "==> Fabric binaries download (최초 1회, 수 분)"
  curl -sSL https://bit.ly/2ysbOFE | bash -s -- "$FABRIC_VERSION" 1.5.15
fi

export PATH="$SAMPLES/bin:$PATH"
export FABRIC_CFG_PATH="$SAMPLES/config/"

cd "$SAMPLES/test-network"
echo "==> Fabric network up + channel $CHANNEL"
./network.sh down || true
./network.sh up createChannel -c "$CHANNEL" -ca

echo "==> Deploy chaincode $CC_NAME"
./network.sh deployCC -ccn "$CC_NAME" -ccp "$CC_SRC" -ccl go -c "$CHANNEL"

echo "==> Gateway .env 작성"
bash "$ROOT/scripts/write-gateway-env.sh" "$SAMPLES"

echo "==> npm install (gateway)"
cd "$ROOT/gateway"
if command -v npm >/dev/null 2>&1; then
  npm install --omit=dev
else
  echo "WARN: npm 없음. Node 18+ 설치 후: cd $ROOT/gateway && npm install"
fi

cat <<EOF

============================================================
 Fabric 네트워크 + chaincode 배포 완료
============================================================
 Gateway 시작:
   cd $ROOT/gateway
   npm start
   # 또는: bash $ROOT/scripts/start-gateway.sh

 헬스체크:
   curl http://localhost:8088/health

 앵커 테스트:
   curl -X POST http://localhost:8088/api/v1/anchor \\
     -H 'Content-Type: application/json' \\
     -d '{"subjectHash":"abc123","anchorType":"EVIDENCE_HASH","clientId":"forenshield-be","evidenceId":"1"}'

 EKS BE 설정 (EC2 private IP):
   bash $ROOT/scripts/print-be-config.sh

 가이드: Infra/md/21.fabric-gateway-quickstart.md

 네트워크 중지:
   cd $SAMPLES/test-network && ./network.sh down
============================================================
EOF

bash "$ROOT/scripts/print-be-config.sh" || true
