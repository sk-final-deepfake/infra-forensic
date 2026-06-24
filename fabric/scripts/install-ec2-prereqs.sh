#!/usr/bin/env bash
# Ubuntu 22.04 EC2 — Fabric PoC 사전 패키지 (최초 1회)
# 사용: sudo bash scripts/install-ec2-prereqs.sh
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

apt-get update -y
apt-get install -y docker.io git golang curl ca-certificates

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
node --version
go version

echo "OK — 다음: bash scripts/setup-all.sh"
