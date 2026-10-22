# Snapshots

Snapshots captured during the live run of the platform (project `gcp-awx-ops`, region `asia-south1`). Grouped by phase. The main [README](../README.md) shows the highlights.

Secrets in the original snapshots (an admin password, a private key, an IP address, a webhook URL) were removed or masked before publishing.

## Phase 1: Platform foundation

Folder: `docs/snapshots/01-platform/`

**Private GKE cluster awxplat-gke, healthy**

![Private GKE cluster awxplat-gke, healthy](snapshots/01-platform/01-gke-cluster-overview.png)

**Node pool and node status**

![Node pool and node status](snapshots/01-platform/02-gke-node-pool.png)

**AWX operator, task and web workloads running**

![AWX operator, task and web workloads running](snapshots/01-platform/03-awx-workloads-running.png)

**Cloud SQL Postgres 15 with a private IP only**

![Cloud SQL Postgres 15 with a private IP only](snapshots/01-platform/04-cloudsql-private-ip.png)

**VPC and subnets**

![VPC and subnets](snapshots/01-platform/05-vpc-subnets.png)

**Firewall rules (IAP and internal only)**

![Firewall rules (IAP and internal only)](snapshots/01-platform/06-vpc-firewall-rules.png)

**Workload Identity Federation pool for GitHub Actions**

![Workload Identity Federation pool for GitHub Actions](snapshots/01-platform/07-wif-github-pool.png)

**Service accounts created by Terraform**

![Service accounts created by Terraform](snapshots/01-platform/08-service-accounts.png)

**Terraform state bucket with a folder per stack**

![Terraform state bucket with a folder per stack](snapshots/01-platform/09-terraform-state-bucket.png)

**Generated database password in Secret Manager**

![Generated database password in Secret Manager](snapshots/01-platform/10-secret-manager.png)

**gcloud and kubectl: cluster, nodes, pods, Cloud SQL, network**

![gcloud and kubectl: cluster, nodes, pods, Cloud SQL, network](snapshots/01-platform/11-cli-gke-sql-network.png)

**gcloud: subnets, Cloud NAT and service accounts**

![gcloud: subnets, Cloud NAT and service accounts](snapshots/01-platform/12-cli-subnets-nat-service-accounts.png)

**gcloud: identity pool, secrets and state files**

![gcloud: identity pool, secrets and state files](snapshots/01-platform/13-cli-wif-secrets-state.png)

## Phase 2: AWX credential, project and inventory

Folder: `docs/snapshots/02-awx-setup/`

**First login to AWX through the port-forward**

![First login to AWX through the port-forward](snapshots/02-awx-setup/01-awx-first-login-dashboard.png)

**Machine credential fleet-ssh (key stored encrypted)**

![Machine credential fleet-ssh (key stored encrypted)](snapshots/02-awx-setup/02-credential-fleet-ssh.png)

**Project awx-ops-playbooks created from Git**

![Project awx-ops-playbooks created from Git](snapshots/02-awx-setup/03-project-create.png)

**Project sync succeeded**

![Project sync succeeded](snapshots/02-awx-setup/04-project-synced.png)

**Inventory gcp-fleet**

![Inventory gcp-fleet](snapshots/02-awx-setup/05-inventory-gcp-fleet.png)

**Dynamic inventory source from the project (gcp_compute.yml)**

![Dynamic inventory source from the project (gcp_compute.yml)](snapshots/02-awx-setup/06-inventory-source-edit.png)

**Inventory source sync succeeded**

![Inventory source sync succeeded](snapshots/02-awx-setup/07-inventory-source-synced.png)

**Inventory access**

![Inventory access](snapshots/02-awx-setup/08-inventory-access.png)

**Groups built from VM labels (env, role, patch group)**

![Groups built from VM labels (env, role, patch group)](snapshots/02-awx-setup/09-inventory-groups.png)

**Six imported hosts**

![Six imported hosts](snapshots/02-awx-setup/10-inventory-hosts.png)

## Phase 2: first job templates

Folder: `docs/snapshots/03-first-playbooks/`

**Create 00 Connectivity check**

![Create 00 Connectivity check](snapshots/03-first-playbooks/01-template-00-create.png)

**00 Connectivity check details**

![00 Connectivity check details](snapshots/03-first-playbooks/02-template-00-details.png)

**Launch prompt with limit**

![Launch prompt with limit](snapshots/03-first-playbooks/03-template-00-launch-prompt.png)

**Job output: every host answered**

![Job output: every host answered](snapshots/03-first-playbooks/04-job-00-output.png)

**Create 10 Health check**

![Create 10 Health check](snapshots/03-first-playbooks/05-template-10-create.png)

**10 Health check details**

![10 Health check details](snapshots/03-first-playbooks/06-template-10-details.png)

**Launch prompt**

![Launch prompt](snapshots/03-first-playbooks/07-template-10-launch-prompt.png)

**Launch preview**

![Launch preview](snapshots/03-first-playbooks/08-template-10-launch-preview.png)

**Health report output**

