# Hyperledger Fabric — 구축 · 연동 · 운영

> ForenShield **해시 앵커** PoC. 코드: [`Infra/fabric/`](../fabric/) · BE HTTP 계약: [`backend/.../blockchain.md`](../../backend/backend-forensic/docs/integrations/blockchain.md)

---

## 1. 한 줄 요약

- **파일은 S3/RDS**, Fabric ledger에는 **SHA-256 해시만** 기록
- **BE**는 Fabric SDK 없이 Gateway **HTTP**만 호출 (`HttpBlockchainAnchorClient`)
- **INF**가 EC2에 Fabric + Gateway(`:8088`) 운영
- **PoC 완료:** `EVIDENCE_HASH` 업로드 앵커 (EVD-74 `ANCHORED`)

---

## 2. 아키텍처

```text
[EKS backend] ──POST /api/v1/anchor──► [EC2 Gateway :8088]
                                              │
                                              ▼
                                    [peer/orderer + chaincode anchor]
                                              │
                                              ▼
                                    channel forenshield-evidence
```

| 앵커 타입 | 트리거 | ledger 키 | PoC |
|-----------|--------|-----------|-----|
| `EVIDENCE_HASH` | 업로드 완료 | `EVIDENCE:{id}` | ✅ |
| `REPORT_HASH` | PDF 생성 | `REPORT:{id}` | ⬜ |
| `MERKLE_ROOT` | 일일 배치 | `MERKLE:{date}` | ⬜ |

**Fabric이 아닌 것:** RabbitMQ(AI 큐), GPU(추론), S3/RDS(저장)

---

## 3. 현재 인프라

| 항목 | 값 |
|------|-----|
| EC2 | `forenshield-fabric-poc` · `i-08f10733c96e387fc` |
| Private IP | **`10.0.10.224`** (변경 시 ConfigMap 갱신) |
| SG | `forenshield-sg-fabric` · `sg-0992309b24773bb7f` |
| 인바운드 8088 | EKS **클러스터 SG** `sg-072ccb770bbf72e1c` (eks-node SG만으로는 연결 안 됨) |
| Fabric | 2.5.15 · test-network PoC |
| 접속 | SSM Session Manager (SSH 불필요) |

---

## 4. 디렉터리

| 경로 | 설명 |
|------|------|
| `chaincode/anchor/anchor.go` | `AnchorHash`, `GetAnchor` |
| `gateway/src/server.js` | REST `/health`, `/api/v1/anchor` |
| `gateway/src/fabric.js` | Fabric Gateway SDK submit |
| `scripts/setup-all.sh` | Fabric up + chaincode deploy + `.env` |
| `scripts/start-gateway.sh` | Gateway 기동 |
| `scripts/print-be-config.sh` | BE ConfigMap URL 출력 |

Gateway는 test-network **Org1 Admin** 인증서 사용 (PoC 한계 — 프로젝트 범위 OK).

---

## 5. 최초 구축 (EC2)

### 5.1 사전 조건

- EKS와 **동일 VPC**, Private subnet, **NAT** (SSM·git·npm용)
- IAM: `forenshield-ec2-fabric-role` + SSM
- SG: `forenshield-sg-fabric` — 8088 from **EKS cluster SG**

### 5.2 EC2 생성 (콘솔 요약)

1. Ubuntu 22.04 · `t3.medium` · **키 페어 없음**
2. Private subnet · **퍼블릭 IP 없음**
3. SG: `forenshield-sg-fabric` · IAM: `forenshield-ec2-fabric-role`
4. 이름: `forenshield-fabric-poc` · 30GB gp3

### 5.3 SSM 접속

콘솔: EC2 → 연결 → Session Manager  
CLI: `aws ssm start-session --target i-08f10733c96e387fc`

### 5.4 설치 (SSM 세션)

```bash
cd ~
git clone <infra-repo-url> forenshield-infra
cd forenshield-infra/fabric

sudo bash scripts/install-ec2-prereqs.sh
# SSM 세션 종료 후 재접속 (docker 그룹)

bash scripts/setup-all.sh          # 30~60분
bash scripts/start-gateway.sh
bash scripts/print-be-config.sh    # BLOCKCHAIN_ANCHOR_URL 복사
```

