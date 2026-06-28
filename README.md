# Cloud-Native Healthcare System

**A legacy PHP Hospital Management System, modernized into a production-grade, cloud-native platform on AWS.**

Built solo as a DevOps Engineering capstone project — Digilians Program, Software Development Track.

[![CI](https://github.com/ahmedswilam141/hospital-devops-modernization/actions/workflows/pr-validation.yml/badge.svg)](https://github.com/ahmedswilam141/hospital-devops-modernization/actions)

---

## What This Project Is

This repository documents the transformation of a single-server PHP application — running manually, with no automation, no fault tolerance, and no observability — into a fully containerized, orchestrated, and continuously delivered system on Amazon EKS.

The application logic (patient records, appointments, doctor management, medical reports) is the **original legacy codebase**, preserved as-is. Every change in this repository is at the **infrastructure and operations layer** — this is a "lift and modernize" project, not a rewrite.

**Everything below reflects the real, current state of the project — including what's finished, what's in progress, and what's planned next.**

---

## Project Status

| Area | Status | Notes |
|---|---|---|
| Application containerization | ✅ Done | 3 production Docker images (frontend, backend, nginx) |
| Infrastructure as Code (Terraform) | ✅ Done | 52 AWS resources, 7 modules, remote state |
| Kubernetes orchestration (EKS) | ✅ Done | Rolling updates, probes, anti-affinity, autoscaling |
| CI/CD pipeline (Jenkins) | ✅ Done | 6-stage pipeline, confirmed passing builds |
| CI/CD pipeline (GitHub Actions) | ✅ Done | PR validation — scan, build-test, manifest-lint |
| Security (IRSA, Secrets Manager, Trivy) | ✅ Done | No static credentials anywhere in the system |
| Database / Sessions / Storage (RDS, Redis, S3) | ✅ Done | Stateless pods, managed AWS services |
| Configuration management (Ansible) | ✅ Done | Idempotent Bastion provisioning |
| **Observability (Prometheus + Grafana + Loki)** | 📋 **Planned** | Helm provider is wired into Terraform; charts not yet deployed |
| **HTTPS / TLS termination** | 📋 **Planned** | Currently HTTP via NLB; needs ALB + ACM certificate |
| **AI Clinical Assistant** | 🔄 **In Design** | Architecture defined (AWS Bedrock); not yet implemented |
| Password hashing | 📋 **Planned** | Legacy app stores passwords in plaintext — known gap, not yet fixed |

This table is the single source of truth for project status. If a feature isn't marked ✅ Done, it is not running in production — and that's stated here on purpose rather than implied otherwise.

---

## Architecture

```
                              Internet
                                 │
                                 ▼
                  AWS Network Load Balancer (public subnet)
                                 │
                                 ▼
                  ┌──────────────────────────────┐
                  │   EKS Cluster (K8s 1.31)      │
                  │   private subnets, 2 AZs      │
                  │                                │
                  │   nginx (×2) ──┬─ frontend (×2)│
                  │                └─ backend (×1) │
                  └──────┬─────────────────┬───────┘
                         │                 │
              ┌──────────▼───────┐  ┌──────▼────────┐
              │  RDS MySQL 8.0    │  │ ElastiCache    │
              │  (private subnet) │  │ Redis (sessions)│
              └───────────────────┘  └────────────────┘
                         │
                  ┌──────▼────────┐
                  │  S3 (PDF reports) │
                  └───────────────┘
```

- **Public subnet:** NLB + Bastion host only
- **Private subnets:** EKS nodes, RDS, ElastiCache — no direct internet access
- **Single entry point:** nginx routes `/admin/*` → backend, everything else → frontend
- **No static credentials:** pods authenticate to AWS via IRSA (IAM Roles for Service Accounts)

---

## Tech Stack

| Layer | Tools |
|---|---|
| Cloud | AWS (EKS, RDS, ElastiCache, S3, ECR, Secrets Manager, VPC) |
| IaC | Terraform ≥1.7, 7 modules, S3 remote state + DynamoDB locking |
| Containers | Docker, 3 images (PHP 8.1 + Apache, nginx 1.25-alpine) |
| Orchestration | Kubernetes 1.31 (EKS) |
| CI/CD | Jenkins (Kubernetes pod agent), GitHub Actions |
| Security | Trivy, IAM IRSA/OIDC, Secrets Manager, nginx rate limiting |
| Config Management | Ansible (Bastion provisioning) |
| Planned Observability | Prometheus, Grafana, Loki (Helm) |
| Planned AI | AWS Bedrock (Claude) |

---

## Repository Structure

```
.
├── .github/workflows/pr-validation.yml   # GitHub Actions — PR validation (3 jobs)
├── Jenkinsfile                           # 6-stage CI/CD pipeline (Kubernetes pod agent)
├── ansible/
│   ├── inventory.ini                     # Bastion host inventory
│   └── playbook-bastion.yml              # Idempotent Bastion configuration
├── app/
│   ├── Backend/                          # Admin portal (PHP) — legacy app, modernized
│   └── Frontend/                         # Patient/doctor portal (PHP) — legacy app, modernized
├── ci/
│   └── Dockerfile.jenkins-agent          # Custom Jenkins agent (Docker CLI, kubectl, AWS CLI, Trivy)
├── docker/
│   ├── Dockerfile.backend
│   ├── Dockerfile.frontend
│   ├── Dockerfile.nginx
│   ├── apache-backend.conf / apache-frontend.conf
│   ├── php-sessions.ini                  # Redis session handler config — enables horizontal scaling
│   └── php-uploads.ini
├── k8s/
│   ├── namespaces/hospital.yaml
│   ├── frontend/                         # Deployment, Service, ConfigMap, HPA (one resource per file)
│   ├── backend/                          # Deployment, Service, ConfigMap (one resource per file)
│   ├── nginx/                            # Deployment, Service, ConfigMap (one resource per file)
│   ├── redis/                            # Optional in-cluster Redis — StatefulSet + Service (local testing only)
│   └── secrets/external-secrets.yaml     # SecretStore + ExternalSecret + ServiceAccount — kept together
│                                          # (these three are tightly coupled and only meaningful as a unit)
├── nginx/
│   ├── nginx.conf                        # Reference config (also embedded in k8s/nginx ConfigMap)
│   └── proxy_params
├── scripts/
│   ├── deploy-infrastructure.sh
│   ├── fix-mysql.sh
│   ├── schema.sql                        # Canonical database schema
│   └── setup-local.sh
├── terraform/
│   ├── main.tf, variables.tf, outputs.tf, backend.tf
│   ├── terraform.tfvars.example
│   └── modules/
│       ├── vpc/      # VPC, subnets, IGW, NAT, route tables
│       ├── eks/       # Cluster, managed node group, OIDC provider
│       ├── rds/       # MySQL 8.0, subnet group, Secrets Manager
│       ├── redis/     # ElastiCache cluster, subnet group
│       ├── s3/        # Report storage bucket
│       ├── ecr/       # 3 private container registries
│       └── bastion/   # EC2 jump host
├── docker-compose.yml                    # Local development environment
└── .env.example
```

**K8s manifest style:** every Deployment, Service, ConfigMap, StatefulSet, and HPA lives in its own file (one resource per file), consistently across `frontend/`, `backend/`, `nginx/`, and `redis/`. The one exception is `k8s/secrets/external-secrets.yaml`, which intentionally keeps `SecretStore` + `ExternalSecret` + `ServiceAccount` together — these three only make sense as a single unit and splitting them would hurt readability, not help it.

---

## How the Pipeline Works

```
git push (master)
       │
       ├──► GitHub Actions (PR validation — fast, ~3 min)
       │     ├─ trivy-scan      (filesystem CVE scan)
       │     ├─ build-test      (docker build, no push)
       │     └─ manifest-lint   (kubectl --dry-run=client)
       │
       └──► Jenkins (full pipeline — ~5 min, runs inside EKS)
             1. Checkout
             2. Security Scan      (Trivy — blocks on CRITICAL CVE)
             3. Build Images       (Docker, via Docker-in-Docker pod)
             4. Push to ECR        (versioned + :latest tags)
             5. Deploy to EKS      (kubectl rollout restart — zero downtime)
             6. Verify             (fails build if any pod isn't Running)
```

Jenkins runs each pipeline as a temporary Kubernetes pod with three containers: `jnlp` (Jenkins agent), `tools` (custom image with Docker CLI/kubectl/AWS CLI/Trivy pre-installed), and `dind` (isolated Docker daemon for image builds — avoids mounting the host Docker socket).

---

## Key Engineering Decisions

- **EKS over ECS** — Kubernetes skills and manifests are portable across any cloud provider.
- **Jenkins *and* GitHub Actions** — GitHub Actions gives fast, free pre-merge feedback; Jenkins runs the authoritative post-merge deploy inside the cluster's own trust boundary.
- **Redis for PHP sessions** — `php-sessions.ini` redirects session storage to ElastiCache with zero application code changes, which is what makes running multiple frontend/backend replicas possible at all.
- **IRSA over static AWS keys** — every pod authenticates to AWS using short-lived, auto-rotated IAM tokens via OIDC. There are no `AWS_ACCESS_KEY_ID` values anywhere in this repository or the running cluster.
- **Terraform remote state (S3 + DynamoDB)** — infrastructure is reproducible from any machine, with locking to prevent concurrent-apply corruption.

---

## Known Gaps (Honest List)

These are real, current limitations — not hidden, not yet fixed:

- **Passwords are stored in plaintext** in the legacy application's database layer. This needs `bcrypt`/`password_hash()` and a migration script before any real-world deployment.
- **No HTTPS yet.** The NLB serves HTTP only. Needs an ALB + ACM certificate for TLS termination.
- **No observability stack deployed yet.** Prometheus/Grafana/Loki are planned (the Helm Terraform provider is already declared), but not yet applied to the cluster.

---

## Roadmap

| Priority | Item |
|---|---|
| High | HTTPS / TLS termination (ALB + ACM) |
| High | Password hashing migration (bcrypt) |
| High | AI Clinical Assistant — Phase 1 (AWS Bedrock symptom triage) |
| Medium | Deploy Prometheus + Grafana + Loki via Helm |
| Medium | Horizontal Pod Autoscaler tuning under real load |
| Medium | ArgoCD — replace `kubectl rollout restart` with GitOps sync |
| Low | Multi-region disaster recovery |

---

## Running Locally

```bash
cp .env.example .env        # edit values if you want something other than the defaults
docker-compose up --build   # first run — builds the images
docker-compose up -d        # subsequent runs — detached
```

Verify everything is healthy:

```bash
docker-compose ps                          # all containers should show "healthy"
curl http://localhost/health.php           # frontend health check
curl http://localhost/admin/health.php     # backend health check
curl http://localhost/nginx-health         # nginx health check
```

This spins up frontend, backend, nginx, and a local MySQL container for development — independent of the AWS infrastructure.

---

## Author

**Ahmed Hosam ELdien Reyad Swilam**
DevOps Engineer — Digilians Program, Software Development Track

This project was built solo, by design — to gain hands-on depth across the full DevOps lifecycle: infrastructure, containers, CI/CD, security, and (in progress) observability — rather than owning one slice of a team effort.
