# EKS 생명주기 + Wake Bootstrap 자동화

> **Park:** EKS 삭제 + RDS/EC2 stop  
> **Wake:** EKS 재생성 + Secret/Helm/Argo/Route53/Fabric SG + **RDS/EC2/Pod/Health 전부 자동**

---

## 1. 파일

| 파일 | 설명 |
|------|------|
| `terraform.tfvars` | subnet ID, RDS/EC2 ID 등 (Git 제외) |
| `secrets.tfvars` | DB/Redis/RabbitMQ/JWT/**Manifest PEM** 비밀 (Git 제외) |
| `wake_aws.tf` | RDS start/stop, Fabric EC2 start/stop |
| `modules/bootstrap/wake_verify.tf` | Pod Ready 대기, HTTPS health |
| `scripts/*.ps1` | AWS CLI / kubectl / curl 검증 |

---

## 2. 최초 1회

```powershell
cd Infra/terraform/eks-lifecycle
copy secrets.tfvars.example secrets.tfvars
# secrets.tfvars ← config/secrets.env 값 입력

$env:AWS_PROFILE = "forenshield"
terraform init
```

### 기존 클러스터 import

```powershell
terraform import 'aws_eks_cluster.this[0]' forenshield
terraform import 'aws_eks_node_group.frontend[0]' forenshield:frontend-ng
terraform import 'aws_eks_node_group.backend[0]' forenshield:backend-ng
terraform import 'aws_eks_node_group.ai_fastapi[0]' forenshield:ai-fastapi-ng
```

> 기존 운영 클러스터: `bootstrap_enabled=false` 로 EKS만 관리.  
> 완전 재생성(Wake) 후 `bootstrap_enabled=true`.

---

## 3. 퇴근 (Park)

```powershell
cd Infra/terraform/eks-lifecycle
.\eks-park.cmd
# 또는: powershell -ExecutionPolicy Bypass -File .\scripts\eks-park.ps1
```

**2단계로 실행됩니다:** (1) bootstrap(Helm/K8s) 제거 — EKS 유지, (2) EKS 삭제 + RDS/EC2 stop.

| 단계 | 자동 |
|------|------|
| Phase 1 `bootstrap_enabled=false` (EKS 유지) | Helm/K8s 리소스 삭제 |
| Phase 2 `eks_enabled=false` | EKS Control Plane + Node Group 삭제 |
| RDS `stop` | ✅ |
| Fabric EC2 `stop` (+ Gateway systemd stop 시도) | ✅ |

---

## 4. 출근 (Wake) — 전체 자동화

```powershell
cd Infra/terraform/eks-lifecycle
$env:AWS_PROFILE = "forenshield"

# 방법 A (권장): .cmd 래퍼 — ExecutionPolicy 영향 없음
.\eks-wake.cmd

# 방법 B: PowerShell에서 직접 (Bypass 필수)
powershell -ExecutionPolicy Bypass -File .\scripts\eks-wake.ps1
```

> `.\scripts\eks-wake.ps1` 만 실행하면 **ExecutionPolicy** 때문에 `PSSecurityException` 이 날 수 있습니다.

| 단계 | 자동 | 구현 |
|------|------|------|
| RDS `start` + available 대기 | ✅ | `scripts/start-rds.ps1` |
| Fabric EC2 `start` + SSM Gateway health | ✅ | `scripts/start-fabric-ec2.ps1` |
| EKS Cluster + Node Group | ✅ | `eks.tf` / `nodegroups.tf` |
| Secret / ConfigMap | ✅ | `k8s_base.tf` |
| RabbitMQ · Argo CD Helm | ✅ | `helm.tf` |
| Ingress · Route53 · Fabric SG 8088 | ✅ | `ingress.tf` / `aws_edge.tf` |
| Argo CD Application sync | ✅ | `kubernetes_manifest.argocd_app` |
| Pod Ready (rabbitmq, backend, frontend, ai-fastapi) | ✅ | `scripts/wait-k8s-ready.ps1` |
| Fabric EKS→Gateway health | ✅ | kubectl exec / curl pod |
| `https://forensheildjangdochi.com/health` | ✅ | `scripts/verify-app-health.ps1` |
| IRSA trust policy | ✅ | `patch-ebs-csi-trust.ps1` / `patch-irsa-trust.ps1` / `patch-alb-controller-trust.ps1` |
| Public subnet ELB tags | ✅ | `patch-subnet-tags.ps1` (Route53 15분 타임아웃 방지) |

`wake_run_id` 를 매 Wake마다 새로 넣어 provisioner가 재실행됩니다.

---

## 5. 전제 조건

| 항목 | 설명 |
|------|------|
| AWS CLI + `forenshield` profile | RDS/EC2/SSM/EKS |
| `kubectl` | Pod wait |
| Fabric EC2 SSM Online | `forenshield-ec2-fabric-role` |
| systemd (`install-systemd.sh` 1회) | EC2 reboot 후 Gateway 자동 기동 |
| `secrets.tfvars` | Wake 시 필수 (JWT + **Manifest PEM** 포함) |

### Manifest 서명 키 (park/wake)

kubectl 로만 Secret 을 만들면 **park 시 EKS 삭제와 함께 사라집니다.**

**권장:** `secrets.tfvars` 에 PEM 을 넣고, bootstrap 이 `app-secrets` 에
`MANIFEST_SIGNING_PRIVATE_KEY_PEM` / `MANIFEST_SIGNING_CERTIFICATE_PEM` 을 넣습니다.
backend `deployment` 는 이미 `app-secrets` 를 `envFrom` 하므로 **별도 `manifest-signing-credentials` Secret 불필요** 합니다.

```hcl
# secrets.tfvars (Git 금지)
manifest_signing_private_key_pem = <<-EOT
-----BEGIN PRIVATE KEY-----
...
-----END PRIVATE KEY-----
EOT
manifest_signing_certificate_pem = <<-EOT
-----BEGIN CERTIFICATE-----
...
-----END CERTIFICATE-----
EOT
```

live deployment 에 `manifest-signing-credentials` 가 **필수** 로 붙어 있으면 제거하세요
(Secret 없어도 CreateContainerConfigError). `app-secrets` 만 쓰면 됩니다.

```powershell
# 잘못된 secretRef 제거 (index 는 describe 로 확인)
kubectl get deploy backend -n forenshield -o jsonpath="{.spec.template.spec.containers[0].envFrom}" 
```

대안: AWS Secrets Manager + `MANIFEST_SIGNING_SECRET_ID` (IRSA 권한 필요). PEM 을 AWS 에만 둘 때.

---

## 6. 변수 (terraform.tfvars)

```hcl
rds_instance_identifier = "forenshield-db"
fabric_instance_id      = "i-08f10733c96e387fc"
fabric_health_url       = "http://10.0.10.224:8088/health"
app_health_url          = "https://forensheildjangdochi.com/health"
wake_automation_enabled = true
park_automation_enabled = true
```

자동화 끄기: `wake_automation_enabled = false` (Helm/Route53만 적용)

---

## 7. 주의

| 항목 | 설명 |
|------|------|
| apply 소요 시간 | Pod pull + ALB DNS 전파로 **15~25분** 가능 |
| 기존 ALB 이름 | `forenshield-k8s-app`, `forenshield-k8s-argocd` |
| Fabric SG / Route53 | 기존 리소스 있으면 import 필요 |
| EC2 IP 변경 시 | `fabric_health_url`, `fabric_anchor_url` 갱신 |

---

*마지막 업데이트: 2026-06-26*
