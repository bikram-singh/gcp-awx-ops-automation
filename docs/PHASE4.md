# Phase 4: AWX configuration as code and job pipelines

## What this phase adds

| Piece | Where | What it does |
|---|---|---|
| Desired state | `ansible/awx-config/awx_config.yml` | Credential, project, inventory, inventory source, 4 job templates and a daily schedule, written as YAML |
| Applier | `ansible/awx-config/configure.yml` | Pushes that YAML into AWX through its API (`awx.awx` collection). Idempotent |
| Launcher | `ansible/awx-config/launch.yml` | Starts a job template, waits, fails if the job fails |
| Connect action | `.github/actions/awx-connect/` | Keyless GCP login, GKE credentials, kubectl tunnel to the private AWX service, exports `CONTROLLER_*` |
| Workflow `awx-config` | `.github/workflows/awx-config.yml` | Runs on a push that touches `ansible/awx-config/**`, applies the config |
| Workflow `ops-trigger` | `.github/workflows/ops-trigger.yml` | Run from the Actions tab: pick a template, limit and variables, GitHub launches it in AWX |

Result: AWX can be rebuilt from Git with no UI clicks, and operations can be started from GitHub with an audit trail.

## How it works

AWX runs in a private cluster, so GitHub cannot call its API directly. Each workflow logs in to GCP keylessly (the same Workload Identity setup as `infra`), gets cluster credentials, opens `kubectl port-forward` to `svc/awx-service`, reads the admin password from the `awx-admin-password` secret, and then runs Ansible against `http://localhost:8080`. No new GCP permissions are needed: the deployer service account already has `roles/container.admin`.

## One-time setup

1. Optional but recommended: add the fleet private key as a repository **secret** named `FLEET_SSH_PRIVATE_KEY` (Settings, Secrets and variables, Actions, Secrets). Paste the full contents of `awx_fleet` (the file with no extension). Without it, the workflow leaves the `fleet-ssh` credential you created by hand as it is.
2. Optional variables: `GKE_CLUSTER` (default `awxplat-gke`) and `GCP_REGION` (default `asia-south1`).
3. The `production` environment already exists. `ops-trigger` uses it only for the real patching template, so a reviewer must approve that one.

## Run it

1. Commit and push to `main`. The `awx-config` workflow starts because files under `ansible/awx-config/` changed. You can also start it from the Actions tab.
2. In AWX, check **Templates**: you should see the three existing templates plus `21 Patch Linux DEV (dry run)`, and **Schedules** with `Daily health check 02:00 UTC`.
3. Actions, **ops-trigger**, Run workflow: template `10 Health check`, limit `all`. The run waits for the AWX job and shows its status in the summary.
4. Try `21 Patch Linux DEV (dry run)` next. It runs in check mode against `env_dev` and changes nothing.
5. Real patching: pick `20 Patch Linux (rolling)`, limit `env_dev`, extra vars `{"patch_batch_size": 1, "patch_max_fail_percent": 0}`. GitHub asks a reviewer to approve the `production` environment first.

## Change the AWX setup

Edit `awx_config.yml` (for example add a template or change the schedule), push, and the workflow applies it. Because the names match the objects you built by hand, the first run adopts them instead of creating duplicates.

## Troubleshooting

| Symptom | Likely cause |
|---|---|
| `awx-connect` cannot get cluster credentials | `GCP_WIF_PROVIDER` or `GCP_DEPLOYER_SA` variable missing, or the cluster name or region differs from the defaults |
| `AWX did not answer` | The AWX pods are not ready or the cluster is stopped. Check `kubectl -n awx get pods` |
| Module not found or parameter error from `awx.awx` | Collection version does not match the AWX version. Change the version in `ansible/awx-config/requirements.yml` |
| `fleet-ssh` credential not found | The secret is not set and the credential does not exist. Add the secret or create the credential in the UI |
| Schedule rejected | `rrule` must start with `DTSTART:` in UTC, for example `DTSTART:20261022T020000Z RRULE:FREQ=DAILY;INTERVAL=1` |
| `ops-trigger` fails on a real run | Open the AWX job (the ID is in the log) and read its output. The workflow fails when the AWX job fails |

## Notes

- Not run end to end yet. The playbooks were syntax-checked in a sandbox without the real `awx.awx` modules, so the first run is the real test. Send me the log if it fails.
- If the AWX instance is reset or rebuilt, run `awx-config` again and the whole setup returns.
