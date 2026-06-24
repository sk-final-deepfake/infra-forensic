# ForenShield — Hyperledger Fabric (PoC)

**권장 배포:** AWS **EC2** (EKS와 동일 VPC) — GPU On-Prem과 분리  
**BE 연동:** 이미 `HttpBlockchainAnchorClient` 완료

## EC2 빠른 시작

```bash
sudo bash scripts/install-ec2-prereqs.sh   # 최초 1회, 재로그인
bash scripts/setup-all.sh
bash scripts/start-gateway.sh
bash scripts/print-be-config.sh            # EKS ConfigMap URL
```

가이드: [`../md/22.fabric-ec2-full-runbook.md`](../md/22.fabric-ec2-full-runbook.md) (콘솔·CLI 전체) · [`../md/21.fabric-gateway-quickstart.md`](../md/21.fabric-gateway-quickstart.md) (요약)

## 디렉터리

| 경로 | 설명 |
|------|------|
| `chaincode/anchor/` | 해시 앵커 chaincode (Go) |
| `gateway/` | REST `POST /api/v1/anchor` |
| `scripts/install-ec2-prereqs.sh` | EC2 Ubuntu 패키지 |
| `scripts/setup-all.sh` | Fabric test-network + deploy |
| `scripts/print-be-config.sh` | `BLOCKCHAIN_ANCHOR_URL` 출력 |
| `systemd/` | Gateway 자동 시작 (선택) |

## BE 계약

[`backend/.../integrations/blockchain.md`](../../backend/backend-forensic/docs/integrations/blockchain.md)
