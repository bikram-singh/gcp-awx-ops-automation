# Teardown (stop the cost)

GKE nodes and Cloud SQL are the main cost. Destroy in reverse order of creation: **selfheal, fleet, awx, platform**.

Backend bucket: `gcp-awx-ops-tfstate`. Project: `gcp-awx-ops`.

## 0. Prepare

```bash
export PROJECT_ID=gcp-awx-ops
export STATE_BUCKET=gcp-awx-ops-tfstate
gcloud config set project $PROJECT_ID
```

Stopped VMs trigger self-healing. Destroying `selfheal` first removes the sink and bridge, so deleting the fleet afterwards does not launch heal jobs. (Deleted VMs are not "stopped" events, but doing selfheal first is the safe order.)

## 1. Destroy the stacks

Each stack needs its required variables, even for destroy:

| Stack | Variables |
|---|---|
| selfheal | `project_id`, `state_bucket` |
| fleet | `project_id`, `state_bucket`, `ssh_public_key` |
| awx | `project_id`, `state_bucket` |
| platform | `project_id` |

```bash
for s in selfheal fleet awx platform; do
  cd terraform/$s
  terraform init -input=false -backend-config="bucket=$STATE_BUCKET"
  terraform destroy -input=false \
    -var="project_id=$PROJECT_ID" \
    $( [ $s != platform ] && echo -var="state_bucket=$STATE_BUCKET" ) \
    $( [ $s = fleet ] && echo -var="ssh_public_key=$(cat ~/.ssh/id_rsa.pub)" )
  cd ../..
done
```

Cloud SQL has `db_deletion_protection`. If destroy of `platform` is refused, set `db_deletion_protection = false` in `terraform.tfvars`, run `terraform apply`, then destroy again.

## 2. Clean up what Terraform does not own

```bash
# Snapshots made by the patching workflow
gcloud compute snapshots list --format="value(name)" | xargs -r -n1 gcloud compute snapshots delete --quiet

# Check nothing is left
gcloud compute instances list
gcloud container clusters list
gcloud sql instances list
gcloud pubsub topics list
```

## 3. Optional: remove the bootstrap

Keep the state bucket and Workload Identity Federation if you plan to rebuild; they cost almost nothing. To remove everything, delete the bucket (`gcloud storage rm -r gs://$STATE_BUCKET`) and the deployer service account / WIF pool created by `scripts/bootstrap.sh`.

## Rebuild

Run `infra` (merge to `main` or Run workflow), then `awx-config` again, because it needs the bridge secret that `selfheal` creates.
