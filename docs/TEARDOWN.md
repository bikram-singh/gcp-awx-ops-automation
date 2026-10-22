# 💥 Teardown (stop the cost)

> 🏠 [README](../README.md) · 🏛️ [HLD](HLD.md) · 🗺️ [Architecture](ARCHITECTURE.md) · 🎬 [Demo](DEMO.md) · 💥 [Teardown](TEARDOWN.md) · 📸 [Snapshots](SNAPSHOTS.md)

GKE nodes and Cloud SQL are the main cost. Destroy in reverse order of creation: **ingress (if you created it), selfheal, fleet, awx, platform**.

Backend bucket: `gcp-awx-ops-tfstate`. Project: `gcp-awx-ops`.

## 🔹 0. Prepare

```bash
export PROJECT_ID=gcp-awx-ops
export STATE_BUCKET=gcp-awx-ops-tfstate
gcloud config set project $PROJECT_ID
```

Stopped VMs trigger self-healing. Destroying `selfheal` first removes the sink and bridge, so deleting the fleet afterwards does not launch heal jobs. (Deleted VMs are not "stopped" events, but doing selfheal first is the safe order.)

## 🔹 1. Destroy the stacks

Each stack needs only its required variables, even for destroy. Passing a variable a stack does not declare is an error, so use exactly these:

| Stack | Variables |
|---|---|
| ingress (only if created) | `state_bucket` |
| selfheal | `state_bucket` |
| fleet | `state_bucket`, `ssh_public_key` |
| awx | `state_bucket` |
| platform | `project_id` |

```bash
SSH_PUB="$(cat ~/.ssh/awx_fleet.pub)"   # the public key you used for the fleet

destroy() {   # destroy <stack> [extra -var arguments]
  local stack=$1; shift
  ( cd "terraform/$stack" \
    && terraform init -input=false -backend-config="bucket=$STATE_BUCKET" \
    && terraform destroy -input=false "$@" )
}

destroy ingress  -var="state_bucket=$STATE_BUCKET"      # skip if you never created it
destroy selfheal -var="state_bucket=$STATE_BUCKET"
destroy fleet    -var="state_bucket=$STATE_BUCKET" -var="ssh_public_key=$SSH_PUB"
destroy awx      -var="state_bucket=$STATE_BUCKET"
destroy platform -var="project_id=$PROJECT_ID"
```

Run them one at a time and stop if one fails.

Cloud SQL has `db_deletion_protection`. If destroy of `platform` is refused, set `db_deletion_protection = false` in `terraform.tfvars`, run `terraform apply`, then destroy again.

## ✨ 2. Clean up what Terraform does not own

```bash
# Snapshots made by the patching workflow
gcloud compute snapshots list --format="value(name)" | xargs -r -n1 gcloud compute snapshots delete --quiet

# Check nothing is left
gcloud compute instances list
gcloud container clusters list
gcloud sql instances list
gcloud pubsub topics list
```

## 🔹 3. Optional: remove the bootstrap

Keep the state bucket and Workload Identity Federation if you plan to rebuild; they cost almost nothing. To remove everything, delete the bucket (`gcloud storage rm -r gs://$STATE_BUCKET`) and the deployer service account / WIF pool created by `scripts/bootstrap.sh`.

## ♻️ Rebuild

Run `infra` (merge to `main` or Run workflow), then `awx-config` again, because it needs the bridge secret that `selfheal` creates.

---

<div align="center">

**Maintained by Bikram Singh** · [⬆ Back to README](../README.md)

</div>