### 5.5 EKS 연결

`config/k8s/app-config.yaml`:

```yaml
BLOCKCHAIN_ANCHOR_ENABLED: "true"
BLOCKCHAIN_ANCHOR_MODE: "http"
BLOCKCHAIN_ANCHOR_URL: "http://<EC2_PRIVATE_IP>:8088/api/v1/anchor"
BLOCKCHAIN_ANCHOR_NETWORK: "hyperledger-fabric-forenshield"
```

```bash
kubectl apply -f config/k8s/app-config.yaml -n forenshield
kubectl rollout restart deployment/backend -n forenshield
```

### 5.6 SG 수정 (연결 안 될 때)

```bash
aws ec2 authorize-security-group-ingress \
  --group-id sg-0992309b24773bb7f \
  --ip-permissions "IpProtocol=tcp,FromPort=8088,ToPort=8088,UserIdGroupPairs=[{GroupId=sg-072ccb770bbf72e1c,Description=EKS-cluster-SG-to-Gateway}]" \
  --region ap-northeast-2
```

---

## 6. 매일 기동 (이미 구축된 경우)

[handbook.md § 출근](./handbook.md#53-fabric-ec2) 참고.

```bash
cd ~/forenshield-fabric-runtime/fabric-samples/test-network
./network.sh up -ca
./network.sh deployCC -ccn anchor \
  -ccp ~/forenshield-infra/fabric/chaincode/anchor \
  -ccl go -c forenshield-evidence
cd ~/forenshield-infra/fabric && bash scripts/start-gateway.sh
```

**Gateway systemd (선택):**

```bash
sudo cp systemd/forenshield-fabric-gateway.service /etc/systemd/system/
sudo systemctl enable --now forenshield-fabric-gateway
```

Fabric `network.sh up`은 여전히 수동.

---

## 7. E2E 검증

```bash
# EKS → Gateway
kubectl exec -n forenshield deploy/backend -- curl -sf http://10.0.10.224:8088/health

# 앱 API
curl -s "https://forensheildjangdochi.com/api/v1/evidences/74/blockchain" \
  -H "Authorization: Bearer <token>"
```

기대: `status: "ANCHORED"`, `transactionHash`, `blockNumber`

---

## 8. 트러블슈팅

| 증상 | 원인 | 해결 |
|------|------|------|
| curl timeout (EKS→EC2) | SG가 eks-node만 허용 | cluster SG → 8088 추가 |
| `evidenceId required` | 구 backend body | `BlockchainAnchorRequest` 배포 |
| CrashLoop `c3f14d4` | Lombok+생성자 충돌 | `0c22475` 이상 |
| curl exit 23 + 200 | Git Bash | 200이면 성공 |
| 앵커 FAILED | Gateway/Fabric down | up + deployCC + gateway |
| DB ANCHORED ≠ chain | `network.sh down` | down 금지 |
| Gateway 로그 없음 (성공) | server.js 설계 | 실패만 로그 — 정상 |

---

## 9. PoC 한계 (발표용)

- Admin 키가 EC2 Gateway에 있음 → EC2 침해 시 ledger 쓰기 가능
- 단일 org/peer/orderer, API Key 없음, HTTP 평문
- backend가 txHash를 Fabric에서 재검증하지 않음
- `REPORT_HASH` · `MERKLE_ROOT` · Explorer 미완

운영 시: invoke 전용 identity, Secrets Manager, mTLS, multi-org.

---

## 10. BE·INF 계약 요약

**Gateway POST** `/api/v1/anchor`:

```json
{
  "subjectHash": "<sha256>",
  "anchorType": "EVIDENCE_HASH",
  "evidenceId": "74",
  "clientId": "forenshield-be"
}
```

**응답:**

```json
{
  "transactionHash": "<txId>",
  "blockNumber": 8,
  "network": "hyperledger-fabric-forenshield"
}
```

체인코드: 같은 `evidenceId` 재앵커 시 **멱등** (첫 해시 유지).

---

*마지막 업데이트: 2026-06-24*
