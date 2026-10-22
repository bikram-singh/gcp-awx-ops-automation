# 🏛️ High-Level Design: Ansible Ops Platform on GCP

> 🏠 [README](../README.md) · 🏛️ [HLD](HLD.md) · 🗺️ [Architecture](ARCHITECTURE.md) · 🎬 [Demo](DEMO.md) · 💥 [Teardown](TEARDOWN.md) · 📸 [Snapshots](SNAPSHOTS.md)

| | |
|---|---|
| Author | Bikram |
| Status | v1.0, all phases implemented and run end to end (the optional HTTPS entry and chat notifications are off until configured; both were proven on this build) |
| Scope | Platform to provision, deliver and operate infrastructure using Terraform, GitHub Actions and AWX |

Diagrams: [ARCHITECTURE.md](ARCHITECTURE.md). Per-phase detail: PHASE2 to PHASE8, INGRESS. Demo: [DEMO.md](DEMO.md). Teardown: [TEARDOWN.md](TEARDOWN.md).

## 🎯 1. Problem statement

Infrastructure teams build servers with IaC but still run daily operations by hand: patching, hardening, access, health checks, incident fixes. This causes:

- inconsistent configuration (snowflake servers)
- slow, manual, error-prone change execution
- no central audit trail of who changed what
- shared credentials passed around between engineers
- slow response to common incidents (a VM stopped, a new VM nobody configured)

## ✅ 2. Goals and non-goals

**Goals**

1. Provision the whole platform as code, with no console clicks.
2. Run all routine operations through one control plane with RBAC, audit and credential isolation.
3. Make operations self-service, scheduled or event-driven.
4. Use keyless authentication from CI to cloud.
5. Manage the automation platform itself as code (config-as-code).
6. Gate every change with automated quality checks.

**Non-goals**

- Application CI/CD for business apps.
- Multi-region HA of AWX (single region, single replica in the lab).
- Windows fleet management.

## 🏗️ 3. Logical architecture

See the platform diagram in [ARCHITECTURE.md](ARCHITECTURE.md) (`img/platform.png`). In short:

- **GitHub** holds Terraform, Ansible playbooks, roles, AWX configuration and the execution-environment definition. GitHub Actions authenticates to GCP through Workload Identity Federation.
- **GCP** hosts a private VPC, a private GKE cluster running AWX (operator install), Cloud SQL (private IP), Artifact Registry and a fleet of private VMs.
- **AWX** is the operations plane: inventory, credentials, job templates, a staged patching workflow, schedules, RBAC and notifications.
- **Event path:** the Admin Activity audit log feeds two log sinks (VM stopped, VM created) into one Pub/Sub topic. A small bridge in the cluster pulls events and launches the matching AWX template.
- **Optional HTTPS entry:** a global load balancer with a Google-managed certificate and a Cloud Armor allowlist, for people only. Pipelines keep using the private tunnel.

## 🧩 4. Components

| Component | Purpose | Notes |
|---|---|---|
| Terraform `platform` | VPC, NAT, firewall, private GKE, Cloud SQL, Secret Manager, Artifact Registry | State in GCS, prefix `platform` |
| Terraform `awx` | AWX operator (Helm) and the AWX instance | Reads `platform` outputs; prefix `awx` |
| Terraform `fleet` | Labelled private VMs, inventory and snapshot service accounts, conditional IAM | Prefix `fleet` |
| Terraform `selfheal` | Pub/Sub topic, two log sinks, bridge deployment, bridge service accounts | Prefix `selfheal` |
| Terraform `ingress` | Optional load balancer, certificate, Cloud Armor allowlist | Off unless a domain and allowlist are set |
| AWX | Control plane | Upstream of Ansible Tower / Automation Controller |
| Execution environment | Container image with ansible-core, Google libraries and collections | Built by `ansible-builder` in `ee-build`, pulled from Artifact Registry |
| Dynamic inventory | VMs from the Compute API, grouped by label | `google.cloud.gcp_compute`, keyless |
| Roles | `roles/cis`: CIS-aligned hardening, tested with Molecule | |
| GitHub Actions | `infra`, `awx-config`, `ops-trigger`, `daily-report`, `lint`, `ee-build` | |

## 🧠 5. Key design decisions

| Decision | Choice | Reason |
|---|---|---|
| Controller | AWX via the operator | Same engine as Tower/Controller, free, Kubernetes-native |
| Database | Cloud SQL PostgreSQL, private IP | Managed backups; stateless AWX pods |
| Terraform split | Five stacks | Avoids provider-before-cluster problems; small blast radius per stack |
| CI auth | Workload Identity Federation | No long-lived keys |
| AWX access from CI | Keyless login plus a `kubectl` tunnel | AWX never needs a public address |
| Event ingestion | Pub/Sub **pull** by an in-cluster bridge | No inbound path to AWX, no load balancer, nearly free. Replaces the originally planned Cloud Function plus webhook |
| New-VM callback | Second log sink, same bridge | Reuses the heal path instead of a callback endpoint (about $18 a month saved) |
| AWX config | Config as code with the `awx.awx` collection | Reproducible, reviewable, adopts hand-built objects by name |
| Least privilege for events | AWX user `selfheal` may run only two templates | Compromise of the bridge cannot reach production patching |
| IAM scoping | Conditional bindings by VM name | AWX can start and snapshot only fleet VMs, never GKE nodes |
| Public entry | Optional, allowlist mandatory, HTTPS only | An admin tool should not be open to the internet |

