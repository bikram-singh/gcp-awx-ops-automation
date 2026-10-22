# Demo script (10 minutes) and interview talking points

## Before you start (2 minutes, off camera)

- Fleet is running: `gcloud compute instances list` shows web-dev-01/02, web-prod-01 etc. as RUNNING.
- AWX port-forward is up (`kubectl -n awx port-forward svc/awx-service 8080:80`) and you are logged in.
- GitHub tabs open: Actions (infra, awx-config, ops-trigger, daily-report) and the repo README.

## The story in one sentence

"Servers are easy to build and hard to operate, so I built the platform that runs the operations: Terraform builds it, GitHub Actions delivers it with no stored keys, and AWX runs patching, health checks, snapshots and self-healing with approvals and audit."

## Run of show

| Min | Show | Say |
|---|---|---|
| 0-1 | `docs/img/platform.png` | Four Terraform stacks (platform, awx, fleet, selfheal). Private GKE, Cloud SQL on private IP, AWX via the operator. |
| 1-2 | GitHub Actions, infra workflow | Keyless auth with Workload Identity Federation. No JSON keys anywhere. Apply runs behind the `production` environment. |
| 2-3 | AWX Templates page | Everything here was created by `awx-config` from `awx_config.yml`. Nobody clicks to configure AWX; the repo is the source of truth. |
| 3-5 | Actions > ops-trigger > Run workflow, template `10 Health check` | Self-service from Git. Show the job in AWX, per-host output. Mention JSON args after the key=value bug. |
| 5-7 | AWX workflow `50 Staged patching` | Pre-check, snapshot dev, patch dev, verify, **approval gate**, snapshot prod, patch prod, verify. Open a finished run (workflow 48). Show snapshots in the GCP console. |
| 7-9 | Self-healing: `gcloud compute instances stop web-dev-02`, then watch AWX Jobs | Audit log, sink, Pub/Sub, bridge, AWX job `40 Heal`. VM is RUNNING again in about a minute (job 138). Show `docs/img/selfheal.png`. |
| 9-10 | AWX Teams / RBAC, `daily-report` run | Viewers look, operators run, approvers approve prod. The report is a table in the run summary. |

## Talking points (likely interview questions)

**Why AWX and not just GitHub Actions running Ansible?**
Actions is the delivery pipeline. AWX is the operations plane: inventory, credentials the operators never see, RBAC, schedules, approvals, job history and a REST API. This is the same model as Ansible Automation Platform, which many enterprises already license.

**How is it secure?**
No long-lived keys: Workload Identity Federation for CI, Workload Identity for pods. The fleet has no public IPs. AWX is private and reached by port-forward. Least privilege IAM, with conditional bindings so AWX can only start the fleet VMs and only snapshot disks.

**How do you keep AWX config from drifting?**
`awx-config` is idempotent and runs on merge. It adopts objects by name, so hand-built things become managed.

**What went wrong and how did you fix it?** (have two ready)
1. ops-trigger launched the wrong template: `-e key=value` splits on spaces and a numeric name resolves as an AWX ID. Fixed with JSON args and an assertion.
2. IAM condition rejected `matches` and `contains`. Only `==`, `startsWith`, `endsWith`, `extract` are supported; generated `endsWith` clauses from the fleet variable.

**How does self-healing avoid loops?**
Scoped to Admin Activity `stop` events on VMs matching the fleet name regex, one fixed template, an operator label to opt out, and the heal playbook is idempotent (running VM is a no-op).

**What would you do next for production?**
Self-hosted runner or Connect Gateway for a private control plane, managed ingress with a certificate, custom execution environment, Molecule tests, notifications to Slack or Teams, provisioning callback for new VMs.

**Cost?**
Main costs are GKE nodes and Cloud SQL. The whole stack is destroyable in four steps; see TEARDOWN.md.
