# 🎬 Demo script (10 minutes) and interview talking points

> 🏠 [README](../README.md) · 🏛️ [HLD](HLD.md) · 🗺️ [Architecture](ARCHITECTURE.md) · 🎬 [Demo](DEMO.md) · 💥 [Teardown](TEARDOWN.md) · 📸 [Snapshots](SNAPSHOTS.md)

## 🧰 Before you start (2 minutes, off camera)

- Fleet is running: `gcloud compute instances list` shows the six VMs (web-dev-01/02, app-dev-01, db-dev-01, web-prod-01, app-prod-01) as RUNNING.
- AWX port-forward is up (`kubectl -n awx port-forward svc/awx-service 8080:80`) and you are logged in.
- GitHub tabs open: Actions (infra, awx-config, ops-trigger, daily-report) and the repo README.

## 📖 The story in one sentence

"Servers are easy to build and hard to operate, so I built the platform that runs the operations: Terraform builds it, GitHub Actions delivers it with no stored keys, and AWX runs patching, health checks, snapshots and self-healing with approvals and audit."

## 🎬 Run of show

| Min | Show | Say |
|---|---|---|
| 0-1 | `docs/img/platform.png` | Five Terraform stacks. Private GKE, Cloud SQL on private IP, AWX via the operator, private registry for my own execution environment. |
| 1-2 | GitHub Actions: infra, lint | Keyless auth with Workload Identity Federation. Every playbook and role change is linted and tested with Molecule before it merges. Apply runs behind the `production` environment. |
| 2-3 | AWX Templates page | Everything here was created by `awx-config` from `awx_config.yml`. The repo is the source of truth. |
| 3-5 | Actions > ops-trigger, template `10 Health check` | Self-service from Git. Show the job in AWX, per-host output. Mention JSON args after the key=value bug. |
| 5-7 | AWX workflow `50 Staged patching` | Pre-check, snapshot dev, patch dev, verify, **approval gate**, snapshot prod, patch prod, verify. Open a finished run (workflow 48). Show snapshots in the GCP console. |
| 7-8 | Hardening: run `61 Harden Linux DEV (dry run)`, show the diff (job 153), then the all-fleet run showing `changed=0` | CIS-aligned baseline, tested by Molecule, dry run first, one host at a time, connectivity check after. |
| 8-9 | Self-healing: `gcloud compute instances stop web-dev-02`, watch AWX Jobs | Audit log, sink, Pub/Sub, bridge, AWX job `40 Heal`. VM is RUNNING in about a minute (job 138). Show `docs/img/selfheal.png`. |
| 9-10 | Provisioning callback: show job 146 and `docs/img/onboard.png` (or merge a new VM line live, about 3 minutes) | Same audit-log path, second sink. A new VM configures itself, no load balancer. |
| 10-11 | AWX Teams / RBAC; optional `https://awx.gcpcloudhub.in` | Viewers look, operators run, approvers approve prod. The public entry is optional, HTTPS only and allowlist-protected. |

For a 10-minute slot, skip the live provisioning merge and the HTTPS page.

## 💬 Talking points (likely interview questions)

**Why AWX and not just GitHub Actions running Ansible?**
Actions is the delivery pipeline. AWX is the operations plane: inventory, credentials the operators never see, RBAC, schedules, approvals, job history and a REST API. This is the same model as Ansible Automation Platform, which many enterprises already license.

**How is it secure?**
No long-lived keys: Workload Identity Federation for CI, Workload Identity for pods. The fleet has no public IPs. AWX is private and reached by port-forward. Least privilege IAM, with conditional bindings so AWX can only start the fleet VMs and only snapshot disks.

**How do you keep AWX config from drifting?**
`awx-config` is idempotent and runs on merge. It adopts objects by name, so hand-built things become managed.

**What went wrong and how did you fix it?** (have two ready)
1. ops-trigger launched the wrong template: `-e key=value` splits on spaces and a numeric name resolves as an AWX ID. Fixed with JSON args and an assertion.
2. IAM condition rejected `matches` and `contains`. Only `==`, `startsWith`, `endsWith`, `extract` are supported; generated `endsWith` clauses from the fleet variable.
3. Alerts: the AWX Test button always failed against Discord (no `text` field), and my first "failing" job succeeded because the limit skipped the localhost check. Tested with real jobs instead, and fixed the limit with `localhost:vm`.

**How does self-healing avoid loops?**
Scoped to Admin Activity `stop` events on VMs matching the fleet name regex, one fixed template, an operator label to opt out, and the heal playbook is idempotent (running VM is a no-op).

**What would you do next for production?**
Self-hosted runner or Connect Gateway for a fully private control plane, identity-aware access (IAP or SSO) instead of an IP allowlist, more roles on the same Molecule-tested pattern (users, certificates), and deployments with rollback.

**How did you make hardening safe?**
Dry-run template first, one host at a time with zero tolerated failures, the SSH file validated with `sshd -t` before install, and a connectivity check right after. A final run showed `changed=0` on all six VMs.

**Why a custom execution environment?**
The jobs need the Google libraries and collections. Baking them into an image built in CI and stored in a private registry means jobs install nothing at run time and every run uses a known, versioned set.

**How do you stop AWX being exposed?**
It is private by default and pipelines use a tunnel. The optional HTTPS entry refuses to exist without an allowlist, serves HTTPS only and puts Cloud Armor in front.

**Cost?**
Main costs are GKE nodes and Cloud SQL, plus about $18 to $25 a month if the optional HTTPS entry is on. The whole stack is destroyable in a few steps; see TEARDOWN.md.

---

<div align="center">

**Maintained by Bikram Singh** · [⬆ Back to README](../README.md)

</div>
