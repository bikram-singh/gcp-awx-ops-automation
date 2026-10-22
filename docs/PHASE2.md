# 📘 Phase 2: VM fleet, dynamic inventory and first playbooks

> 🏠 [README](../README.md) · 🏛️ [HLD](HLD.md) · 🗺️ [Architecture](ARCHITECTURE.md) · 🎬 [Demo](DEMO.md) · 💥 [Teardown](TEARDOWN.md) · 📸 [Snapshots](SNAPSHOTS.md)

## ✨ What this phase adds

| Piece | Where | What it does |
|---|---|---|
| Fleet stack | `terraform/fleet/` | 6 private Debian 12 VMs labelled `env`, `role`, `patch_group`; an `ansible` user created by a startup script; a read-only `awx-inventory` service account |
| Dynamic inventory | `ansible/inventories/gcp_compute.yml` | AWX asks the GCE API for running VMs and builds groups from the labels |
| Playbooks | `ansible/playbooks/` | `connectivity_check.yml`, `health_check.yml`, `patch_linux.yml` |

Inventory groups produced from labels: `env_dev`, `env_prod`, `role_web`, `role_app`, `role_db`, `patch_a`, `patch_b`.

## 🔹 1. Create the SSH key pair (once, on your laptop)

```powershell
ssh-keygen -t ed25519 -f $env:USERPROFILE\.ssh\awx_fleet -C ansible@awx -N '""'
Get-Content $env:USERPROFILE\.ssh\awx_fleet.pub
```

The `.pub` file goes to Terraform and is not secret. The private key (`awx_fleet`, no extension) goes only into AWX.

## 🖥️ 2. Deploy the fleet

Add a GitHub repository **variable** `SSH_PUBLIC_KEY` with the full contents of the `.pub` line (Settings, Secrets and variables, Actions, Variables). Then push to `main`. The `fleet` job runs after `platform` and `awx` and waits for your approval. Or apply locally:

```powershell
cd terraform\fleet
copy terraform.tfvars.example terraform.tfvars   # edit ssh_public_key
terraform init -backend-config="bucket=gcp-awx-ops-tfstate"
terraform apply
```

Check the result:

```powershell
gcloud compute instances list --project gcp-awx-ops --format="table(name,zone.basename(),networkInterfaces[0].networkIP,labels)"
```

## 🗂️ 3. Inventory access without keys (Workload Identity)

Your organization blocks service account keys (`iam.managed.disableServiceAccountKeyCreation`), so the inventory sync uses Workload Identity instead. Nothing to create by hand:

- the `fleet` stack creates `awx-inventory@gcp-awx-ops.iam.gserviceaccount.com` (read-only, `compute.viewer`) and allows the AWX Kubernetes service accounts `awx/default` and `awx/awx` to act as it;
- the `awx` stack annotates the `default` Kubernetes service account in the `awx` namespace, which AWX job pods use.

Apply both stacks (push and approve the pipeline) before you sync the inventory. If the sync later says it cannot find credentials, also annotate the `awx` service account and restart the task pod:

```powershell
kubectl -n awx annotate serviceaccount awx iam.gke.io/gcp-service-account=awx-inventory@gcp-awx-ops.iam.gserviceaccount.com --overwrite
kubectl -n awx rollout restart deployment awx-task
```

## ⚙️ 4. Configure AWX (UI)

Open AWX at http://localhost:8080 (`kubectl -n awx port-forward svc/awx-service 8080:80`).

1. **Credentials, Add** (`fleet-ssh`): type **Machine**, username `ansible`, paste the private key. Leave privilege escalation empty (the playbooks set `become` themselves).
2. **Projects, Add** (`awx-ops-playbooks`): source control type Git, URL `https://github.com/bikram-singh/gcp-awx-ops-automation.git`, branch `main`. Tick **Update revision on job launch**. Save and wait for the project to show a green status.
3. **Inventories, Add** (`gcp-fleet`), then open it, **Sources, Add**:
   - Source: **Sourced from a Project**
   - Project: `awx-ops-playbooks`
   - Inventory file: `ansible/inventories/gcp_compute.yml`
   - Credential: none (Workload Identity is used)
   - Options: Overwrite, Overwrite variables, Update on launch
   - Save and click **Sync**. In **Hosts** you should see the 6 VMs, and in **Groups** the label groups.
4. **Templates, Add job template**, three times. For each: inventory `gcp-fleet`, project `awx-ops-playbooks`, credential `fleet-ssh`, and tick **Prompt on launch** for Limit and Variables.

   | Name | Playbook |
   |---|---|
   | `00 Connectivity check` | `ansible/playbooks/connectivity_check.yml` |
   | `10 Health check` | `ansible/playbooks/health_check.yml` |
   | `20 Patch Linux (rolling)` | `ansible/playbooks/patch_linux.yml` |

## 🔹 5. Run order

1. `00 Connectivity check` with limit `all`. All 6 hosts should be OK. If the SSH step fails, see Troubleshooting.
2. `10 Health check`. Open the job output and the **Artifacts** section for `health_report`.
3. `20 Patch Linux (rolling)` first with **Check mode** (job template option) and limit `env_dev`, then for real with limit `env_dev`, then `env_prod` through a survey or a schedule later.

Useful extra vars: `{"patch_batch_size": 1, "patch_max_fail_percent": 0, "patch_reboot": "auto"}` patches one host at a time and stops on the first failure.

## 🔧 Troubleshooting

| Symptom | Likely cause |
|---|---|
| Inventory sync fails with an import error for `google.auth` or `requests` | The default execution environment lacks the GCP Python libraries. Phase 3 builds a custom execution environment; ask me and I will bring that forward |
| Inventory sync: `could not automatically find credentials` or a 403 | The job pod is not mapped to the inventory service account. See step 3: annotate the `awx` service account and restart `awx-task` |
| Inventory sync returns 0 hosts | VMs not running, or the labels do not match the filters in `gcp_compute.yml` (`status = RUNNING`, `labels.ansible_managed = true`) |
| SSH timeout to hosts | Firewall `allow_internal` must allow the pod range (it does by default); check the VM is running and has an IP |
| SSH permission denied | Wrong private key in `fleet-ssh`, or `ssh_public_key` in Terraform was different. Re-apply with the right key and reboot or `sudo google_metadata_script_runner startup` |
| Project sync fails on collections | Galaxy not reachable from the cluster; check Cloud NAT is up |

## 💰 Costs

Six `e2-small` VMs cost roughly as much as one extra small node. When you are not working, destroy the `fleet` stack (it is cheap to recreate):

```powershell
cd terraform\fleet
terraform destroy
```

---

<div align="center">

**Maintained by Bikram Singh** · [⬆ Back to README](../README.md)

</div>
