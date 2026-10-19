# ECS Fargate web service with Terragrunt (dev + prod)

A containerised web app (nginx stands in for "the app") on **ECS Fargate**, behind an ALB, reading **one secret**
from Secrets Manager and wired to an **ElastiCache Redis replication group**, deployed with **Terragrunt** to two
environments. This is a **plan-only** deliverable: nothing is hosted, but everything is ready to `plan`.

```
                        Internet
                           │ 80 (HTTP)
                    ┌──────▼──────┐        public subnets (per AZ)
                    │     ALB     │
                    └──────┬──────┘
                           │ app port, SG → SG
                    ┌──────▼──────┐        private subnets (per AZ), egress via NAT (+ S3 gateway endpoint)
                    │ Fargate     │──── secretsmanager:GetSecretValue (execution role, injected as env var)
                    │ tasks (N)   │
                    └──────┬──────┘
                           │ 6379/TLS, SG → SG
                    ┌──────▼──────┐        isolated subnets (per AZ), NO route to the internet
                    │ Redis       │
                    │ primary+repl│
                    └─────────────┘
```

## Layout

```
root.hcl                  backend (S3) + provider generation, shared by every unit
_envcommon/*.hcl          one definition per unit (network, alb, redis, ...) - identical for dev and prod
live/<env>/env.hcl        ALL dev/prod differences live in this one file  (diff dev/env.hcl prod/env.hcl)
live/<env>/<unit>/        6 tiny terragrunt.hcl files per env: include root + include _envcommon/<unit>.hcl
modules/
  network/                VPC, 3 subnet tiers, NAT, S3 gateway endpoint   (wraps terraform-aws-modules/vpc)
  alb/                    ALB, SG, HTTP listener (404 by default, services add rules)
  ecs-cluster/            cluster + FARGATE / FARGATE_SPOT capacity providers
  secret/                 Secrets Manager secret (value managed out-of-band)
  redis/                  ElastiCache replication group, subnet/parameter group, SG
  ecs-service/            THE reusable module: task def, service, IAM, SG, target group, rule, autoscaling
```

Dependency order (Terragrunt works it out from `dependency` blocks): `network → alb, redis` and
`secret, ecs-cluster` (independent) `→ app`.

## How to plan it

Requirements: Terraform ≥ 1.10, a recent Terragrunt (developed with 1.1.6; needs `run --all` and `--backend-bootstrap`), AWS credentials for *any* account
(plan reads the account id for the state bucket name; it creates nothing besides the state bucket).

```bash
export AWS_PROFILE=...                 # or any other way of providing credentials
cd live/dev  && terragrunt run --all --backend-bootstrap plan    # all 6 dev units, in dependency order
cd live/prod && terragrunt run --all --backend-bootstrap plan
# or a single unit:
cd live/prod/app && terragrunt plan
```

* State: S3 bucket `tg-demo-tfstate-<account-id>-<region>`, key = unit path, native S3 locking
  (`use_lockfile`, no DynamoDB). `--backend-bootstrap` creates the bucket on first use.
* On a brand-new account the dependent units are planned with **mock outputs** of their dependencies
  (see `mock_outputs` in `_envcommon`), so `plan` works for the whole stack before anything exists.
  Mocks are only allowed for `init/validate/plan`, never for `apply`.
* Offline checks without credentials: `terraform init -backend=false && terraform validate` in each `modules/*` folder.

What I verified: all modules pass `terraform validate`, and `terragrunt run --all --backend-bootstrap plan` against a real
AWS account succeeded for all 12 units (6 dev + 6 prod). I did **not** `apply` anything.

## Requirement by requirement

### One reusable `ecs-service` module
Everything a service needs and nothing environment-specific: task definition, execution role vs task role, task SG,
target group + listener rule, service with circuit breaker/rollback, log group, autoscaling. A second service is another
`terragrunt.hcl` calling the same module. The ALB, cluster, Redis and secret are deliberately separate modules because
they are shared or have a different lifecycle than a service.

### Secret
`modules/secret` creates the secret (JSON, key `API_KEY`) with a placeholder value and `ignore_changes` on it, so the real
value is set out-of-band (`aws secretsmanager put-secret-value`) and never lands in state or a PR.
The service references `"<arn>:API_KEY::"` in the task definition `secrets`; ECS injects it as env var `API_KEY` at task
start. The **execution role** gets `secretsmanager:GetSecretValue` on exactly that ARN (nothing else). The **task role**
(what the app's own code uses) has no secret access.

### Redis connectivity - why the app can reach it
1. **Routing**: tasks (private subnets) and Redis (isolated subnets) are in the same VPC; the implicit `local` route covers
   every subnet, so no routes are needed. The isolated subnets have *no* default route, so Redis can't reach out and
   nothing outside can reach in.
2. **DNS**: `REDIS_HOST` is the replication group's *primary endpoint*, a DNS name resolving to a private IP
   (`enable_dns_support`). On failover the name moves to the new primary, so the app config never changes.
3. **Security groups, SG-to-SG, both directions**: task SG egress `6379 → redis SG`, redis SG ingress `6379 ← task SG`.
   Referencing the SG instead of a CIDR means autoscaling / new IPs / new tasks just work, and nothing else in the VPC
   can talk to Redis. Redis' SG has no other ingress rule and no egress at all. (Both rules are created by the
   `ecs-service` module via `peer_security_groups`; that also avoids a circular dependency between the Redis and app units.)
4. **TLS**: in-transit encryption is on, so the client must use `rediss://` (`REDIS_TLS=true` is passed to the app).
5. **How to prove it** once deployed (ECS Exec is enabled on the service):
   `aws ecs execute-command --cluster tg-demo-dev --task <id> --container tg-demo-dev-web --interactive --command "sh -c 'nc -zv $REDIS_HOST $REDIS_PORT'"`

