# ForenShield — Hyperledger Fabric (PoC)

**배포:** EC2 (EKS와 동일 VPC) · **문서:** [`../md/fabric.md`](../md/fabric.md)

## 빠른 시작 (EC2 SSM)

```bash
sudo bash scripts/install-ec2-prereqs.sh   # 최초 1회, 재접속
bash scripts/setup-all.sh
bash scripts/start-gateway.sh
bash scripts/print-be-config.sh
```

## 디렉터리

| 경로 | 설명 |
|------|------|
| `chaincode/anchor/` | 해시 앵커 chaincode (Go) |
| `gateway/` | REST `POST /api/v1/anchor` |
| `scripts/` | install · setup · start-gateway |
| `systemd/` | Gateway 자동 시작 (선택) |

BE 계약: [`backend/.../blockchain.md`](../../backend/backend-forensic/docs/integrations/blockchain.md)
