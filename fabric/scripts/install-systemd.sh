#!/usr/bin/env bash
# Fabric + Gateway systemd 등록 (EC2에서 1회)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Run with sudo: sudo bash scripts/install-systemd.sh"
  exit 1
fi

chmod +x "$ROOT/scripts/start-fabric-network.sh"
chmod +x "$ROOT/scripts/start-gateway.sh"

cp "$ROOT/systemd/forenshield-fabric-network.service" /etc/systemd/system/
cp "$ROOT/systemd/forenshield-fabric-gateway.service" /etc/systemd/system/

systemctl daemon-reload
systemctl enable forenshield-fabric-network.service
systemctl enable forenshield-fabric-gateway.service

cat <<EOF

Installed:
  forenshield-fabric-network.service  (boot: Fabric up + deployCC)
  forenshield-fabric-gateway.service  (boot: npm start :8088)

Start now:
  sudo systemctl start forenshield-fabric-network
  sudo systemctl start forenshield-fabric-gateway

Status:
  sudo systemctl status forenshield-fabric-network
  sudo systemctl status forenshield-fabric-gateway
  curl -s http://localhost:8088/health

Logs:
  journalctl -u forenshield-fabric-network -n 50
  journalctl -u forenshield-fabric-gateway -n 50
  tail -f /home/ubuntu/forenshield-infra/fabric/logs/fabric-network.log

Important: 퇴근 시 network.sh down 하지 말고 EC2 stop 만 사용하세요.
EOF
