# High-Level Design: Day-2 Operations Automation Platform on GCP

| | |
|---|---|
| Author | Bikram |
| Status | Draft v0.1 (Phase 1 implemented) |
| Scope | Platform to provision, deliver and operate infrastructure using Terraform, GitHub Actions and AWX |

## 1. Problem statement

Infrastructure teams build servers with IaC but still run daily operations by hand: patching, hardening, user access, health checks, incident fixes, cost control. This causes:

- inconsistent configuration (snowflake servers)
- slow, manual, error-prone change execution
- no central audit trail of who changed what
- shared credentials passed around between engineers
- slow response to common incidents (disk full, service down)

## 2. Goals and non-goals

**Goals**

1. Provision the whole platform as code, with no console clicks.
2. Run all routine operations through one control plane with RBAC, audit and credential isolation.
3. Make operations self-service, scheduled or event-driven.
4. Use keyless authentication from CI to cloud.
5. Manage the automation platform itself as code (config-as-code).

**Non-goals**

- Application CI/CD for business apps (only an example rolling deployment is included).
- Multi-region HA of AWX (single region, single replica in the lab).
- Windows fleet management beyond a small demonstration (optional).

## 3. Logical architecture

```
                          +---------------------------+
   Developer ---PR--->    |  GitHub repo              |
                          |  terraform/ ansible/      |
                          |  awx-config/ ee/          |
                          +-------------+-------------+
                                        | GitHub Actions (OIDC / WIF)
        +-------------------------------+--------------------------------+
        | terraform apply               | lint + molecule | AWX config sync
        v                               v                 v
 +------------------ GCP project ----------------------------------------------+
 |  VPC (private subnets, Cloud NAT, IAP-only SSH)                              |
 |                                                                              |
 |  +------ GKE (private nodes, Workload Identity) ------+     +-----------+    |
 |  |  AWX Operator -> AWX web/task pods (+ EE image)    |---->| Cloud SQL |    |
 |  +--------------------+-------------------------------+     | Postgres  |    |
 |                       | SSH over IAP / WinRM                | (private) |    |
 |                       v                                     +-----------+    |
 |  Managed fleet: GCE VMs labelled env/role/patch_group                        |
 |                                                                              |
 |  Cloud Monitoring alert -> Pub/Sub -> Cloud Function -> AWX webhook          |
 |  Secret Manager (DB password, tokens)    Artifact Registry (EE images)       |
 +------------------------------------------------------------------------------+
                         |
                         v
                Slack / email notifications, daily report (GCS / BigQuery)
```

## 4. Components

| Component | Purpose | Notes |
|---|---|---|
| Terraform `platform` stack | VPC, NAT, firewall, GKE, Cloud SQL, Secret Manager | State in GCS, prefix `platform` |
| Terraform `awx` stack | AWX Operator (Helm) and AWX instance | Reads outputs of `platform` via remote state; state prefix `awx` |
| AWX | Control plane: inventories, projects, credentials, job templates, workflows, schedules, RBAC | Upstream of Ansible Tower |
| Execution Environment | Container image with ansible-core, collections, Python deps | Built by `ansible-builder` in CI |
| GCE dynamic inventory | Discovers VMs from the Compute API, groups by label | `google.cloud.gcp_compute` plugin |
| GitHub Actions | CI/CD for infra, playbooks, EE, AWX config | Authenticates through Workload Identity Federation |
| Event path | Alert to Pub/Sub to Cloud Function to AWX webhook | Self-healing |

## 5. Key design decisions

| Decision | Choice | Reason |
|---|---|---|
| Controller | AWX via AWX Operator | Same engine as Tower/Controller, free, Kubernetes-native |
| Hosting | GKE | Operator is the supported install path; easy to scale task pods |
| Database | Cloud SQL PostgreSQL (private IP) | Managed backups and patching; stateless AWX pods |
| Terraform split | Two stacks (`platform`, `awx`) | Avoids the provider-before-cluster problem; smaller blast radius |
| CI auth | Workload Identity Federation | No long-lived service account keys |
| Node access | IAP tunnelling, no public IPs | Smaller attack surface |
| AWX config | Config-as-code (`awx.awx` collection) | Reproducible, reviewable, no click-ops |
| Terraform vs Ansible | Terraform creates resources; Ansible configures and operates them | Each tool used for what it does best |

## 6. Security design

- **Identity:** GitHub Actions to GCP with OIDC; the provider is restricted to this repository through an attribute condition.
- **Least privilege:** separate service accounts for the deployer, GKE nodes, and (later) AWX-to-GCP inventory sync.
- **Secrets:** DB password generated by Terraform and stored in Secret Manager; machine credentials live only inside AWX (encrypted), users never see them.
- **Network:** private nodes, private Cloud SQL, Cloud NAT for egress, firewall allows SSH only from the IAP range.
- **Access control:** AWX organizations and teams (Ops, Dev, Auditors) with role-based permissions on templates and inventories.
- **Audit:** AWX job history and activity stream, Cloud Audit Logs for GCP.

## 7. Operational use cases (target)

1. Rolling OS patching with approval gate (workflow)
2. CIS baseline hardening and drift report
3. User and SSH key management through a survey
4. Daily health and capacity report to Slack
5. Self-healing from monitoring alerts
6. Provisioning callback for new VMs
7. Scheduled stop/start of dev VMs
8. Certificate expiry check
9. Rolling application deployment with rollback
10. Snapshot management and cleanup

## 8. Delivery pipeline

| Workflow | Trigger | Steps |
|---|---|---|
| `infra.yml` | PR / push to main | fmt, validate, plan on PR; apply `platform` then `awx` on main with environment approval |
| `ansible-ci.yml` (Phase 3) | PR touching `ansible/` | yamllint, ansible-lint, Molecule |
| `ee-build.yml` (Phase 3) | change in `execution-env/` | ansible-builder, push to Artifact Registry |
| `awx-config.yml` (Phase 4) | change in `awx-config/` | apply AWX objects through the API |
| `ops-trigger.yml` (Phase 4) | manual / schedule | launch a job template and wait for the result |

## 9. Failure handling and resilience

- Rolling updates with `serial` and `max_fail_percentage` so a bad patch stops early.
- Snapshot before patching; rollback playbook restores from it.
- AWX pods are stateless; the database is on Cloud SQL with automated backups and point-in-time recovery.
- Whole platform can be rebuilt from Git (`terraform apply`, then config-as-code sync).

## 10. Cost considerations

Main cost drivers are GKE nodes, Cloud SQL and the VM fleet. Mitigations: small machine types, one node for the lab, scheduled stop of dev VMs, and `terraform destroy` when idle.

## 11. Risks and open items

| Risk | Mitigation |
|---|---|
| GKE endpoint reachable by hosted runners requires a public endpoint | Restrict by authorized networks; production uses self-hosted runner or Connect Gateway |
| AWX Operator and chart version drift | Pin versions in Terraform variables |
| AWX is community-supported | State clearly it is the upstream of Ansible Tower; design maps 1:1 to Automation Controller |
| Cost overrun | Budget alert and routine destroy |

## 12. Phases

1. Foundation (this phase)
2. Fleet and dynamic inventory
3. Core roles, tests and execution environment
4. Config-as-code and pipelines
5. Workflows and approvals
6. Event-driven automation and callback
7. RBAC, notifications, reporting, documentation, demo