### Autoscaling - what and why
Target tracking via Application Auto Scaling, three policies on one service (scale **out** if *any* wants more, scale **in**
only if *all* agree):

| Signal | Why | dev | prod |
|---|---|---|---|
| `ALBRequestCountPerTarget` | A web app is I/O-bound; request rate is the *leading* indicator and scales before CPU saturates | off | 500 req/task |
| CPU | Backstop for CPU-heavy requests | 70 % | 55 % (headroom: Fargate needs ~1-2 min to add a task) |
| Memory | Guard for caches / leaks; memory doesn't shrink, so it's a safety net, not the main driver | off | 75 % |

Scale out fast (30-60 s cooldown), scale in slowly (5-10 min) to avoid flapping. For the real app I'd load-test to pick the
requests-per-target number; 500 is a placeholder. If the app were queue-driven, the metric would be queue depth per task.

### Prod differs from dev

| | dev | prod |
|---|---|---|
| AZs / NAT | 2 AZ, 1 NAT | 3 AZ, 1 NAT per AZ |
| Tasks | 1-3, 0.25 vCPU / 512 MiB | 3-30 (≥1 per AZ), 0.5 vCPU / 1 GiB |
| Capacity | 100 % Fargate Spot | base 3 on-demand, above that 75 % Spot |
| Deploy | min healthy 50 % | min healthy 100 % / max 200 % (rolling, no capacity dip) |
| Redis | 1 × t4g.micro, no failover | 3 × r7g.large, Multi-AZ + automatic failover, 7-day snapshots |
| ALB | no deletion protection | deletion protection |
| Observability | 7-day logs | 90-day logs, Container Insights |
| Secret | deleted immediately | 30-day recovery window |

Both have: encryption at rest + in transit for Redis, private tasks, deployment circuit breaker with automatic rollback.

## Trade-offs

* **ALB and HTTP only**: the brief doesn't mention a load balancer. I added an ALB because a web app needs an entry point and
  because request-count autoscaling needs one. It serves plain HTTP (no domain/certificate needed to plan); HTTPS is listed
  under "What I'd add". Running without it means removing `modules/alb` and the ALB wiring in `ecs-service`
  (target group, listener rule, `load_balancer` block, request-count scaling policy).

* **Terragrunt `_envcommon` + one `env.hcl`** instead of copying units per env: no drift, and the dev/prod diff is one file.
  Cost: one level of indirection to learn (a unit is "include root + include envcommon").
* **Community VPC module** (`terraform-aws-modules/vpc`) instead of hand-rolling: well tested and fast, but a third-party
  dependency and more surface than I use. Everything else is hand-written to keep it readable.
* **Secret value out-of-band**: nothing sensitive in code or state, but a human/pipeline step is needed after first apply.
* **NAT for AWS API access** (ECR, Secrets Manager, Logs) instead of interface VPC endpoints: simpler and cheaper at
  small scale; per-AZ NAT is the main fixed prod cost. The S3 gateway endpoint is free and already offloads image layers.
* **Spot in prod above the baseline**: ~70 % cheaper for burst capacity; tasks must tolerate a 2-minute reclaim notice.
* **Native S3 locking** (needs Terraform ≥ 1.10) instead of DynamoDB: one less resource, newer feature.
* **One state per unit** (blast radius, speed) at the price of cross-unit plumbing via `dependency`.
* **Image tag, not digest**, for nginx; fine for a demo, not for prod.
* **Prod and dev in one account/region** in this repo; the layout supports separate accounts (see below).

## What I'd add with more time

* **Separate AWS accounts** for dev/prod (per-env `assume_role` in `root.hcl`, `allowed_account_ids`), OIDC roles for CI.
* **CI/CD**: PR runs `terragrunt run --all plan` and posts it; apply on merge to main for dev, manual approval for prod.
  Image build/push (ECR, scan, immutable digests) and deploys by updating the task definition image.
* **Alarms + dashboards**: ALB 5xx / target response time, unhealthy hosts, ECS running vs desired, Redis CPU / memory /
  evictions / replication lag, autoscaling at max; SNS → Slack/PagerDuty.
* **Security hardening**: WAF on the ALB, interface VPC endpoints (ECR, Secrets Manager, Logs) so tasks need no NAT egress,
  CMK for secrets/Redis/logs, VPC flow logs, read-only root FS + non-root user, ALB access logs, Redis AUTH/RBAC and secret rotation.
* **HTTPS / edge**: ACM certificate + HTTPS listener with 80→443 redirect (TLS 1.2/1.3 policy), Route 53 record, CloudFront in front.
  Left out on purpose: it needs a domain and a certificate, and the brief is plan-only.
* **Scaling**: scheduled scaling for known peaks, load-tested targets.
* **Deployments**: CodeDeploy blue/green with canary, or ECS native blue/green.
* **Tests/policy**: `terraform test` / Terratest on the modules, tflint, checkov/trivy, infracost in PRs, pre-commit.

## A note on how this was made

I built this with AI assistance (Claude Code), working from my instructions and reviewing the result. I want to be upfront about that.

My background is Terraform and EKS/Kubernetes. Terragrunt and ECS were new to me (although I knew the purpose/concepts), so I used this task to learn them:
I went through the code step by step, asked for explanations of each concept (units, `include`/`_envcommon`, `dependency`,
remote state, task vs execution role, capacity providers, autoscaling policies and
mapped them to what I already know from Kubernetes. I can walk through and explain every part of this repo, including the
trade-offs above, and I'm happy to go through it in the interview.
