# ForenShield — 인프라 문서

## 문서 6개

| 문서 | 용도 | 언제 읽나 |
|------|------|-----------|
| **[handbook.md](./md/handbook.md)** | 운영 · 출퇴근 · 헬스체크 · 장애 | **매일** |
| **[deployment.md](./md/deployment.md)** | BE·FE EKS 연결 · CI/CD | 배포·최초 연결 |
| **[fabric.md](./md/fabric.md)** | Hyperledger Fabric · Gateway | 블록체인 |
| **[settings.md](./md/settings.md)** | Secret · ConfigMap · RDS | 설정 변경 |
| **[aws-infrastructure.md](./md/aws-infrastructure.md)** | VPC · EKS · RDS 구축 | 최초 구축 |
| **[gpu.md](./md/gpu.md)** | On-Prem GPU · RabbitMQ 큐 | AI 분석 |

```text
[처음] aws-infrastructure → settings → deployment → fabric
[매일] handbook
[배포] deployment (Git push → Argo CD)
```

## 코드 · 설정

| 경로 | 설명 |
|------|------|
| [config/](./config/) | K8s ConfigMap · Secret · `apply-settings.sh` |
| [fabric/](./fabric/) | chaincode · gateway · EC2 스크립트 |

## 현재 상태 (2026-06-24)

| 영역 | 상태 |
|------|------|
| EKS · RDS · S3 · ALB | ✅ |
| BE · FE · AI Argo CD | ✅ |
| Fabric 해시 앵커 E2E | ✅ EVD-74 |
| REPORT/MERKLE 앵커 | ⬜ |

## 공통

- Region: `ap-northeast-2` · Cluster: `forenshield` · Domain: `https://forensheildjangdochi.com`
- Fabric EC2: `10.0.10.224` (IP 변경 시 `config/k8s/app-config.yaml` 갱신)

---

*마지막 업데이트: 2026-06-24*
