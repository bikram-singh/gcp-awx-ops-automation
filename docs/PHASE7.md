# 📘 Phase 7a: Access control and the daily health report

> 🏠 [README](../README.md) · 🏛️ [HLD](HLD.md) · 🗺️ [Architecture](ARCHITECTURE.md) · 🎬 [Demo](DEMO.md) · 💥 [Teardown](TEARDOWN.md) · 📸 [Snapshots](SNAPSHOTS.md)

## ✨ What this adds

| Piece | Where | What it does |
|---|---|---|
| Teams and roles as code | `ansible/awx-config/awx_config.yml` (`awx_rbac`), applied by `configure.yml` | Three teams with separate duties: look, operate, approve production |
| Optional demo users | same, created only when the secret `DEMO_USER_PASSWORD` exists | `viewer`, `operator`, `approver`, one per team, to show the separation live |
| Daily health report | `ansible/awx-config/report.yml` and `report.md.j2` | Runs the health check through AWX and turns the result into a table |
| Workflow `daily-report` | `.github/workflows/daily-report.yml` | Every day at 09:00 India time. Shows the table on the run page, keeps it as an artifact, goes red when a host needs attention |

## ✨ Who can do what

| Team | Can do | Cannot do |
|---|---|---|
| `ops-readonly` | See everything in the organization | Launch or change anything |
| `ops-operators` | Launch `00 Connectivity check`, `10 Health check`, `21 Patch Linux DEV (dry run)`, `30 Snapshot disks` | Launch real patching (`20`), launch the staged workflow (`50`), approve prod |
| `prod-approvers` | Approve or deny the "Promote patching to prod?" step | Launch anything |

The person who starts a change is not the person who approves it into production. That is the point to make in an interview.

## 🎬 Turn on the demo users (optional)

1. In GitHub, go to Settings, Secrets and variables, Actions, **Secrets**, New repository secret. Name it `DEMO_USER_PASSWORD` and give it a password for the three demo users (the same one for all, for the lab).
2. Run the **awx-config** workflow from the Actions tab.
3. Open AWX in a private browser window and log in as each user. Screenshot what each one sees:
   - `viewer`: everything is visible, and the launch rocket is missing or refused.
   - `operator`: can launch `10 Health check`, but not `20 Patch Linux (rolling)`.
   - `approver`: sees Views, Workflow Approvals and can approve or deny a pending request.

Without the secret, the teams and grants are still created, only the users are skipped.

## 📊 The daily report

- It runs every day at 03:30 UTC (09:00 India time). You can also run it from Actions, **daily-report**, Run workflow.
- Open the run page. The table is under the run summary, and the same file is kept as the artifact `fleet-health-report`.
- The run goes **red** if any host has a finding (disk, memory, load or a failed service). GitHub emails the repository owner about failed runs, so this doubles as a notification with nothing extra to set up. Turn the failure off for a manual run with `fail_on_warn` unticked.

## 🔹 About the AWX admin password

Do not change it. The generated password is already long and random, and the pipelines read it from the Kubernetes secret `awx-admin-password`. Changing it in the AWX screen would make every workflow fail until the secret matched again. Daily work should go through the three teams above instead.

## 🔧 Troubleshooting

| Symptom | Likely cause |
|---|---|
| `awx-config` fails on "Give each team its role" | The template or workflow named in `awx_rbac.grants` does not exist yet. Names must match `awx_templates` and `awx_workflows` exactly |
| A demo user cannot log in | `DEMO_USER_PASSWORD` was not set when `awx-config` last ran. Set it and run the workflow again |
| `approver` sees no pending approval | The approval only exists while the staged workflow is waiting. Start workflow `50` and look in Workflow Approvals |
| `daily-report` fails with "no health_report artifact" | The health check job itself failed. Open it in AWX Views, Jobs |
| `daily-report` is red but the job was green | A host has a finding. Open the report table on the run page |

## 📝 Notes

- **Not run end to end yet.** The report was tested against a mock AWX (table, warning case, no-warning case). The roles are checked by lint against the real module definitions, but I could not apply them to a real AWX from here. The first run is the real test, and the approver's view is the part I am least sure of. Send me a screenshot if it looks wrong.
- Next in Phase 7: **7b** notifications from AWX itself (failed jobs, waiting approvals), then **7c** diagrams, the demo script and the Medium article.

---

<div align="center">

**Maintained by Bikram Singh** · [⬆ Back to README](../README.md)

</div>
