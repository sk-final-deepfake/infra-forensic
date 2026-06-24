#!/usr/bin/env bash
# fabric-samples test-network 인증서 경로 → gateway/.env
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SAMPLES="${1:-$HOME/forenshield-fabric-runtime/fabric-samples}"
TN="$SAMPLES/test-network"
ENV_FILE="$ROOT/gateway/.env"

TLS="$TN/organizations/peerOrganizations/org1.example.com/peers/peer0.org1.example.com/tls/ca.crt"
CERT="$TN/organizations/peerOrganizations/org1.example.com/users/Admin@org1.example.com/msp/signcerts/cert.pem"
KEY_DIR="$TN/organizations/peerOrganizations/org1.example.com/users/Admin@org1.example.com/msp/keystore"

if [[ ! -f "$TLS" ]]; then
  echo "ERROR: Fabric TLS cert not found: $TLS"
  echo "       먼저 scripts/setup-all.sh 를 실행하세요."
  exit 1
fi

KEY="$(find "$KEY_DIR" -maxdepth 1 -type f | head -n 1)"
if [[ -z "$KEY" ]]; then
  echo "ERROR: Fabric private key not found under $KEY_DIR"
  exit 1
fi

cat > "$ENV_FILE" <<EOF
GATEWAY_PORT=8088
GATEWAY_API_KEY=

FABRIC_NETWORK_LABEL=hyperledger-fabric-forenshield
FABRIC_CHANNEL=${FABRIC_CHANNEL:-forenshield-evidence}
FABRIC_CHAINCODE=${FABRIC_CHAINCODE:-anchor}
FABRIC_MSP_ID=Org1MSP
FABRIC_PEER_ENDPOINT=localhost:7051
FABRIC_PEER_HOST_ALIAS=peer0.org1.example.com
FABRIC_TLS_CERT_PATH=$TLS
FABRIC_CERT_PATH=$CERT
FABRIC_KEY_PATH=$KEY
EOF

echo "Wrote $ENV_FILE"
