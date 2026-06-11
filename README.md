# ForenShield AI — 인프라 · 배포 문서

ForenShield AI 프로젝트의 **인프라 구축 · 앱 배포 · GPU 운영 · E2E 검증** 가이드 모음입니다.  
번호 순서대로 진행하는 것을 권장합니다.

---

## 문서 목록

| # | 문서 | 설명 |
|---|------|------|
| **1** | [GPU 자원 활용 가이드](./1.gpu_use_guide.md) | 단일 GPU 스케줄링, RabbitMQ 순차 처리, OOM 대응, Phase 1 원격 테스트 |
| **2** | [AWS 인프라 구축 (Terraform)](./2.Terraform%20architecture.md) | VPC · RDS · EKS · VPN · ALB 등 14단계 구축 순서 |
| **3** | [환경변수 · Secret 관리](./3.settings.md) | `.env.example`, K8s Secret/ConfigMap, IRSA |
| **4** | [데이터 레이어 배포](./4.data-layer-deploy.md) | RDS PostgreSQL, RabbitMQ, S3 (evidence/models) |
| **5** | [프론트엔드 배포](./5.frontend-deploy.md) | Next.js + Nginx 사이드카, ALB, Ingress |
| **6** | [백엔드 배포](./6.backend-deploy.md) | Spring Boot, Redis, 큐 발행 |
| **7** | [AI 분석 서버 배포](./7.ai-deploy.md) | EKS AI FastAPI + On-Prem GPU Gateway |
| **8** | [E2E 통합 테스트](./8.test.md) | 프로덕션 URL 기준 전체 파이프라인 검증 |
| **9** | [백엔드·프론트엔드 인프라 연결 (통합본)](./md/9.connect-backend-frontend.md) | 연결 따라하기(1~8장) + 트러블슈팅(9장) + 명령어(10장) + 체크리스트(11장) |
| **10** | [트러블슈팅 (→ 9장 통합)](./md/10.troubleshooting-2026-06-10.md) | 9번 문서로 리다이렉트 |
| **11** | [명령어 정리 (→ 9장 통합)](./md/11.commands-2026-06-10.md) | 9번 문서로 리다이렉트 |

---

## 권장 진행 순서

```text
[1] GPU Phase 1 (On-Prem)     ← AWS 전 선행
[2] Terraform / AWS 인프라
[3] 환경변수 · Secret 정의
[4] 데이터 레이어 (RDS · MQ · S3)
[5] RabbitMQ → [7] AI FastAPI → [6] Backend → [5] Frontend
[8] E2E 통합 테스트
```

### Phase 요약

| Phase | 문서 | 완료 기준 |
|-------|------|-----------|
| Phase 1 | 1 | `nvidia-smi`, 원격 `/health` |
| Phase 3 | 2, 3, 4 | VPC, RDS, S3, VPN |
| Phase 4 | 5, 6, 7 | EKS Pod 전체 Running |
| Sprint 4 | 8 | E2E 해피 패스 무오류 |

---

## 공통 정보

| 항목 | 값 |
|------|-----|
| Region | `ap-northeast-2` (서울) |
| Namespace | `forenshield` |
| EKS Cluster | `forenshield` |
| GPU | On-Prem NVIDIA RTX 5080 |

---

*마지막 업데이트: 2026-06-10*
