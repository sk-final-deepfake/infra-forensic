#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT/gateway"
if [[ ! -f .env ]]; then
  cp env.example .env
  echo "Created .env from env.example — FABRIC_* 경로를 채운 뒤 다시 실행하세요."
  echo "또는: bash ../scripts/write-gateway-env.sh"
  exit 1
fi
npm install --omit=dev
npm start
