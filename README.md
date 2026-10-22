<div align="center">

# ⚙️ gcp-awx-ops-automation

### Ansible Ops Platform on GCP

**Terraform provisions it · GitHub Actions delivers it · AWX (Ansible) runs it · Events heal it**

[![Google Cloud](https://img.shields.io/badge/Google_Cloud-GKE_·_Cloud_SQL_·_Pub%2FSub-4285F4?logo=googlecloud&logoColor=white)](https://cloud.google.com/)
[![Terraform](https://img.shields.io/badge/Terraform-5_stacks-7B42BC?logo=terraform&logoColor=white)](#-repository-structure)
[![AWX](https://img.shields.io/badge/AWX-Ansible_Tower_upstream-EE0000?logo=ansible&logoColor=white)](https://github.com/ansible/awx)
[![GitHub Actions](https://img.shields.io/badge/GitHub_Actions-Keyless_%28WIF%29-2088FF?logo=githubactions&logoColor=white)](#-the-deliver-layer)
[![Quality](https://img.shields.io/badge/Quality-ansible--lint_·_Molecule-16A34A)](#-phase-3a--lint-molecule-and-cis-hardening)
[![Self-healing](https://img.shields.io/badge/Self--healing-Audit_log_→_Pub%2FSub-F59E0B)](#-phases-6-and-8--self-healing-and-onboarding)
[![Alerts](https://img.shields.io/badge/Alerts-Discord_·_Slack_·_Teams-5865F2?logo=discord&logoColor=white)](#-phase-8--notifications)
[![Status](https://img.shields.io/badge/Status-Built_%26_Verified_end_to_end-2ECC71)](#-snapshots)

---

*Servers are easy to build and hard to operate. This project builds the platform that does the **daily operational work** (patching, hardening, access, health checks, self-healing) as **self-service, scheduled, auditable and event-driven automation**. Everything is created from code, nothing is clicked into existence, and no key is ever stored.*

Terraform provisions it. GitHub Actions delivers it. AWX (upstream of Ansible Tower / Automation Controller) runs the daily operations.

📝 **Medium Article:** [Ansible Ops Platform on GCP: Private GKE, AWX, Workload Identity and Event-Driven Self-Healing](https://medium.com/@bikram23march/ansible-ops-platform-on-gcp-67d04193ef01) · source in [docs/medium_article.md](docs/medium_article.md)

![Ansible Ops Platform on GCP: architecture](docs/architecture/architecture-gcp.svg)

</div>

---

## 📋 Table of Contents

- [Overview](#-overview)
- [What Was Built](#-what-was-built)
- [Architecture](#-architecture)
- [Concepts You Need](#-concepts-you-need)
- [Design and Naming Plan](#-design-and-naming-plan)
- [Prerequisites](#-prerequisites)
- [Repository Structure](#-repository-structure)
- [Phase 1: Stand Up the Platform](#-phase-1--stand-up-the-platform)
- [Phase 2: Fleet, Inventory and First Playbooks](#-phase-2--fleet-inventory-and-first-playbooks)
- [Phases 4 and 5: ops-trigger and Staged Patching](#-phases-4-and-5--ops-trigger-and-staged-patching)
- [Phases 6 and 8: Self-Healing and Onboarding](#-phases-6-and-8--self-healing-and-onboarding)
- [Phase 3a: Lint, Molecule and CIS Hardening](#-phase-3a--lint-molecule-and-cis-hardening)
- [Phase 3b: Custom Execution Environment](#-phase-3b--custom-execution-environment)
- [Phase 9: Optional HTTPS Entry](#-phase-9--optional-https-entry)
- [Phase 8: Notifications](#-phase-8--notifications)
- [Gotchas Reference Table](#-gotchas-reference-table)
- [Troubleshooting](#-troubleshooting)
- [Security Checklist](#-security-checklist)
- [Cost and Cleanup](#-cost-and-cleanup)
- [Snapshots](#-snapshots)
- [Roadmap](#-roadmap)
- [Documents](#-documents)
- [Known Limitations](#-known-limitations-lab-vs-production)
- [Resources](#-resources)

---

## 🌐 Overview

### What this project is

Servers are easy to build and hard to operate. This project builds the platform that handles the daily operational work (patching, hardening, access, health checks, self-healing, cost control) as **self-service, scheduled, auditable and event-driven automation**.

| Layer | Tool | Role |
|---|---|---|
| 🧱 Provision | Terraform | VPC, private GKE, Cloud SQL, AWX install, VM fleet |
| 🚚 Deliver | GitHub Actions | Plan/apply with keyless auth (OIDC), lint and test playbooks, sync AWX config |
| 🎛️ Operate | AWX | Job templates, workflows, schedules, RBAC, credentials, notifications |
| ⚡ Event | Audit log, Pub/Sub, in-cluster bridge | A VM stopped is started again; a new VM configures itself |
| ✅ Quality | ansible-lint, Molecule, ansible-builder | Every change is linted and tested; jobs run in a custom execution environment |

### 🔑 Key Facts

| Property | Value |
|---|---|
| ☁️ **Cloud** | Google Cloud, project `gcp-awx-ops`, region `asia-south1` |
| 🧱 **Provisioning** | Terraform, **5 stacks**: `platform`, `awx`, `fleet`, `selfheal`, `ingress` (optional) |
| 🚚 **Delivery** | GitHub Actions with **Workload Identity Federation**, no service account keys |
| ☸️ **Runtime** | Private GKE cluster `awxplat-gke` running AWX, Cloud SQL PostgreSQL 15 on a private IP |
| 🖥️ **Fleet** | Private Debian 12 VMs with **no public IP**, grouped by labels (env, role, patch group) |
| 🧰 **Job templates** | 11 templates and 1 workflow, all created from `awx_config.yml` |
| ⚡ **Events** | Audit log → 2 log sinks → Pub/Sub → in-cluster pull bridge → AWX |
| 📸 **Evidence** | 90 real console, CLI and AWX screenshots, sorted by phase in [`docs/snapshots/`](docs/snapshots) |
| 📚 **Docs** | HLD, architecture, 8 phase guides, demo script, teardown guide, article draft |

### ✨ What Makes This Different

| Capability | Description |
|---|---|
| 🔐 **Keyless end to end** | GitHub reaches GCP through Workload Identity Federation. AWX reads its inventory through Workload Identity. No JSON key exists anywhere |
| 🔒 **Private by default** | Private GKE, private database, VMs without public IPs, AWX only through a tunnel unless you switch the HTTPS entry on |
| 📜 **AWX as code** | Credentials, project, inventory, templates, workflow, schedules, teams and notifications live in one YAML file and are re-applied on every merge |
| ⚡ **Event driven** | A stopped VM is started again in about a minute. A new VM is onboarded when the audit log shows it was created |
| ✅ **Quality gates** | ansible-lint and Molecule on every change, a CIS-style hardening role with a dry run first, a custom execution environment |
| 🚦 **Human approval where it matters** | Staged patching: snapshot, dev, verify, **approve**, prod |
| 🔔 **Alerts with working links** | Failed and succeeded jobs post to chat, and the link opens the job in AWX |

### ❓ Why This Design?

| Choice | How It Showed Up Here |
|---|---|
| **Pull instead of push for events** | The bridge pulls from Pub/Sub inside the cluster, so AWX needs no public URL and no load balancer |
| **Config as code** | AWX can be rebuilt from scratch with no UI clicks. UI edits are put back by the next run |
| **Least privilege** | The bridge user can launch only two templates. AWX can start only the fleet VMs, never the GKE nodes |
| **Reversible by design** | Disk snapshots before patching, dry run before hardening, approval before prod |

---

## 🏗️ What Was Built

### Status

All phases are built and were run end to end on a real GCP project. 90 snapshots from the live run are in [docs/SNAPSHOTS.md](docs/SNAPSHOTS.md) and the highlights are [below](#-snapshots).

What was proven on the running platform:

| Area | Result |
|---|---|
| Platform | ✅ Private GKE, Cloud SQL (private IP), AWX running, all from Terraform and GitHub Actions with no stored keys |
| Fleet | ✅ VMs grouped by labels; dynamic inventory with no service account key |
| Patching | ✅ Staged workflow: snapshot, patch dev, verify, approval, patch prod |
| Self-healing | ✅ A stopped VM is started again within seconds |
| Onboarding | ✅ A new VM is configured by AWX as soon as the audit log shows it was created |
| Hardening | ✅ Dry run, real run, then `changed=0` on a second run, dev and prod |
| Quality | ✅ ansible-lint and Molecule run on every change; custom execution environment built and pushed |
| Access | ✅ Separate look, operate and approve duties (RBAC) |
| HTTPS | ✅ Optional entry with a managed certificate, restricted to an allowlist |
| Alerts | ✅ A failed job and a succeeded job each send a chat message (Discord) with a working link |

---

## 🏛️ Architecture

> Architecture (summary)

### 🧭 Summary

```
GitHub Repo --> GitHub Actions --(OIDC)--> GCP
                 |- terraform plan/apply (platform, awx, fleet, selfheal, ingress)
                 |- ansible-lint / molecule, execution-environment build
                 `- AWX config-as-code sync + job trigger
GKE (private) : AWX Operator -> AWX  --> Cloud SQL (PostgreSQL, private IP)
AWX --(IAP / SSH)--> managed VM fleet (labelled web/app/db, dev/prod)
Audit log --> Pub/Sub --> in-cluster bridge --> AWX (heal a stopped VM, onboard a new VM)
```

Full design: [docs/HLD.md](docs/HLD.md) and diagrams in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)

![Architecture with Google Cloud icons](docs/architecture/architecture-gcp.svg)

Vector version: [docs/architecture/architecture-gcp.svg](docs/architecture/architecture-gcp.svg) (PNG: [architecture-gcp.png](docs/architecture/architecture-gcp.png)).

![Platform](docs/img/platform.png)

More: [Demo script](docs/DEMO.md) | [Teardown](docs/TEARDOWN.md) | [Medium article](https://medium.com/@bikram23march/ansible-ops-platform-on-gcp-67d04193ef01) | [Snapshots](docs/SNAPSHOTS.md)

### 🔄 Build Order

```
 bootstrap.sh ──► platform ──► awx ──► fleet ──► AWX config (awx-config)
 (state bucket,    (VPC, GKE,   (operator,  (labelled   (credential, project,
  WIF, deployer)    Cloud SQL)   AWX)        VMs)        inventory, templates)
                                                │
                                                ▼
              selfheal ──► sinks + Pub/Sub + bridge ──► heal / onboard automatically
                                                │
                                                ▼
        lint + Molecule ──► CIS hardening ──► ee-build ──► ingress (optional) ──► alerts ✅
```

### 🧩 The Deliver Layer

| Workflow | What it does |
|---|---|
| 🏗️ `infra` | validate, plan, then apply behind the `production` approval, one matrix job per stack |
| ⚙️ `awx-config` | applies `awx_config.yml` to AWX through a private `kubectl` tunnel |
| 🚀 `ops-trigger` | launches any AWX template from GitHub with a limit and extra vars |
| 🧹 `lint` | ansible-lint and Molecule on every change |
| 📦 `ee-build` | builds the execution environment and pushes it to Artifact Registry |
| 📊 `daily-report` | scheduled health and capacity report, red when something is wrong |

---

## 🧠 Concepts You Need

| Concept | What it is | Role in this project |
|---|---|---|
| 🪪 **Workload Identity Federation** | Lets an outside identity (GitHub) act as a service account without a key | `github-pool` and the `tf-deployer` service account |
| ☸️ **Workload Identity** | Lets a pod act as a service account without a key | AWX reads the GCE inventory as `awx-inventory` |
| 📜 **Config as code** | AWX settings kept in Git and applied by a playbook | `awx_config.yml` and `configure.yml` |
| 🗂️ **Dynamic inventory** | Hosts and groups built from VM labels | `gcp-fleet`, groups `env_dev`, `role_web`, `patch_a` |
| 🔀 **Workflow with approval** | Jobs chained with a human gate | Template 50 stops before prod |
| 📡 **Audit-log sink** | Routes selected log entries to Pub/Sub | `instances.stop` and `instances.insert` |
| 🌉 **Pull bridge** | A pod that pulls events and calls the AWX API | Starts the VM again or onboards a new one |
| 📦 **Execution environment** | The container image jobs run in | `gcp-ops-ee` with the Google libraries |
| 🛡️ **Idempotence** | A second run changes nothing | Hardening shows `changed=0` |

---

## 📐 Design and Naming Plan

| Item | Value |
|---|---|
| Project | `gcp-awx-ops` |
| Region | `asia-south1` |
| GKE cluster | `awxplat-gke` (private, Workload Identity) |
| Database | Cloud SQL PostgreSQL 15, private IP, password in Secret Manager |
| State bucket | `gcp-awx-ops-tfstate`, one folder per stack |
| Deploy identity | `tf-deployer` service account, pool `github-pool` |
| Inventory identity | `awx-inventory` (read-only) |
| AWX credential / project / inventory | `fleet-ssh` / `awx-ops-playbooks` / `gcp-fleet` |
| Execution environment | `gcp-ops-ee` in Artifact Registry |

### 🧰 Job Templates at a Glance

| # | Template | Purpose |
|---|---|---|
| `00` | Connectivity check | Proves AWX can log in to every VM |
| `05` | Execution environment check | Shows the EE, Ansible version and libraries |
| `10` | Health check | Disk, memory, load, failed services |
| `20` | Patch Linux (rolling) | Batches, reboots, post-patch service check |
| `21` | Patch Linux DEV (dry run) | Check mode on dev |
| `30` | Snapshot disks (pre-patch) | Safety net before patching |
| `40` | Heal: start stopped VM | Launched by the bridge |
| `45` | Onboard new VM | Launched by the bridge for a new VM |
| `50` | Staged patching (workflow) | precheck, snapshot, patch dev, verify, **approve**, prod |
| `60` | Harden Linux (CIS baseline) | The `cis` role, one host at a time |
| `61` | Harden Linux DEV (dry run) | Check mode on dev |

### ⚙️ GitHub Configuration

| Kind | Name | Used for |
|---|---|---|
| Variable | `GCP_PROJECT_ID`, `GCP_WIF_PROVIDER`, `GCP_DEPLOYER_SA`, `TF_STATE_BUCKET` | Keyless access and state |
| Variable | `SSH_PUBLIC_KEY` | Public key placed on the fleet |
| Variable (optional) | `GKE_CLUSTER`, `GCP_REGION` | Defaults `awxplat-gke`, `asia-south1` |
| Variable (optional) | `AWX_DOMAIN`, `AWX_ALLOWED_CIDRS` | HTTPS entry and allowlist |
| Variable (optional) | `NOTIFY_FORMAT` | `teams` for a Teams Workflows webhook |
| Secret (optional) | `FLEET_SSH_PRIVATE_KEY`, `NOTIFY_WEBHOOK_URL`, `DEMO_USER_PASSWORD` | Credential, chat alerts, demo users |

> ⚠️ **Never commit keys, webhook URLs or passwords.** Keep them as GitHub secrets, and delete a webhook after a demo.

---

## ✅ Prerequisites

- ☁️ A **GCP project** with billing enabled
- 🧰 `gcloud`, `terraform >= 1.6` and `kubectl`
- 🐙 A **GitHub repository** (Actions enabled)
- 🔑 An SSH key pair for the fleet
- 🌍 *(Optional)* a domain you control, for the HTTPS entry

---

## 📁 Repository Structure

### Repo layout

```
.
├── terraform/
│   ├── platform/      VPC, NAT, firewall, private GKE, Cloud SQL, Secret Manager   (stack 1)
│   ├── awx/           AWX Operator (Helm) + AWX instance                           (stack 2)
│   ├── fleet/         Labelled private VMs + read-only inventory service account   (stack 3)
│   ├── selfheal/      Pub/Sub, log sink and in-cluster bridge for self-healing     (stack 4)
│   └── ingress/       Optional HTTPS entry to AWX (load balancer, certificate, allowlist) (stack 5)
├── ansible/           playbooks, GCE dynamic inventory                             (phase 2+)
├── roles/             Ansible roles with Molecule tests (cis hardening)             (phase 3)
├── collections/       requirements.yml read by AWX on project sync
├── ansible/awx-config/ AWX configuration as code + job launcher                    (phase 4)
├── execution-env/     ansible-builder definition of the custom AWX image          (phase 3)
├── scripts/bootstrap.sh   one-time: state bucket + Workload Identity Federation
├── .github/workflows/ infra, awx-config, ops-trigger, daily-report, lint, ee-build
└── docs/              HLD, architecture, phase guides, runbooks, snapshots/
```

### 📚 Inside `docs/`

```
docs/
├── HLD.md  ARCHITECTURE.md  DEMO.md  TEARDOWN.md  INGRESS.md  medium_article.md
├── PHASE2.md ... PHASE8.md       # what each phase built and how to run it
├── SNAPSHOTS.md                  # every snapshot with a caption
├── architecture/                 # architecture-gcp.svg and .png (Google Cloud icons)
├── img/                          # Mermaid diagram PNGs for slides and the article
└── snapshots/                    # real screenshots, one folder per phase
    ├── 01-platform/                    13
    ├── 02-awx-setup/                   10
    ├── 03-first-playbooks/             14
    ├── 04-ops-trigger-and-patching/    14
    ├── 05-self-healing-and-onboarding/  6
    ├── 06-hardening-and-lint/          16
    ├── 07-execution-environment/        4
    ├── 08-https-ingress/                6
    └── 09-notifications/                7
```

---

## 🔹 Phase 1 · Stand Up the Platform

A **private GKE cluster**, **Cloud SQL on a private IP only**, and **keyless GitHub access** through Workload Identity Federation. All built by Terraform, delivered by GitHub Actions.

| What | Detail |
|---|---|
| 🧰 Bootstrap | State bucket `gcp-awx-ops-tfstate`, `tf-deployer` service account, Workload Identity pool `github-pool` |
| 🌐 Platform stack | VPC and subnet with Cloud NAT, IAP and internal firewalls, private GKE with Workload Identity, Cloud SQL Postgres 15 on a private IP, DB password generated into Secret Manager |
| 🎛️ AWX stack | AWX Operator through Helm, then the AWX resource with the external database |
| 🚚 CI/CD | validate, plan, then apply behind a `production` approval, matrix of stacks |

#### Phase 1: stand up the platform

Prerequisites: a GCP project with billing, `gcloud`, `terraform >= 1.6`, a GitHub repo.

1. **Bootstrap (once, from your laptop or Cloud Shell)**

   ```bash
   export PROJECT_ID=your-project-id
   export GITHUB_REPO=bikram-singh/gcp-awx-ops-automation
   ./scripts/bootstrap.sh
   ```

   It creates the Terraform state bucket, the deployer service account, and the Workload Identity Federation pool/provider, then prints the values to store as GitHub repository **variables**: `GCP_PROJECT_ID`, `GCP_WIF_PROVIDER`, `GCP_DEPLOYER_SA`, `TF_STATE_BUCKET`.

2. **Push to GitHub.** A PR runs fmt, validate and plan for both stacks. Merging to `main` applies `platform` first, then `awx`, behind the `production` environment approval.

3. **Or run locally**

   ```bash
   cd terraform/platform
   cp terraform.tfvars.example terraform.tfvars   # edit values
   terraform init -backend-config="bucket=$TF_STATE_BUCKET"
   terraform apply

   cd ../awx
   cp terraform.tfvars.example terraform.tfvars
   terraform init -backend-config="bucket=$TF_STATE_BUCKET"
   terraform apply
   ```

4. **Log in to AWX**

   ```bash
   gcloud container clusters get-credentials $(terraform -chdir=../platform output -raw cluster_name) \
     --region $(terraform -chdir=../platform output -raw region) --project $PROJECT_ID
   kubectl -n awx port-forward svc/awx-service 8080:80
   kubectl -n awx get secret awx-admin-password -o jsonpath='{.data.password}' | base64 -d
   # open http://localhost:8080  user: admin
   ```

📘 Full guide: [docs/HLD.md](docs/HLD.md) · [docs/PHASE2.md](docs/PHASE2.md)

> 📷 A private GKE cluster, Cloud SQL on a private IP only, and keyless GitHub access through Workload Identity Federation. All built by Terraform.

<table>
<tr><td width="50%"><img src="docs/snapshots/01-platform/01-gke-cluster-overview.png" alt="Private GKE cluster awxplat-gke, healthy"><br><sub><b>Private GKE cluster awxplat-gke, healthy</b></sub></td><td width="50%"><img src="docs/snapshots/01-platform/02-gke-node-pool.png" alt="Node pool and node status"><br><sub><b>Node pool and node status</b></sub></td></tr>
<tr><td width="50%"><img src="docs/snapshots/01-platform/03-awx-workloads-running.png" alt="AWX operator, task and web workloads running"><br><sub><b>AWX operator, task and web workloads running</b></sub></td><td width="50%"><img src="docs/snapshots/01-platform/04-cloudsql-private-ip.png" alt="Cloud SQL Postgres 15 with a private IP only"><br><sub><b>Cloud SQL Postgres 15 with a private IP only</b></sub></td></tr>
<tr><td width="50%"><img src="docs/snapshots/01-platform/05-vpc-subnets.png" alt="VPC and subnets"><br><sub><b>VPC and subnets</b></sub></td><td width="50%"><img src="docs/snapshots/01-platform/06-vpc-firewall-rules.png" alt="Firewall rules (IAP and internal only)"><br><sub><b>Firewall rules (IAP and internal only)</b></sub></td></tr>
<tr><td width="50%"><img src="docs/snapshots/01-platform/07-wif-github-pool.png" alt="Workload Identity Federation pool for GitHub Actions"><br><sub><b>Workload Identity Federation pool for GitHub Actions</b></sub></td><td width="50%"><img src="docs/snapshots/01-platform/08-service-accounts.png" alt="Service accounts created by Terraform"><br><sub><b>Service accounts created by Terraform</b></sub></td></tr>
</table>

> 📸 Showing 8 of 13. All of them: [docs/SNAPSHOTS.md](docs/SNAPSHOTS.md)

---

## 🔹 Phase 2 · Fleet, Inventory and First Playbooks

Give AWX real servers to manage and prove it can operate them.

| Piece | Detail |
|---|---|
| 🔑 SSH key pair | Public key to a GitHub variable, private key into AWX as the `fleet-ssh` credential |
| 🖥️ Fleet stack | Private Debian 12 VMs, no public IP. Labels `env`, `role`, `patch_group`, `ansible_managed` drive the groups. A startup script creates the `ansible` user |
| 🪪 Keyless inventory | The org policy blocked service account keys, so Workload Identity maps the AWX service accounts to the read-only `awx-inventory` account |
| 🎛️ AWX setup | Credential `fleet-ssh`, project `awx-ops-playbooks`, inventory `gcp-fleet` with a dynamic GCE source |
| 🧰 First templates | `00` Connectivity check, `10` Health check, `20` Patch Linux (rolling) |

📘 Full guide: [docs/PHASE2.md](docs/PHASE2.md)

### 🔧 AWX setup

> 📷 The SSH credential (stored encrypted), the project synced from Git, and a dynamic inventory built from VM labels with no service account key.

<table>
<tr><td width="50%"><img src="docs/snapshots/02-awx-setup/01-awx-first-login-dashboard.png" alt="First login to AWX through the port-forward"><br><sub><b>First login to AWX through the port-forward</b></sub></td><td width="50%"><img src="docs/snapshots/02-awx-setup/02-credential-fleet-ssh.png" alt="Machine credential fleet-ssh (key stored encrypted)"><br><sub><b>Machine credential fleet-ssh (key stored encrypted)</b></sub></td></tr>
<tr><td width="50%"><img src="docs/snapshots/02-awx-setup/03-project-create.png" alt="Project awx-ops-playbooks created from Git"><br><sub><b>Project awx-ops-playbooks created from Git</b></sub></td><td width="50%"><img src="docs/snapshots/02-awx-setup/04-project-synced.png" alt="Project sync succeeded"><br><sub><b>Project sync succeeded</b></sub></td></tr>
<tr><td width="50%"><img src="docs/snapshots/02-awx-setup/05-inventory-gcp-fleet.png" alt="Inventory gcp-fleet"><br><sub><b>Inventory gcp-fleet</b></sub></td><td width="50%"><img src="docs/snapshots/02-awx-setup/06-inventory-source-edit.png" alt="Dynamic inventory source from the project (gcp_compute.yml)"><br><sub><b>Dynamic inventory source from the project (gcp_compute.yml)</b></sub></td></tr>
<tr><td width="50%"><img src="docs/snapshots/02-awx-setup/07-inventory-source-synced.png" alt="Inventory source sync succeeded"><br><sub><b>Inventory source sync succeeded</b></sub></td><td width="50%"><img src="docs/snapshots/02-awx-setup/08-inventory-access.png" alt="Inventory access"><br><sub><b>Inventory access</b></sub></td></tr>
</table>

> 📸 Showing 8 of 10. All of them: [docs/SNAPSHOTS.md](docs/SNAPSHOTS.md)

### ▶️ First job templates

> 📷 Connectivity check, health report and a rolling patch with reboot and post-check.

<table>
<tr><td width="50%"><img src="docs/snapshots/03-first-playbooks/01-template-00-create.png" alt="Create 00 Connectivity check"><br><sub><b>Create 00 Connectivity check</b></sub></td><td width="50%"><img src="docs/snapshots/03-first-playbooks/02-template-00-details.png" alt="00 Connectivity check details"><br><sub><b>00 Connectivity check details</b></sub></td></tr>
<tr><td width="50%"><img src="docs/snapshots/03-first-playbooks/03-template-00-launch-prompt.png" alt="Launch prompt with limit"><br><sub><b>Launch prompt with limit</b></sub></td><td width="50%"><img src="docs/snapshots/03-first-playbooks/04-job-00-output.png" alt="Job output: every host answered"><br><sub><b>Job output: every host answered</b></sub></td></tr>
<tr><td width="50%"><img src="docs/snapshots/03-first-playbooks/05-template-10-create.png" alt="Create 10 Health check"><br><sub><b>Create 10 Health check</b></sub></td><td width="50%"><img src="docs/snapshots/03-first-playbooks/06-template-10-details.png" alt="10 Health check details"><br><sub><b>10 Health check details</b></sub></td></tr>
<tr><td width="50%"><img src="docs/snapshots/03-first-playbooks/07-template-10-launch-prompt.png" alt="Launch prompt"><br><sub><b>Launch prompt</b></sub></td><td width="50%"><img src="docs/snapshots/03-first-playbooks/08-template-10-launch-preview.png" alt="Launch preview"><br><sub><b>Launch preview</b></sub></td></tr>
</table>

> 📸 Showing 8 of 14. All of them: [docs/SNAPSHOTS.md](docs/SNAPSHOTS.md)

---

## 🔹 Phases 4 and 5 · ops-trigger and Staged Patching

**Phase 4** puts AWX configuration in Git and adds workflows that apply it and launch jobs. **Phase 5** adds the staged patching workflow.

| Piece | Detail |
|---|---|
| ⚙️ `awx-config` | Applies `awx_config.yml` on every merge, adopting hand-built objects by name |
| 🚀 `ops-trigger` | Pick a template, a limit and extra vars, and GitHub launches the job in AWX |
| 📸 Snapshot first | Template `30` snapshots the disks before any patching |
| 🔀 Workflow `50` | precheck, snapshot dev, patch dev, verify dev, **approve**, snapshot prod, patch prod, verify prod |
| 🚦 Two approvals | GitHub `production` environment for the trigger, and an AWX approval inside the workflow |

📘 Full guides: [docs/PHASE4.md](docs/PHASE4.md) · [docs/PHASE5.md](docs/PHASE5.md)

> 📷 Jobs launched from GitHub Actions (`ops-trigger`), and the staged patching workflow: snapshot, patch dev, verify, human approval, then prod.

<table>
<tr><td width="50%"><img src="docs/snapshots/04-ops-trigger-and-patching/01-ops-trigger-form-10.png" alt="ops-trigger form for 10 Health check"><br><sub><b>ops-trigger form for 10 Health check</b></sub></td><td width="50%"><img src="docs/snapshots/04-ops-trigger-and-patching/02-ops-trigger-run-10.png" alt="ops-trigger run summary"><br><sub><b>ops-trigger run summary</b></sub></td></tr>
<tr><td width="50%"><img src="docs/snapshots/04-ops-trigger-and-patching/03-ops-trigger-form-21.png" alt="ops-trigger form for 21 Patch Linux DEV (dry run)"><br><sub><b>ops-trigger form for 21 Patch Linux DEV (dry run)</b></sub></td><td width="50%"><img src="docs/snapshots/04-ops-trigger-and-patching/04-ops-trigger-run-21.png" alt="Dry run summary"><br><sub><b>Dry run summary</b></sub></td></tr>
<tr><td width="50%"><img src="docs/snapshots/04-ops-trigger-and-patching/05-ops-trigger-form-30.png" alt="ops-trigger form for 30 Snapshot disks"><br><sub><b>ops-trigger form for 30 Snapshot disks</b></sub></td><td width="50%"><img src="docs/snapshots/04-ops-trigger-and-patching/06-ops-trigger-run-30.png" alt="Snapshot job summary"><br><sub><b>Snapshot job summary</b></sub></td></tr>
<tr><td width="50%"><img src="docs/snapshots/04-ops-trigger-and-patching/07-gcp-snapshots-dev.png" alt="Pre-patch snapshots of the dev disks"><br><sub><b>Pre-patch snapshots of the dev disks</b></sub></td><td width="50%"><img src="docs/snapshots/04-ops-trigger-and-patching/08-workflow-50-details.png" alt="Workflow 50 Staged patching"><br><sub><b>Workflow 50 Staged patching</b></sub></td></tr>
</table>

> 📸 Showing 8 of 14. All of them: [docs/SNAPSHOTS.md](docs/SNAPSHOTS.md)

---

## 🔹 Phases 6 and 8 · Self-Healing and Onboarding

Events from the Admin Activity audit log drive AWX, with no inbound path into the cluster.

```
VM stopped / created  ──►  audit log  ──►  2 log sinks  ──►  Pub/Sub topic
                                                                   │
        AWX launches template 40 (heal) or 45 (onboard)  ◄──  in-cluster bridge (pull)
```

| Piece | Detail |
|---|---|
| 🩺 Heal (6a) | A stopped fleet VM is started again within a minute or two. Template `40` |
| 🆕 Onboard (6b) | A new labelled VM gets a baseline, time sync and a health check. Template `45`, limited to that VM |
| 🔒 Least privilege | The bridge's AWX user can run only templates `40` and `45` |
| ⏸️ Opt out | Label `selfheal=off` leaves a VM stopped on purpose |

📘 Full guides: [docs/PHASE6.md](docs/PHASE6.md) · [docs/PHASE8.md](docs/PHASE8.md)

> 📷 A stopped VM is started again automatically, and a new VM is onboarded by an audit-log event.

<table>
<tr><td width="50%"><img src="docs/snapshots/05-self-healing-and-onboarding/01-infra-fleet-iam-condition.png" alt="infra run: IAM condition built from the fleet map"><br><sub><b>infra run: IAM condition built from the fleet map</b></sub></td><td width="50%"><img src="docs/snapshots/05-self-healing-and-onboarding/02-awx-config-run.png" alt="awx-config applied"><br><sub><b>awx-config applied</b></sub></td></tr>
<tr><td width="50%"><img src="docs/snapshots/05-self-healing-and-onboarding/03-self-heal-demo.png" alt="Stop web-dev-02; the bridge launches the heal job"><br><sub><b>Stop web-dev-02; the bridge launches the heal job</b></sub></td><td width="50%"><img src="docs/snapshots/05-self-healing-and-onboarding/04-awx-config-phase8.png" alt="awx-config for Phase 8 (template 45 and bridge permissions)"><br><sub><b>awx-config for Phase 8 (template 45 and bridge permissions)</b></sub></td></tr>
<tr><td width="50%"><img src="docs/snapshots/05-self-healing-and-onboarding/05-infra-add-app-dev-02.png" alt="infra run: add app-dev-02 to the fleet"><br><sub><b>infra run: add app-dev-02 to the fleet</b></sub></td><td width="50%"><img src="docs/snapshots/05-self-healing-and-onboarding/06-job-45-onboard-output.png" alt="Onboarding job started by the audit-log event"><br><sub><b>Onboarding job started by the audit-log event</b></sub></td></tr>
</table>

---

## 🔹 Phase 3a · Lint, Molecule and CIS Hardening

Every change is linted and tested, and hardening is rolled out safely.

| Piece | Detail |
|---|---|
| 🧹 `lint` workflow | ansible-lint (production profile) and a Molecule matrix on every change |
| 🛡️ `cis` role | Baseline hardening: SSH settings, sysctl, unused filesystems, file permissions |
| 🧪 Dry run first | Template `61` runs in check mode on dev before `60` changes anything |
| ♻️ Idempotent | A second run shows `changed=0` on every host |
| 🔌 Still reachable | `00 Connectivity check` after hardening proves AWX can still log in |

📘 Full guide: [docs/PHASE3.md](docs/PHASE3.md)

> 📷 ansible-lint and Molecule on every change, a CIS-style hardening role, a dry run before the real run, and a second run that changes nothing (`changed=0`).

<table>
<tr><td width="50%"><img src="docs/snapshots/06-hardening-and-lint/01-lint-molecule-green.png" alt="ansible-lint and Molecule jobs green"><br><sub><b>ansible-lint and Molecule jobs green</b></sub></td><td width="50%"><img src="docs/snapshots/06-hardening-and-lint/02-lint-molecule-green-2.png" alt="lint workflow run, both jobs green"><br><sub><b>lint workflow run, both jobs green</b></sub></td></tr>
<tr><td width="50%"><img src="docs/snapshots/06-hardening-and-lint/03-ops-trigger-form-61.png" alt="ops-trigger form for 61 Harden Linux DEV (dry run)"><br><sub><b>ops-trigger form for 61 Harden Linux DEV (dry run)</b></sub></td><td width="50%"><img src="docs/snapshots/06-hardening-and-lint/04-ops-trigger-run-61.png" alt="Dry run summary"><br><sub><b>Dry run summary</b></sub></td></tr>
<tr><td width="50%"><img src="docs/snapshots/06-hardening-and-lint/05-job-153-dry-run.png" alt="Dry run output in check mode"><br><sub><b>Dry run output in check mode</b></sub></td><td width="50%"><img src="docs/snapshots/06-hardening-and-lint/06-ops-trigger-form-60-dev.png" alt="ops-trigger form for 60 Harden Linux (dev)"><br><sub><b>ops-trigger form for 60 Harden Linux (dev)</b></sub></td></tr>
<tr><td width="50%"><img src="docs/snapshots/06-hardening-and-lint/07-ops-trigger-run-60-dev.png" alt="Hardening dev run summary"><br><sub><b>Hardening dev run summary</b></sub></td><td width="50%"><img src="docs/snapshots/06-hardening-and-lint/08-job-159-harden-dev.png" alt="Hardening applied to dev"><br><sub><b>Hardening applied to dev</b></sub></td></tr>
</table>

> 📸 Showing 8 of 16. All of them: [docs/SNAPSHOTS.md](docs/SNAPSHOTS.md)

---

## 🔹 Phase 3b · Custom Execution Environment

| Piece | Detail |
|---|---|
| 📦 Image | `gcp-ops-ee` built with ansible-builder on the AWX base image, with the Google collections and Python libraries |
| 🗄️ Registry | Pushed to Artifact Registry by the `ee-build` workflow |
| 🎛️ AWX | Registered by `awx-config`. Template `05 Execution environment check` runs in it |

📘 Full guide: [docs/PHASE3.md](docs/PHASE3.md)

> 📷 A custom execution environment built with ansible-builder and pushed to Artifact Registry.

<table>
<tr><td width="50%"><img src="docs/snapshots/07-execution-environment/01-infra-registry.png" alt="infra run: Artifact Registry"><br><sub><b>infra run: Artifact Registry</b></sub></td><td width="50%"><img src="docs/snapshots/07-execution-environment/02-awx-config-ee.png" alt="awx-config registers the execution environment"><br><sub><b>awx-config registers the execution environment</b></sub></td></tr>
<tr><td width="50%"><img src="docs/snapshots/07-execution-environment/03-ee-build.png" alt="ee-build pushes the image to Artifact Registry"><br><sub><b>ee-build pushes the image to Artifact Registry</b></sub></td><td width="50%"><img src="docs/snapshots/07-execution-environment/04-awx-config-allow-limit-05.png" alt="awx-config: allow a limit on template 05"><br><sub><b>awx-config: allow a limit on template 05</b></sub></td></tr>
</table>

---

## 🔹 Phase 9 · Optional HTTPS Entry

By default AWX is reached through a port-forward. For demos there is an **optional** stack: a global load balancer, a Google-managed certificate and a **Cloud Armor allowlist**.

| Rule | Detail |
|---|---|
| 🔒 Safe by default | Does nothing until you set a domain **and** an allowlist |
| 🚫 Refused | A domain without an allowlist, and `0.0.0.0/0` |
| 🌍 DNS | One A record at your DNS host points the name at the load balancer |
| ⏱️ Certificate | Can take up to about 80 minutes to turn **ACTIVE** |

📘 Full guide: [docs/INGRESS.md](docs/INGRESS.md)

> 📷 Optional HTTPS entry: global load balancer, Google-managed certificate and a Cloud Armor allowlist.

<table>
<tr><td width="50%"><img src="docs/snapshots/08-https-ingress/01-infra-ingress-apply.png" alt="infra run including the ingress stack"><br><sub><b>infra run including the ingress stack</b></sub></td><td width="50%"><img src="docs/snapshots/08-https-ingress/02-hostinger-dns-a-record.png" alt="A record for awx at the DNS host"><br><sub><b>A record for awx at the DNS host</b></sub></td></tr>
<tr><td width="50%"><img src="docs/snapshots/08-https-ingress/03-cli-ingress-ip-nslookup.png" alt="Load balancer IP and DNS lookup"><br><sub><b>Load balancer IP and DNS lookup</b></sub></td><td width="50%"><img src="docs/snapshots/08-https-ingress/04-cli-certificate-provisioning-active.png" alt="Managed certificate: PROVISIONING, then ACTIVE"><br><sub><b>Managed certificate: PROVISIONING, then ACTIVE</b></sub></td></tr>
<tr><td width="50%"><img src="docs/snapshots/08-https-ingress/05-awx-login-https.png" alt="AWX login over HTTPS"><br><sub><b>AWX login over HTTPS</b></sub></td><td width="50%"><img src="docs/snapshots/08-https-ingress/06-awx-dashboard-https.png" alt="AWX dashboard at https://awx.gcpcloudhub.in"><br><sub><b>AWX dashboard at https://awx.gcpcloudhub.in</b></sub></td></tr>
</table>

---

## 🔹 Phase 8 · Notifications

AWX sends **failed jobs**, **approval requests** and, for chosen templates, **successes** to a chat webhook. Slack-style body, so it works with Discord (add `/slack` to the URL), Slack and Mattermost. A Teams Workflows webhook needs `NOTIFY_FORMAT=teams`.

| Check | Result |
|---|---|
| ❌ Failed job (template 45, unknown VM) | ✅ Red alert in Discord with a link to the job |
| ✅ Succeeded job (template 00) | ✅ Green alert in Discord with a link to the job |
| 🔗 Alert link | `https://awx.gcpcloudhub.in/#/jobs/playbook/<id>` |

> 💡 The AWX **Test** button shows *Failed* on Discord because its payload has no `text` field. Real alerts work. Test with real jobs.

📘 Full guide: [docs/PHASE8.md](docs/PHASE8.md)

> 📷 A failed job and a succeeded job each send a chat alert with a link that opens the job in AWX.

<table>
<tr><td width="50%"><img src="docs/snapshots/09-notifications/01-github-actions-variables.png" alt="Repository variables (AWX_DOMAIN and allow-list)"><br><sub><b>Repository variables (AWX_DOMAIN and allow-list)</b></sub></td><td width="50%"><img src="docs/snapshots/09-notifications/02-awx-notification-template.png" alt="Notification template Ops alerts (webhook)"><br><sub><b>Notification template Ops alerts (webhook)</b></sub></td></tr>
<tr><td width="50%"><img src="docs/snapshots/09-notifications/03-awx-notification-test-button.png" alt="Notification template with the Test button"><br><sub><b>Notification template with the Test button</b></sub></td><td width="50%"><img src="docs/snapshots/09-notifications/04-template-45-launch.png" alt="Template 45 Onboard new VM, launch"><br><sub><b>Template 45 Onboard new VM, launch</b></sub></td></tr>
<tr><td width="50%"><img src="docs/snapshots/09-notifications/05-discord-failed-alert.png" alt="Discord: failed job alert"><br><sub><b>Discord: failed job alert</b></sub></td><td width="50%"><img src="docs/snapshots/09-notifications/06-job-218-success-output.png" alt="Job 218 succeeded (00 Connectivity check)"><br><sub><b>Job 218 succeeded (00 Connectivity check)</b></sub></td></tr>
<tr><td width="50%"><img src="docs/snapshots/09-notifications/07-discord-failed-and-success-alerts.png" alt="Discord: failed and succeeded alerts with real AWX links"><br><sub><b>Discord: failed and succeeded alerts with real AWX links</b></sub></td><td width="50%"></td></tr>
</table>

---

## 🛡️ Gotchas Reference Table

| Area | Gotcha |
|---|---|
| 🔑 Keys | The org policy can block service account keys. Use Workload Identity Federation and Workload Identity |
| 🪪 IAM conditions | Only `==`, `startsWith`, `endsWith` and `extract` are supported. No regex. Generate the clauses from the fleet map |
| 🧪 Check mode | A patch post-check can break in check mode. Guard it |
| 🏷️ Labels | Only VMs labelled `ansible_managed=true` enter the inventory and are touched by self-healing |
| 🎯 Limit | A template needs *Prompt on launch* for the limit before ops-trigger can pass one |
| 📝 `{{ }}` in config | Use `!unsafe` so AWX, not Ansible, fills notification variables |
| 🌉 Onboarding test | The first play runs on `localhost`, so a failing test needs a limit like `localhost:web-dev-01` |
| 🔔 Test button | AWX's Test sends no `text` field, so Discord shows *Failed* |
| 🌍 Certificate | Managed certificates stay `PROVISIONING` until DNS points at the load balancer |
| 💰 Cost | GKE nodes, Cloud SQL and the optional load balancer keep billing until you tear down |

---

## 🔧 Troubleshooting

| Symptom | Likely cause |
|---|---|
| CI lint fails with `Could not determine home directory` | Word temp files (`~$…docx`, `~WRL….tmp`) were committed. `git rm --cached` them and ignore `~*` |
| Galaxy install fails with `Unexpected Exception 'results'` | A flaky download. The workflows retry the install |
| ops-trigger: *limit does not allow for it to be overridden* | Turn on *Prompt on launch* for the limit (`ask_limit: true` in `awx_config.yml`) |
| `gcloud` asks for a condition when adding an IAM binding | The policy has conditional bindings. Choose **None** for the new binding |
| `curl ifconfig.me` returns a web page on PowerShell | Use `curl.exe -s https://api.ipify.org` |
| Certificate stays `PROVISIONING` | DNS does not yet point at the load balancer address, or it has not propagated |
| Discord notification test shows *Failed* | Expected. Run a real failing job instead |
| No alert for a job you expected to fail | Check the job really failed, and that the template's Notifications tab has the toggle on |
| Stopped VM is not started again | Check the bridge logs (`kubectl -n awx logs deploy/selfheal-bridge`) and that the VM has `ansible_managed=true` and not `selfheal=off` |

More per-phase tips are in the phase guides under [`docs/`](docs).

---

## 🔒 Security Checklist

- 🔐 **No keys anywhere:** Workload Identity Federation for CI, Workload Identity for pods.
- 🌐 **Nothing public by default:** private GKE and database, VMs without public IPs, AWX through a tunnel.
- 🚪 **If you open the HTTPS entry,** keep the Cloud Armor allowlist tight. `0.0.0.0/0` is refused.
- 🧑‍⚖️ **Separate duties (RBAC):** look, operate and approve are different teams.
- ✋ **Require reviewers** on the GitHub `production` environment so approvals really ask someone.
- 🧱 **Least privilege:** the bridge user runs two templates, AWX can start only fleet VMs.
- 🗑️ **Never commit** keys, webhook URLs, passwords or documents that contain them. Delete test webhooks after a demo.
- 📸 **Check screenshots before publishing.** Remove passwords, private keys and personal IPs.

---

## 💰 Cost and Cleanup

### Cost note

GKE nodes and Cloud SQL are the main cost. Use `terraform destroy` when you are not working, in the order given in [docs/TEARDOWN.md](docs/TEARDOWN.md). Set `gke_node_count = 1` and a small machine type for the lab.

⚠️ The optional HTTPS entry adds roughly $18 to $25 a month while it is on. Switch it off (clear `AWX_DOMAIN`) and delete the DNS record when you finish a demo.

**Cleanup order:** `ingress`, `selfheal`, `fleet`, `awx`, `platform`, then snapshots and the optional bootstrap. The exact commands are in [docs/TEARDOWN.md](docs/TEARDOWN.md).

---

## 📸 Snapshots

Highlights from the live run. Every snapshot, in order and with captions, is in [docs/SNAPSHOTS.md](docs/SNAPSHOTS.md). The files are in `docs/snapshots/`, one folder per phase.

Real screenshots taken from the Google Cloud console, the terminal, AWX and GitHub while running the platform, all under [`docs/snapshots/`](docs/snapshots), grouped by phase and shown above. Every snapshot with a caption is in [docs/SNAPSHOTS.md](docs/SNAPSHOTS.md).

| Folder | Phase | Files |
|---|---|---|
| `01-platform` | Platform foundation | 13 |
| `02-awx-setup` | AWX credential, project, inventory | 10 |
| `03-first-playbooks` | First job templates | 14 |
| `04-ops-trigger-and-patching` | ops-trigger and staged patching | 14 |
| `05-self-healing-and-onboarding` | Self-healing and provisioning callback | 6 |
| `06-hardening-and-lint` | Lint, Molecule, CIS hardening | 16 |
| `07-execution-environment` | Custom execution environment | 4 |
| `08-https-ingress` | Optional HTTPS entry | 6 |
| `09-notifications` | Chat alerts | 7 |

> 🔍 The snapshots show the demo project. Replace the project ID and domain with your own when you reproduce the lab.

---

## 🗺️ Roadmap

- [x] Phase 1: Foundation (VPC, GKE, Cloud SQL, AWX)
- [x] Phase 2: VM fleet with labels, GCE dynamic inventory, first playbooks (see [docs/PHASE2.md](docs/PHASE2.md))
- [x] Phase 3: ansible-lint and Molecule in CI, CIS hardening role, custom execution environment (see [docs/PHASE3.md](docs/PHASE3.md))
- [x] Phase 4: AWX config-as-code + workflows that apply it and launch jobs (see [docs/PHASE4.md](docs/PHASE4.md))
- [x] Phase 5: Staged patching workflow (pre-check, snapshot, patch, verify, approval, prod) (see [docs/PHASE5.md](docs/PHASE5.md))
- [x] Phase 6a: Self-healing, a stopped VM is started again by AWX (see [docs/PHASE6.md](docs/PHASE6.md))
- [x] Phase 6b: Provisioning callback, new VMs configure themselves (see [docs/PHASE8.md](docs/PHASE8.md))
- [x] Phase 7a: RBAC with separate look, operate and approve duties, plus a daily health report (see [docs/PHASE7.md](docs/PHASE7.md))
- [x] Phase 7b: AWX notifications (failure, success, approvals) to a chat webhook, proven with Discord (see [docs/PHASE8.md](docs/PHASE8.md))
- [x] Phase 7c: diagrams, demo script, teardown guide, Medium article draft (see Documents)
- [x] Phase 9 (optional): HTTPS entry to AWX with a Google-managed certificate and a Cloud Armor allowlist (see [docs/INGRESS.md](docs/INGRESS.md))

---

## 📚 Documents

| Document | What it is |
|---|---|
| 🏛️ [docs/HLD.md](docs/HLD.md) | High-level design, decisions, security, risks |
| 🗺️ [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | Diagrams: platform, pipelines, patching, self-healing, onboarding, RBAC |
| 📘 [docs/PHASE2.md](docs/PHASE2.md) to [PHASE8.md](docs/PHASE8.md) | What each phase built and how to run it |
| 🌐 [docs/INGRESS.md](docs/INGRESS.md) | Optional HTTPS entry |
| 🎬 [docs/DEMO.md](docs/DEMO.md) | 10-minute demo script and interview talking points |
| 💥 [docs/TEARDOWN.md](docs/TEARDOWN.md) | Destroy everything in the right order |
| 📝 [docs/medium_article.md](docs/medium_article.md) | Medium article ([read on Medium](https://medium.com/@bikram23march/ansible-ops-platform-on-gcp-67d04193ef01)), source file |
| 📸 [docs/SNAPSHOTS.md](docs/SNAPSHOTS.md) | All snapshots from the live run, by phase |

---

## ⚠️ Known Limitations (lab vs production)

- The GKE control-plane endpoint is public but restricted by `master_authorized_cidrs`, so hosted GitHub runners can reach it. In production, use a self-hosted runner inside the VPC or the Connect Gateway and a fully private endpoint.
- AWX is reached through `kubectl port-forward` by default. An optional HTTPS entry with a Google-managed certificate and a Cloud Armor allowlist is in [docs/INGRESS.md](docs/INGRESS.md); it is off until you set `AWX_DOMAIN` and `AWX_ALLOWED_CIDRS`.
- Chat alerts use a webhook URL kept as a GitHub secret. Treat it like a password.

---

## 🔗 Resources

- [AWX on GitHub](https://github.com/ansible/awx) and the [awx.awx collection](https://docs.ansible.com/ansible/latest/collections/awx/awx/)
- [Workload Identity Federation](https://cloud.google.com/iam/docs/workload-identity-federation)
- [Private GKE clusters](https://cloud.google.com/kubernetes-engine/docs/concepts/private-cluster-concept)
- [Cloud Audit Logs and log sinks](https://cloud.google.com/logging/docs/export)
- [Cloud Armor](https://cloud.google.com/armor/docs) and [Google-managed certificates](https://cloud.google.com/load-balancing/docs/ssl-certificates/google-managed-certs)
- [ansible-builder](https://ansible.readthedocs.io/projects/builder/) and [Molecule](https://ansible.readthedocs.io/projects/molecule/)
- [Terraform Google provider](https://registry.terraform.io/providers/hashicorp/google/latest/docs)

---

<div align="center">

**Maintained by Bikram Singh**

*Built and verified hands-on on Google Cloud*

</div>
