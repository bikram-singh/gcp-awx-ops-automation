# Enterprise Day-2 Operations Automation Platform on GCP

Terraform provisions it. GitHub Actions delivers it. AWX (upstream of Ansible Tower / Automation Controller) runs the daily operations.

## What this project is

Servers are easy to build and hard to operate. This project builds the platform that handles the daily operational work (patching, hardening, access, health checks, self-healing, cost control) as **self-service, scheduled, auditable and event-driven automation**.

| Layer | Tool | Role |
|---|---|---|
| Provision | Terraform | VPC, private GKE, Cloud SQL, AWX install, VM fleet |
| Deliver | GitHub Actions | Plan/apply with keyless auth (OIDC), lint and test playbooks, sync AWX config |
| Operate | AWX | Job templates, workflows, schedules, RBAC, credentials, notifications |
| Event | Cloud Monitoring, Pub/Sub, Cloud Function | Alert triggers AWX webhook for self-healing |

## Architecture (summary)

```
GitHub Repo --> GitHub Actions --(OIDC)--> GCP
                 |- terraform plan/apply (platform, awx)
                 |- ansible-lint / molecule
                 `- AWX config-as-code sync + job trigger
GKE (private) : AWX Operator -> AWX  --> Cloud SQL (PostgreSQL, private IP)
AWX --(IAP / SSH)--> managed VM fleet (labelled web/app/db, dev/prod)
Cloud Monitoring alert -> Pub/Sub -> Cloud Function -> AWX webhook
```

Full design: [docs/HLD.md](docs/HLD.md)

## Repo layout

```
.
├── terraform/
│   ├── platform/      VPC, NAT, firewall, private GKE, Cloud SQL, Secret Manager   (stack 1)
│   ├── awx/           AWX Operator (Helm) + AWX instance                           (stack 2)
│   └── fleet/         Labelled private VMs + read-only inventory service account   (stack 3)
├── ansible/           playbooks, GCE dynamic inventory                             (phase 2+)
├── collections/       requirements.yml read by AWX on project sync
├── awx-config/        templates, schedules, workflows as YAML                      (phase 4)
├── execution-env/     ansible-builder definition                                   (phase 3)
├── functions/         Cloud Function: alert -> AWX webhook                         (phase 6)
├── scripts/bootstrap.sh   one-time: state bucket + Workload Identity Federation
├── .github/workflows/infra.yml
└── docs/              HLD, LLD, runbooks
```

## Phase 1: stand up the platform

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

## Roadmap

- [x] Phase 1: Foundation (VPC, GKE, Cloud SQL, AWX)
- [ ] Phase 2 (code written, pending first run): VM fleet with labels, GCE dynamic inventory, first playbooks (see [docs/PHASE2.md](docs/PHASE2.md))
- [ ] Phase 3: Core roles (patching, CIS hardening, health check) + Molecule + custom EE
- [ ] Phase 4: AWX config-as-code + CI pipelines
- [ ] Phase 5: Patching workflow (pre-check, snapshot, patch, verify, notify) with approval
- [ ] Phase 6: Self-healing (alert -> Pub/Sub -> webhook) and provisioning callback
- [ ] Phase 7: RBAC, notifications, daily report, docs, demo, article

## Cost note

GKE nodes and Cloud SQL are the main cost. Use `terraform destroy` (awx stack first, then platform) when you are not working. Set `gke_node_count = 1` and a small machine type for the lab.

## Known limitations (lab vs production)

- The GKE control-plane endpoint is public but restricted by `master_authorized_cidrs`, so hosted GitHub runners can reach it. In production, use a self-hosted runner inside the VPC or the Connect Gateway and a fully private endpoint.
- AWX is exposed through `kubectl port-forward` in Phase 1. Managed ingress with a Google-managed certificate is added in a later phase.