![Health report output](snapshots/03-first-playbooks/09-job-10-output.png)

**Create 20 Patch Linux (rolling)**

![Create 20 Patch Linux (rolling)](snapshots/03-first-playbooks/10-template-20-create.png)

**20 Patch Linux details**

![20 Patch Linux details](snapshots/03-first-playbooks/11-template-20-details.png)

**Launch prompt**

![Launch prompt](snapshots/03-first-playbooks/12-template-20-launch-prompt.png)

**Launch preview**

![Launch preview](snapshots/03-first-playbooks/13-template-20-launch-preview.png)

**Rolling patch with reboot and post-check**

![Rolling patch with reboot and post-check](snapshots/03-first-playbooks/14-job-20-output.png)

## Phases 4 and 5: ops-trigger and the staged patching workflow

Folder: `docs/snapshots/04-ops-trigger-and-patching/`

**ops-trigger form for 10 Health check**

![ops-trigger form for 10 Health check](snapshots/04-ops-trigger-and-patching/01-ops-trigger-form-10.png)

**ops-trigger run summary**

![ops-trigger run summary](snapshots/04-ops-trigger-and-patching/02-ops-trigger-run-10.png)

**ops-trigger form for 21 Patch Linux DEV (dry run)**

![ops-trigger form for 21 Patch Linux DEV (dry run)](snapshots/04-ops-trigger-and-patching/03-ops-trigger-form-21.png)

**Dry run summary**

![Dry run summary](snapshots/04-ops-trigger-and-patching/04-ops-trigger-run-21.png)

**ops-trigger form for 30 Snapshot disks**

![ops-trigger form for 30 Snapshot disks](snapshots/04-ops-trigger-and-patching/05-ops-trigger-form-30.png)

**Snapshot job summary**

![Snapshot job summary](snapshots/04-ops-trigger-and-patching/06-ops-trigger-run-30.png)

**Pre-patch snapshots of the dev disks**

![Pre-patch snapshots of the dev disks](snapshots/04-ops-trigger-and-patching/07-gcp-snapshots-dev.png)

**Workflow 50 Staged patching**

![Workflow 50 Staged patching](snapshots/04-ops-trigger-and-patching/08-workflow-50-details.png)

**Workflow graph: precheck, snapshot, patch, verify, approve, prod**

![Workflow graph: precheck, snapshot, patch, verify, approve, prod](snapshots/04-ops-trigger-and-patching/09-workflow-50-graph.png)

**GitHub asks for production approval**

![GitHub asks for production approval](snapshots/04-ops-trigger-and-patching/10-github-production-review.png)

**Deployment approved**

![Deployment approved](snapshots/04-ops-trigger-and-patching/11-github-production-approved.png)

**AWX workflow approval: Promote patching to prod?**

![AWX workflow approval: Promote patching to prod?](snapshots/04-ops-trigger-and-patching/12-awx-workflow-approval.png)

**Workflow finished, every node green**

![Workflow finished, every node green](snapshots/04-ops-trigger-and-patching/13-workflow-50-complete.png)

**Dev and prod snapshots taken before patching**

![Dev and prod snapshots taken before patching](snapshots/04-ops-trigger-and-patching/14-gcp-snapshots-all.png)

## Phases 6 and 8: self-healing and provisioning callback

Folder: `docs/snapshots/05-self-healing-and-onboarding/`

**infra run: IAM condition built from the fleet map**

![infra run: IAM condition built from the fleet map](snapshots/05-self-healing-and-onboarding/01-infra-fleet-iam-condition.png)

**awx-config applied**

![awx-config applied](snapshots/05-self-healing-and-onboarding/02-awx-config-run.png)

**Stop web-dev-02; the bridge launches the heal job**

![Stop web-dev-02; the bridge launches the heal job](snapshots/05-self-healing-and-onboarding/03-self-heal-demo.png)

**awx-config for Phase 8 (template 45 and bridge permissions)**

![awx-config for Phase 8 (template 45 and bridge permissions)](snapshots/05-self-healing-and-onboarding/04-awx-config-phase8.png)

**infra run: add app-dev-02 to the fleet**

![infra run: add app-dev-02 to the fleet](snapshots/05-self-healing-and-onboarding/05-infra-add-app-dev-02.png)

**Onboarding job started by the audit-log event**

![Onboarding job started by the audit-log event](snapshots/05-self-healing-and-onboarding/06-job-45-onboard-output.png)

## Phase 3a: lint, Molecule and CIS hardening

Folder: `docs/snapshots/06-hardening-and-lint/`

**ansible-lint and Molecule jobs green**

![ansible-lint and Molecule jobs green](snapshots/06-hardening-and-lint/01-lint-molecule-green.png)

**lint workflow run, both jobs green**

![lint workflow run, both jobs green](snapshots/06-hardening-and-lint/02-lint-molecule-green-2.png)

**ops-trigger form for 61 Harden Linux DEV (dry run)**

![ops-trigger form for 61 Harden Linux DEV (dry run)](snapshots/06-hardening-and-lint/03-ops-trigger-form-61.png)

