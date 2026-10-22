# 📘 Phase 5: Staged patching workflow with snapshots and approval

> 🏠 [README](../README.md) · 🏛️ [HLD](HLD.md) · 🗺️ [Architecture](ARCHITECTURE.md) · 🎬 [Demo](DEMO.md) · 💥 [Teardown](TEARDOWN.md) · 📸 [Snapshots](SNAPSHOTS.md)

## ✨ What this phase adds

| Piece | Where | What it does |
|---|---|---|
| Snapshot playbook | `ansible/playbooks/snapshot_disks.yml` | Takes a labelled boot-disk snapshot of each target VM (the rollback point). No SSH needed |
| Snapshot permission | `terraform/fleet/main.tf` | Gives the AWX service account `roles/compute.storageAdmin` so it can create snapshots |
| Template `30 Snapshot disks (pre-patch)` | `ansible/awx-config/awx_config.yml` | Runs the playbook above |
| Workflow `50 Staged patching (dev, approve, prod)` | same file | Chains the templates with a human approval before prod |
| Launcher support | `launch.yml`, `ops-trigger.yml` | `ops-trigger` can start template 30 and workflow 50 |

## 🔹 The workflow

```
precheck (health, all)
  -> snapshot dev -> patch dev (1 host at a time, stop on first failure) -> verify dev
  -> APPROVAL: "Promote patching to prod?"
  -> snapshot prod -> patch prod (1 host at a time) -> verify prod
```

- **Verify** is the health check with `fail_on_issues` on, so a warning on any host fails the stage.
- **Any failed step stops the workflow.** Prod is never touched if dev fails or if nobody approves.
- **The approval** waits up to 24 hours (`timeout: 86400`). Denying it ends the workflow.
- Everything is defined in `awx_config.yml`, so the `awx-config` workflow builds it in AWX.

## 🔹 Deploy

1. **Permission first.** Push the Terraform change. The `infra` pipeline runs `platform`, `awx` and `fleet`, and each stage waits for your approval in the `production` environment. Only `fleet` has a change (the new IAM binding). Approve all three.
2. **AWX config.** The same push changes `ansible/awx-config/`, so the `awx-config` workflow also runs. Wait for `infra` to finish first if you want to be safe, or rerun `awx-config` from the Actions tab afterwards.
3. In AWX you should now see template `30 Snapshot disks (pre-patch)` and, under Templates, the workflow `50 Staged patching (dev, approve, prod)`. Open the workflow and its **Visualizer** tab to see the graph. Take a screenshot.

## 🧪 Test, in this order

1. **Snapshots alone.** Run `ops-trigger` with template `30 Snapshot disks (pre-patch)`, limit `env_dev`. Then check Compute Engine, Storage, Snapshots: you should see `pre-patch-<host>-<date>` for each dev VM. Screenshot it.
2. **The whole workflow.** Run `ops-trigger` with template `50 Staged patching (dev, approve, prod)`. GitHub asks a reviewer to approve the `production` environment first, because this workflow can patch prod. Or launch it directly in AWX (Templates, rocket icon).
3. Watch the workflow job in AWX (Views, Jobs). It runs precheck, dev snapshot, dev patch and dev verify, then stops at the approval.
4. Go to **Views, Workflow Approvals** and approve. The prod stages run.

To rehearse safely, deny the approval once. The workflow ends after dev and nothing in prod changes.

## 📸 Roll back from a snapshot

```powershell
gcloud compute snapshots list --project gcp-awx-ops --filter="labels.purpose=pre-patch"
# Create a new disk from the snapshot, stop the VM, swap the boot disk, start it again
gcloud compute disks create web-dev-01-restore --source-snapshot=<snapshot-name> --zone=asia-south1-a --project gcp-awx-ops
```

## 🔧 Troubleshooting

| Symptom | Likely cause |
|---|---|
| Snapshot task: `Required 'compute.disks.createSnapshot' permission` | The Terraform change is not applied yet (approve `fleet` in the `infra` run), or the Workload Identity mapping is missing |
| Snapshot task: disk not found | The boot disk name differs from the instance name, or the `zone` host variable is empty. Open the host in AWX and check its variables |
| `awx-config` fails on the workflow task | Collection version does not match the AWX version, see `ansible/awx-config/requirements.yml` |
| Verify stage fails on the first run | The health check found a real warning (memory, disk, failed unit). Read the job output, fix it, and rerun |
| Workflow stops at the approval and nobody notices | Expected. Notifications for approvals arrive in Phase 7 |

## 🔧 Notes and trade-offs

- **Snapshot permission is broad for a lab.** `compute.storageAdmin` also covers disks and images in the project. A custom role limited to the snapshot permissions is the production choice.
- **No automatic snapshot clean-up yet.** Snapshots keep costing a little. Delete old ones with `gcloud compute snapshots delete`, or add a retention job later.
- **Not run end to end yet.** The code passed `ansible-lint` at the production profile with the real module definitions, but the first run in your environment is the real test. Send me the log if a step fails.

---

<div align="center">

**Maintained by Bikram Singh** · [⬆ Back to README](../README.md)

</div>
