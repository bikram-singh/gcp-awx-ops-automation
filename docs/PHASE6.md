# Phase 6a: Self-healing, a stopped VM is started again by AWX

## What it does

When someone (or something) stops a managed VM, AWX starts it again, without a human, in about one to two minutes.

```
VM stopped (gcloud, console, API)
  -> Admin Activity audit log entry (always on, free)
  -> log sink  ->  Pub/Sub topic  ->  subscription
  -> bridge pod in the cluster PULLS the event
  -> AWX REST API: launch "40 Heal: start stopped VM"
  -> job starts the VM through the Compute API and waits until it is RUNNING
```

## Design choices (good interview material)

| Choice | Why |
|---|---|
| The bridge **pulls** from Pub/Sub inside the cluster | AWX stays private (ClusterIP). No public URL, no load balancer, no VPC connector, no Cloud Function to secure. Events flow in, nothing flows out to the internet |
| Audit-log **sink** instead of a Monitoring alert | The log entry names the VM and zone directly, arrives in seconds, and needs no agent on the VM. An alert policy only carries a numeric instance ID |
| A **least-privilege AWX user** (`selfheal`) | The bridge can run one template and nothing else. It cannot read credentials or change anything in AWX |
| **Conditional** IAM for starting VMs | AWX may start only the VMs listed in the fleet map, never the GKE nodes. IAM conditions have no regex, so the condition is generated from the map |
| **Opt-out label** | `selfheal=off` on a VM tells the job to leave it stopped. Only VMs with `ansible_managed=true` are ever touched |
| Standard library only, code in a ConfigMap | No image to build or store. The bridge runs on a stock Python image |

## What was added

| Piece | Where |
|---|---|
| Stack `selfheal` | `terraform/selfheal/`: topic, subscription, log sink, identity for the bridge, the bridge Deployment and its secret |
| Bridge code | `terraform/selfheal/bridge.py` |
| Start permission (conditional) | `terraform/fleet/main.tf`, resource `awx_vm_start` |
| Heal playbook | `ansible/playbooks/heal_stopped_vm.yml` |
| Template `40 Heal: start stopped VM`, user `selfheal` and its role | `ansible/awx-config/` |
| `infra` workflow | now includes the `selfheal` stack |

## Deploy

1. Unzip over the repo, commit and push to `main`.
2. **`infra`** runs the four stacks in order (`platform`, `awx`, `fleet`, `selfheal`). Approve each stage if asked. `fleet` adds the conditional start permission, and `selfheal` creates everything else. The first run of `selfheal` also enables the Pub/Sub API, which can take a minute.
3. **`awx-config`** starts at the same push, but it needs the bridge secret that `selfheal` creates. When `infra` is green, run **awx-config** again from the Actions tab. It then creates template 40 and the `selfheal` user and gives the user the right to run only that template.
4. Check the bridge is up:
   ```powershell
   kubectl -n awx get pods -l app=selfheal-bridge
   kubectl -n awx logs deploy/selfheal-bridge --tail=5
   ```
   You should see `{"event": "started", ...}`.

## Demo: break it and watch it heal

```powershell
# 1. Pick a dev VM and note its zone
gcloud compute instances list --project gcp-awx-ops --filter="name~dev" --format="table(name,zone.basename(),status)"

# 2. Break it
gcloud compute instances stop web-dev-02 --zone <zone> --project gcp-awx-ops

# 3. Watch the bridge notice (within a minute)
kubectl -n awx logs deploy/selfheal-bridge --tail=5 -f
```

Then in AWX, Views, Jobs: a new job `40 Heal: start stopped VM` appears by itself, started by user `selfheal`. Its output ends with `was TERMINATED, action start, now RUNNING`. Check the VM again:

```powershell
gcloud compute instances list --project gcp-awx-ops --filter="name=web-dev-02" --format="table(name,status)"
```

**Screenshots:** the stop command, the bridge log line `launched`, the AWX job started by `selfheal`, and the VM back to `RUNNING`.

To run the heal by hand (no stop event), use **ops-trigger** with template `40 Heal: start stopped VM` and extra vars `{"heal_instance": "web-dev-02", "heal_zone": "asia-south1-a"}`.

## Keep a VM stopped on purpose

```powershell
gcloud compute instances add-labels web-dev-02 --zone <zone> --project gcp-awx-ops --labels=selfheal=off
```

Remove it later with `remove-labels --labels=selfheal`. Do this **before** you stop VMs to save money, or they will be started again. Terraform updates that stop a VM (changing its machine type, say) need the same label first. Destroying the `fleet` stack is not affected.

## Troubleshooting

| Symptom | Likely cause |
|---|---|
| Bridge log: `awx_http_error` with code 401 | The `selfheal` user does not exist yet or has an old password. Run **awx-config** again |
| Bridge log: `awx_lookup_error` | Template 40 is missing. Run **awx-config** again |
| Bridge log: `loop_error` with 403 from Pub/Sub | The permissions can take a few minutes to take effect after the first apply. Wait and watch the log |
| Stopped a VM, nothing happens | Check the sink exists (`gcloud logging sinks describe awx-selfheal-vm-stop`), the VM name matches `(web\|app\|db)-(dev\|prod)-N`, and the bridge pod is running |
| Heal job fails with 403 on start | The conditional permission from the `fleet` stack is not applied, or the VM is not in the fleet map (the condition is generated from it) |
| Heal job says `optout` or `unmanaged` | The VM has `selfheal=off`, or lacks the label `ansible_managed=true` |
| `infra`: the `selfheal` stack fails on the Pub/Sub API | The API is still being enabled. Rerun the workflow |

## Notes and trade-offs

- **`compute.instanceAdmin.v1` is broad**, even with the per-VM condition, and every AWX job pod shares the same service account. In production, use a custom role that has only start, get and list, plus a separate service account for the heal job.
- **One event, one job.** Events older than an hour are dropped. Two stops in a row queue two jobs, and the second finds the VM running and does nothing.
- **Not run end to end yet.** The playbook and the bridge were tested against mock servers in a sandbox (start, opt-out, unmanaged, already running, missing, still stopping, AWX errors, redelivery). The Terraform was formatted and reviewed but not applied. The first run in your project is the real test, so send me the log if a step fails.
- **Phase 6b, the provisioning callback**, comes next: new VMs call AWX at boot to configure themselves. That needs a way for VMs to reach AWX (an internal load balancer), so it is a separate step.