## 🔒 6. Security design

- **Identity:** GitHub to GCP with OIDC, restricted to this repository by an attribute condition. Pods use Workload Identity. No JSON keys anywhere.
- **Least privilege:** separate service accounts for the deployer, GKE nodes, the fleet, inventory and snapshots, and the bridge. Conditional IAM limits start and snapshot rights to named VMs.
- **Secrets:** generated by Terraform into Secret Manager or Kubernetes secrets; machine credentials live only inside AWX. Webhook URLs are never logged.
- **Network:** private nodes, private Cloud SQL, no public IPs on VMs, SSH only from the IAP range, Cloud NAT for egress.
- **Access control:** AWX teams separate looking (auditor), operating (execute on safe templates) and approving production (approval role on the workflow).
- **Hardening:** `roles/cis` applies SSH, kernel network, filesystem and permission baselines, validated with `sshd -t` before install.
- **Audit:** AWX job history and activity stream, Cloud Audit Logs, GitHub Actions run history.

## 🛠️ 7. Operational use cases

| Use case | Status |
|---|---|
| Rolling OS patching with approval gate (workflow 50) | Done |
| Pre-patch disk snapshots | Done |
| CIS baseline hardening, with a dry-run template | Done |
| Daily health and capacity report | Done (scheduled job and `daily-report` workflow) |
| Self-healing of stopped VMs | Done |
| Provisioning callback for new VMs | Done |
| Failure, success and approval alerts to a chat webhook | Done, enabled by a secret; proven with Discord |
| Role-based access (look, operate, approve) | Done |
| Scheduled stop/start of dev VMs, certificate expiry checks, application deployment | Not built |

## 🚚 8. Delivery pipelines

| Workflow | Trigger | Steps |
|---|---|---|
| `infra` | PR or push touching `terraform/` | fmt, validate, plan on PR; apply stack by stack on main behind the `production` environment |
| `lint` | PR or push touching `ansible/`, `roles/` | ansible-lint (production profile), Molecule test of each role |
| `ee-build` | change in `execution-env/` | ansible-builder, push to Artifact Registry |
| `awx-config` | change in `ansible/awx-config/` | apply AWX objects through the API |
| `ops-trigger` | manual | launch a template or workflow and wait; real patching and hardening need a production reviewer |
| `daily-report` | schedule or manual | run the health report and publish a summary table |

## 🛡️ 9. Failure handling and resilience

- Rolling updates with `serial` and `max_fail_percentage`; hardening runs one host at a time and stops on the first failure.
- Snapshot before patching; the staged workflow stops before production if dev fails or the approval is denied.
- AWX pods are stateless; the database is on Cloud SQL with automated backups.
- The bridge acknowledges an event only after AWX accepts the launch; server errors are retried, bad events are skipped.
- The whole platform can be rebuilt from Git: `infra`, then `awx-config`.

## 💰 10. Cost considerations

Main costs are GKE nodes, Cloud SQL and the VM fleet. The optional HTTPS entry adds roughly $18 to $25 a month, billed hourly. Mitigations: small machine types, the optional parts off by default, and a documented four-to-five step teardown ([TEARDOWN.md](TEARDOWN.md)).

## ⚠️ 11. Risks and open items

| Risk | Mitigation |
|---|---|
| GKE endpoint reachable by hosted runners needs a public endpoint | Restrict by authorized networks; production uses a self-hosted runner or Connect Gateway |
| AWX operator and chart version drift | Versions pinned in Terraform and in the execution-environment base image |
| AWX is community-supported | It is the upstream of Ansible Tower; the design maps to Automation Controller |
| The allowlist can lock you out when your IP changes | Update `AWX_ALLOWED_CIDRS` and re-run `infra` |
| Hardening changes SSH settings | Dry-run template first; connectivity check after; one host at a time |
| Webhook message format varies by chat tool | Bodies are configurable in `awx_config.yml` |

## 🗺️ 12. Phases

| Phase | Content | Status |
|---|---|---|
| 1 | Foundation: VPC, GKE, Cloud SQL, AWX | Done |
| 2 | Fleet and dynamic inventory, first playbooks | Done |
| 3 | ansible-lint, Molecule, CIS role, custom execution environment | Done |
| 4 | Config as code and pipelines | Done |
| 5 | Staged patching with snapshots and approval | Done |
| 6 | Self-healing (6a) and provisioning callback (6b) | Done |
| 7 | RBAC, daily report, notifications (7b), diagrams and article (7c) | Done |
| 8 | 6b and 7b implementation | Done |
| 9 | Optional HTTPS entry | Done, off by default |

---

<div align="center">

**Maintained by Bikram Singh** · [⬆ Back to README](../README.md)

</div>
