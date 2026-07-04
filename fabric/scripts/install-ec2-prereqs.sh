#!/usr/bin/env bash
# Ubuntu 22.04/24.04 EC2 — Fabric PoC 사전 패키지 (최초 1회)
# 사용: sudo bash scripts/install-ec2-prereqs.sh
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

apt-get update -y
apt-get install -y docker.io git golang curl ca-certificates

# Ubuntu docker.io 저장소는 docker-compose-plugin 이 없고 docker-compose-v2 를 씀
if ! docker compose version >/dev/null 2>&1; then
  if apt-cache show docker-compose-v2 >/dev/null 2>&1; then
    apt-get install -y docker-compose-v2
  elif apt-cache show docker-compose >/dev/null 2>&1; then
    apt-get install -y docker-compose
  else
    echo "ERROR: docker compose 를 설치할 수 없습니다."
    echo "       sudo apt install docker-compose-v2  또는  docker-compose"
    exit 1
  fi
fi

if ! command -v node >/dev/null 2>&1 || [[ "$(node -v | sed 's/v//' | cut -d. -f1)" -lt 18 ]]; then
  curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
  apt-get install -y nodejs
fi

systemctl enable docker
systemctl start docker

if [[ -n "${SUDO_USER:-}" ]]; then
  usermod -aG docker "$SUDO_USER"
  echo "docker 그룹 추가: $SUDO_USER (재로그인 필요)"
fi

docker --version
if docker compose version >/dev/null 2>&1; then
  docker compose version
elif command -v docker-compose >/dev/null 2>&1; then
  docker-compose version
fi
node --version
go version

echo "OK — 다음: bash scripts/setup-all.sh"