**Dry run summary**

![Dry run summary](snapshots/06-hardening-and-lint/04-ops-trigger-run-61.png)

**Dry run output in check mode**

![Dry run output in check mode](snapshots/06-hardening-and-lint/05-job-153-dry-run.png)

**ops-trigger form for 60 Harden Linux (dev)**

![ops-trigger form for 60 Harden Linux (dev)](snapshots/06-hardening-and-lint/06-ops-trigger-form-60-dev.png)

**Hardening dev run summary**

![Hardening dev run summary](snapshots/06-hardening-and-lint/07-ops-trigger-run-60-dev.png)

**Hardening applied to dev**

![Hardening applied to dev](snapshots/06-hardening-and-lint/08-job-159-harden-dev.png)

**ops-trigger form: connectivity check after hardening**

![ops-trigger form: connectivity check after hardening](snapshots/06-hardening-and-lint/09-ops-trigger-form-00.png)

**Connectivity check summary**

![Connectivity check summary](snapshots/06-hardening-and-lint/10-ops-trigger-run-00.png)

**AWX still logs in after hardening**

![AWX still logs in after hardening](snapshots/06-hardening-and-lint/11-job-165-connectivity-after-hardening.png)

**ops-trigger form for 60 Harden Linux (prod)**

![ops-trigger form for 60 Harden Linux (prod)](snapshots/06-hardening-and-lint/12-ops-trigger-form-60-prod.png)

**Hardening prod run summary**

![Hardening prod run summary](snapshots/06-hardening-and-lint/13-ops-trigger-run-60-prod.png)

**Hardening applied to prod**

![Hardening applied to prod](snapshots/06-hardening-and-lint/14-job-177-harden-prod.png)

**Hardening the whole fleet, run summary**

![Hardening the whole fleet, run summary](snapshots/06-hardening-and-lint/15-ops-trigger-run-60-all.png)

**Second run: changed=0 on every host (idempotent)**

![Second run: changed=0 on every host (idempotent)](snapshots/06-hardening-and-lint/16-job-189-idempotent.png)

## Phase 3b: custom execution environment

Folder: `docs/snapshots/07-execution-environment/`

**infra run: Artifact Registry**

![infra run: Artifact Registry](snapshots/07-execution-environment/01-infra-registry.png)

**awx-config registers the execution environment**

![awx-config registers the execution environment](snapshots/07-execution-environment/02-awx-config-ee.png)

**ee-build pushes the image to Artifact Registry**

![ee-build pushes the image to Artifact Registry](snapshots/07-execution-environment/03-ee-build.png)

**awx-config: allow a limit on template 05**

![awx-config: allow a limit on template 05](snapshots/07-execution-environment/04-awx-config-allow-limit-05.png)

## Phase 9: optional HTTPS entry

Folder: `docs/snapshots/08-https-ingress/`

**infra run including the ingress stack**

![infra run including the ingress stack](snapshots/08-https-ingress/01-infra-ingress-apply.png)

**A record for awx at the DNS host**

![A record for awx at the DNS host](snapshots/08-https-ingress/02-hostinger-dns-a-record.png)

**Load balancer IP and DNS lookup**

![Load balancer IP and DNS lookup](snapshots/08-https-ingress/03-cli-ingress-ip-nslookup.png)

**Managed certificate: PROVISIONING, then ACTIVE**

![Managed certificate: PROVISIONING, then ACTIVE](snapshots/08-https-ingress/04-cli-certificate-provisioning-active.png)

**AWX login over HTTPS**

![AWX login over HTTPS](snapshots/08-https-ingress/05-awx-login-https.png)

**AWX dashboard at https://awx.gcpcloudhub.in**

![AWX dashboard at https://awx.gcpcloudhub.in](snapshots/08-https-ingress/06-awx-dashboard-https.png)

## Phase 8: notifications (7b)

Folder: `docs/snapshots/09-notifications/`

**Repository variables (AWX_DOMAIN and allow-list)**

![Repository variables (AWX_DOMAIN and allow-list)](snapshots/09-notifications/01-github-actions-variables.png)

**Notification template Ops alerts (webhook)**

![Notification template Ops alerts (webhook)](snapshots/09-notifications/02-awx-notification-template.png)

**Notification template with the Test button**

![Notification template with the Test button](snapshots/09-notifications/03-awx-notification-test-button.png)

**Template 45 Onboard new VM, launch**

![Template 45 Onboard new VM, launch](snapshots/09-notifications/04-template-45-launch.png)

**Discord: failed job alert**

![Discord: failed job alert](snapshots/09-notifications/05-discord-failed-alert.png)

**Job 218 succeeded (00 Connectivity check)**

![Job 218 succeeded (00 Connectivity check)](snapshots/09-notifications/06-job-218-success-output.png)

**Discord: failed and succeeded alerts with real AWX links**

![Discord: failed and succeeded alerts with real AWX links](snapshots/09-notifications/07-discord-failed-and-success-alerts.png)
