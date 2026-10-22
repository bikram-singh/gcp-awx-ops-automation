<!--
PUBLISHING NOTES (delete this block before you publish):
- Medium does not support markdown tables, so every table below is an image (docs/article/*.png in the repo).
- Every image URL points at the GitHub repo (branch main). Push the repo first, then in Medium's editor paste each image URL on its own line and press Enter, or download the file and upload it.
- Image base URL: https://raw.githubusercontent.com/bikram-singh/gcp-awx-ops-automation/main/docs/
- Medium supports H1/H2 headings, bold, bullet lists and code blocks. Use "##" lines as section headings.
-->

# Ansible Ops Platform on GCP: Private GKE, AWX, Workload Identity and Event-Driven Self-Healing

**GCP · Terraform · GitHub Actions · AWX · Ansible · GKE · Pub/Sub · Self-healing · DevOps · SRE**

*Terraform provisions it, GitHub Actions delivers it with no stored keys, and AWX runs patching, hardening, self-healing and alerts. Built and proved end to end on Google Cloud.*

![Ansible Ops Platform on GCP: architecture](https://raw.githubusercontent.com/bikram-singh/gcp-awx-ops-automation/main/docs/architecture/architecture-gcp.png)

Building servers is the easy part. The hard part starts the next morning: patching, hardening, health checks, snapshots, and the 3 a.m. "why is that VM stopped?" I lead infrastructure and DevOps for GCP at work, and I wanted one project that shows how I think about that operational work, end to end. So I built it.

The result is a platform where Terraform provisions everything, GitHub Actions delivers it without a single stored key, and AWX (the open-source upstream of Ansible Tower) runs the operations: scheduled, approved, audited, tested, and in two cases, fully event-driven.

## 📖 Introduction

Most teams are good at building infrastructure. Infrastructure as code creates networks, clusters and VMs, and a pipeline applies it. Then the daily running of it begins, and the discipline quietly disappears:

- **Snowflake servers.** Patching and hardening done by hand means no two machines are quite the same.
- **Slow, manual change.** A patch window is a person with a runbook and a terminal. It is slow and easy to get wrong.
- **No audit trail.** Who patched production last Tuesday, and what exactly changed? Often nobody can say.
- **Shared credentials.** The SSH key travels between engineers, chat messages and laptops.
- **Slow incident response.** A stopped VM or a new VM nobody configured waits until somebody notices.

I wanted to answer a simple question: what would the *operations plane* look like if it were built with the same care as the infrastructure itself? Everything created from code, nothing clicked into existence, every action approved or audited, and the routine incidents fixed by the platform before a human gets paged.

So I built **Ansible Ops Platform on GCP**: a private GKE cluster running AWX, a Cloud SQL database on a private IP, a fleet of private VMs, a keyless GitHub Actions pipeline, and an event path that heals and onboards machines on its own. It ran end to end on a real project, `gcp-awx-ops`, and every claim in this article has a screenshot behind it.

### 🧭 What you will learn

- How to deploy **AWX on a private GKE cluster** with Terraform and the AWX Operator, backed by Cloud SQL on a private IP
- How to give GitHub Actions access to GCP with **Workload Identity Federation**, and AWX access to the inventory with **Workload Identity**, so no key exists anywhere
- How to keep the **whole AWX configuration in Git** and re-apply it on every merge
- How to build **staged patching** with snapshots, a dev-first order and a human approval gate
- How to **heal a stopped VM and onboard a new VM** from Cloud Audit Logs through Pub/Sub, with no inbound path into the cluster
- How to **lint, test and harden** with ansible-lint, Molecule and a CIS-style role, and how to prove idempotence
- How to send **useful chat alerts**, and why the AWX Test button misleads you
- What broke along the way, and how I fixed it

### 👥 Who this is for

Platform, DevOps and SRE engineers who already run Terraform and want the operational side of the fleet to be as repeatable as the build side. A working knowledge of GCP, Kubernetes basics and Ansible will help, but each concept is explained before it is used.

### 🎯 Goals and non-goals

**Goals:** provision the whole platform as code with no console clicks; run all routine operations through one control plane with RBAC, audit and credential isolation; make operations self-service, scheduled or event-driven; use keyless authentication from CI to cloud; manage the automation platform itself as code; gate every change with automated quality checks.

**Non-goals:** application CI/CD for business apps, multi-region high availability of AWX (single region and a single replica in the lab), and Windows fleet management.

This article is that build, phase by phase, including what broke.

## 🔑 Key Facts

![Key facts](https://raw.githubusercontent.com/bikram-singh/gcp-awx-ops-automation/main/docs/article/01-key-facts.png)

## ✨ What Makes This Different

![What makes this different](https://raw.githubusercontent.com/bikram-singh/gcp-awx-ops-automation/main/docs/article/02-what-makes-different.png)

## 💡 Why this design: the benefits, mapped to what I built

![Benefits mapped to this build](https://raw.githubusercontent.com/bikram-singh/gcp-awx-ops-automation/main/docs/article/03-why-ansible-ops.png)

## 🏛️ The shape of it

- **Terraform**, five stacks: `platform` (VPC, private GKE, Cloud SQL, image registry), `awx` (the operator and AWX), `fleet` (labelled VMs), `selfheal` (Pub/Sub, log sinks, bridge) and an optional `ingress`.
- **GitHub Actions**: plan on pull request, apply on merge behind an approval, authenticated with Workload Identity Federation. No JSON keys. Separate pipelines for lint, the execution-environment image and AWX configuration.
- **AWX**: job templates, a staged patching workflow, schedules, RBAC and notifications, all created from a YAML file in the repo.

A one-glance picture of how the pieces connect:

```
GitHub Repo --> GitHub Actions --(OIDC)--> GCP
                 |- terraform plan/apply (platform, awx, fleet, selfheal, ingress)
                 |- ansible-lint / molecule, execution-environment build
                 `- AWX config-as-code sync + job trigger
GKE (private) : AWX Operator -> AWX  --> Cloud SQL (PostgreSQL, private IP)
AWX --(IAP / SSH)--> managed VM fleet (labelled web/app/db, dev/prod)
Audit log --> Pub/Sub --> in-cluster bridge --> AWX (heal a stopped VM, onboard a new VM)
```

![Platform diagram](https://raw.githubusercontent.com/bikram-singh/gcp-awx-ops-automation/main/docs/img/platform.png)

## 🧠 The concepts you need (five minutes of theory)

**AWX.** The open-source upstream of Ansible Tower and Red Hat Automation Controller. It adds what a plain `ansible-playbook` command lacks: an inventory, credentials the operators never see, RBAC, schedules, approvals, job history and a REST API. Actions is the delivery pipeline; AWX is the operations plane.

**Workload Identity Federation.** Lets an outside identity, here a GitHub Actions run, act as a GCP service account without a key. Trust is limited to this repository by an attribute condition.

**Workload Identity.** The same idea for pods: AWX reads the Compute API as a read-only service account with no key file.

**Config as code.** AWX settings kept in Git and applied by a playbook using the `awx.awx` collection, so the whole control plane is reproducible and reviewable.

**Dynamic inventory.** Hosts and groups are built from VM labels (`env`, `role`, `patch_group`), so the inventory is never edited by hand.

**Audit-log sink and Pub/Sub.** A sink routes selected audit-log entries (a VM stopped, a VM created) to a Pub/Sub topic, which is the event bus.

**A pull bridge.** A small pod in the cluster pulls events from Pub/Sub and calls the AWX API. Because it *pulls*, AWX needs no public URL.

**Execution environment.** The container image every job runs in. Mine is built with `ansible-builder`, so jobs install nothing at run time.

**Idempotence.** A second run changes nothing. It is how you prove a hardening role is safe to repeat.

And the plan I wrote down before touching anything:

![Job templates at a glance](https://raw.githubusercontent.com/bikram-singh/gcp-awx-ops-automation/main/docs/article/04-templates.png)

## 🔄 The build order (this matters)

```
 bootstrap.sh ──► platform ──► awx ──► fleet ──► AWX config (awx-config)
 (state bucket,    (VPC, GKE,   (operator,  (labelled   (credential, project,
  WIF, deployer)    Cloud SQL)   AWX)        VMs)        inventory, templates)
                                                │
                                                ▼
              selfheal ──► sinks + Pub/Sub + bridge ──► heal / onboard automatically
                                                │
                                                ▼
        lint + Molecule ──► CIS hardening ──► ee-build ──► ingress (optional) ──► alerts ✅
```

Each phase needs the one before it, and each ended with a visible proof. Here is the whole build in one table:

![What was built](https://raw.githubusercontent.com/bikram-singh/gcp-awx-ops-automation/main/docs/article/05-what-was-built.png)

## 🔹 Phase 1: The platform foundation

One bootstrap script, run once, creates the Terraform state bucket, a deployer service account and the Workload Identity Federation pool and provider. It prints four values that go into GitHub as repository variables: `GCP_PROJECT_ID`, `GCP_WIF_PROVIDER`, `GCP_DEPLOYER_SA` and `TF_STATE_BUCKET`. From that moment, GitHub Actions can apply Terraform with no secret stored anywhere.

The `platform` stack builds a VPC with Cloud NAT, firewall rules that allow only IAP and internal traffic, a **private GKE cluster** with Workload Identity, and **Cloud SQL PostgreSQL 15 on a private IP only**. The database password is generated by Terraform straight into Secret Manager. The `awx` stack then installs the AWX Operator with Helm and creates the AWX resource against the external database.

![Private GKE cluster](https://raw.githubusercontent.com/bikram-singh/gcp-awx-ops-automation/main/docs/snapshots/01-platform/01-gke-cluster-overview.png)

![Cloud SQL with a private IP only](https://raw.githubusercontent.com/bikram-singh/gcp-awx-ops-automation/main/docs/snapshots/01-platform/04-cloudsql-private-ip.png)

![Workload Identity Federation pool for GitHub Actions](https://raw.githubusercontent.com/bikram-singh/gcp-awx-ops-automation/main/docs/snapshots/01-platform/07-wif-github-pool.png)

![AWX workloads running in the cluster](https://raw.githubusercontent.com/bikram-singh/gcp-awx-ops-automation/main/docs/snapshots/01-platform/03-awx-workloads-running.png)

The pipeline that delivers all of this: validate, plan on every pull request, and apply on merge **behind the `production` environment approval**, one matrix job per stack.

![The delivery pipelines](https://raw.githubusercontent.com/bikram-singh/gcp-awx-ops-automation/main/docs/article/06-pipelines.png)

### 🔍 Key behaviors I found

**Private cluster, public pipeline.** Hosted GitHub runners must reach the cluster API, so the control-plane endpoint is public but locked to `master_authorized_cidrs`. In production I would use a self-hosted runner or the Connect Gateway and a fully private endpoint. I note this honestly as a lab trade-off.

**AWX never needs a public address.** The pipeline gets cluster credentials, port-forwards to the AWX service, and talks to it locally.

## 🔹 Phase 2: A fleet to manage, and AWX set up

An operations platform with nothing to operate proves nothing, so the `fleet` stack creates six private Debian 12 VMs (`web-dev-01/02`, `app-dev-01`, `db-dev-01`, `web-prod-01`, `app-prod-01`) with **no public IP**. Labels (`env`, `role`, `patch_group`, `ansible_managed`) drive everything that follows. A startup script creates the `ansible` user.

The inventory needed a decision. My organisation policy blocked service account keys, so the usual "upload a JSON key to AWX" route was closed. I used Workload Identity instead: AWX's service accounts impersonate a read-only `awx-inventory` account, and the `google.cloud.gcp_compute` inventory plugin builds groups from labels with no key file anywhere.

In AWX I created the machine credential `fleet-ssh` (stored encrypted), the project `awx-ops-playbooks` from Git, and the inventory `gcp-fleet` with a dynamic GCE source.

![Machine credential fleet-ssh](https://raw.githubusercontent.com/bikram-singh/gcp-awx-ops-automation/main/docs/snapshots/02-awx-setup/02-credential-fleet-ssh.png)

![Groups built from VM labels](https://raw.githubusercontent.com/bikram-singh/gcp-awx-ops-automation/main/docs/snapshots/02-awx-setup/09-inventory-groups.png)

![Six imported hosts](https://raw.githubusercontent.com/bikram-singh/gcp-awx-ops-automation/main/docs/snapshots/02-awx-setup/10-inventory-hosts.png)

Then the first templates: `00 Connectivity check`, `10 Health check` and `20 Patch Linux (rolling)`.

![Connectivity check, every host answered](https://raw.githubusercontent.com/bikram-singh/gcp-awx-ops-automation/main/docs/snapshots/03-first-playbooks/04-job-00-output.png)

![Health report output](https://raw.githubusercontent.com/bikram-singh/gcp-awx-ops-automation/main/docs/snapshots/03-first-playbooks/09-job-10-output.png)

![Rolling patch with reboot and post-check](https://raw.githubusercontent.com/bikram-singh/gcp-awx-ops-automation/main/docs/snapshots/03-first-playbooks/14-job-20-output.png)

### 🔍 Key behaviors I found

**Only labelled VMs are managed.** A VM without `ansible_managed=true` never enters the inventory and is never touched by self-healing. The GKE nodes are safe by construction.

**"Playbook not found."** The first template was created before the project had synced. The fix is an explicit project update that waits, before templates.

## 🔹 Phase 4: Nothing is clicked into existence

AWX is configured by a playbook using the `awx.awx` collection. Credentials, project, inventory, execution environment, templates, workflow, schedule, teams and notifications all live in `awx_config.yml`. A workflow called `awx-config` applies it on every merge and adopts anything I had built by hand, by name. If someone edits AWX in the UI, the next run puts it back.

![awx-config applied](https://raw.githubusercontent.com/bikram-singh/gcp-awx-ops-automation/main/docs/snapshots/05-self-healing-and-onboarding/02-awx-config-run.png)

## 🔹 Principle 2: keyless, private by default

GitHub authenticates to GCP through OIDC. The AWX API is not on the internet, so the workflow gets cluster credentials, port-forwards to the AWX service, and talks to it locally. The VMs have no public IPs.

## 🔹 Daily operations in practice

**Self-service operations.** A GitHub workflow, `ops-trigger`, lets me launch a template by name, with a limit and extra variables, and waits for the result. Jobs 29 and 35 were the first correct runs, after a bug I describe below.

![ops-trigger form for 10 Health check](https://raw.githubusercontent.com/bikram-singh/gcp-awx-ops-automation/main/docs/snapshots/04-ops-trigger-and-patching/01-ops-trigger-form-10.png)

![ops-trigger run summary](https://raw.githubusercontent.com/bikram-singh/gcp-awx-ops-automation/main/docs/snapshots/04-ops-trigger-and-patching/02-ops-trigger-run-10.png)

**Staged patching.** Workflow 50 runs: pre-check, snapshot dev disks, patch dev, verify, then a human approval, then the same for prod. If dev breaks, prod is never touched. Patching is rolling, one host at a time, with a failure threshold of zero. The approval is a real AWX approval node, gated by an RBAC role that operators do not have.

![Workflow 50 graph](https://raw.githubusercontent.com/bikram-singh/gcp-awx-ops-automation/main/docs/snapshots/04-ops-trigger-and-patching/09-workflow-50-graph.png)

![GitHub asks for production approval](https://raw.githubusercontent.com/bikram-singh/gcp-awx-ops-automation/main/docs/snapshots/04-ops-trigger-and-patching/10-github-production-review.png)

![AWX workflow approval: Promote patching to prod?](https://raw.githubusercontent.com/bikram-singh/gcp-awx-ops-automation/main/docs/snapshots/04-ops-trigger-and-patching/12-awx-workflow-approval.png)

![Workflow finished, every node green (workflow 48)](https://raw.githubusercontent.com/bikram-singh/gcp-awx-ops-automation/main/docs/snapshots/04-ops-trigger-and-patching/13-workflow-50-complete.png)

![Pre-patch snapshots in the GCP console](https://raw.githubusercontent.com/bikram-singh/gcp-awx-ops-automation/main/docs/snapshots/04-ops-trigger-and-patching/14-gcp-snapshots-all.png)

Note that there are two approvals: GitHub's `production` environment decides whether the job may be launched, and AWX's approval node decides whether the workflow may continue to prod.

![Patching sequence](https://raw.githubusercontent.com/bikram-singh/gcp-awx-ops-automation/main/docs/img/patching.png)

**Self-healing.** I stop `web-dev-02` on purpose. The Admin Activity audit log records it, a log sink forwards it to Pub/Sub, a small bridge running in the cluster pulls the message and calls the AWX API, and job 138 starts the VM again. About a minute, no human.

![Self-healing sequence](https://raw.githubusercontent.com/bikram-singh/gcp-awx-ops-automation/main/docs/img/selfheal.png)

Here is the event path in seven steps, so you can see where each safety check sits:

1. Someone (or something) runs `compute.instances.stop` on a VM.
2. Cloud Audit Logs records an **Admin Activity** entry. These are on by default and free.
3. A **log sink** with a filter on `compute.instances.stop` and the fleet name regex routes the entry to a Pub/Sub topic. A second sink does the same for `compute.instances.insert`.
4. The **bridge**, a small Python pod using only the standard library, **pulls** the message from a subscription. It authenticates to Pub/Sub with Workload Identity.
5. The bridge reads the event type and the VM name, and checks the VM name against the fleet pattern.
6. It calls the AWX REST API as a user that can run only two templates: `40 Heal` for a stop, `45 Onboard new VM` for an insert, with the limit set to that single host.
7. Only after AWX accepts the launch does the bridge **acknowledge** the message. Server errors are retried and bad events are skipped.

Pulling instead of pushing is the key design decision. A push-style webhook would need a public URL for AWX, a load balancer and a certificate. A pull bridge needs none of those, and it costs almost nothing.

![Stop web-dev-02; the bridge launches the heal job](https://raw.githubusercontent.com/bikram-singh/gcp-awx-ops-automation/main/docs/snapshots/05-self-healing-and-onboarding/03-self-heal-demo.png)

The design keeps this safe. The event scope is Admin Activity `stop` events on VMs matching the fleet name regex, one fixed template, a `selfheal=off` label to opt out, and an idempotent heal playbook (a running VM is a no-op). The bridge's AWX user can run only two templates, so compromising the bridge cannot reach production patching.

**New VMs configure themselves.** I wanted a provisioning callback, the usual answer being an internal load balancer so a booting VM can call AWX. That is about $18 a month for a lab. Instead I added a second log sink for completed VM creations into the same topic. The bridge looks at the event type: a stop launches the heal job, a create launches "45 Onboard new VM". I added one line for `app-dev-02` to the Terraform fleet and merged it. About a minute after Terraform created the VM, job 146 started with the limit set to that single host, waited for SSH, applied the baseline and ran the connectivity and health checks. 16 tasks ok, none failed. The VM was 0.0 hours old.

![Onboarding sequence](https://raw.githubusercontent.com/bikram-singh/gcp-awx-ops-automation/main/docs/img/onboard.png)

![infra run: add app-dev-02 to the fleet](https://raw.githubusercontent.com/bikram-singh/gcp-awx-ops-automation/main/docs/snapshots/05-self-healing-and-onboarding/05-infra-add-app-dev-02.png)

![Onboarding job started by the audit-log event](https://raw.githubusercontent.com/bikram-singh/gcp-awx-ops-automation/main/docs/snapshots/05-self-healing-and-onboarding/06-job-45-onboard-output.png)

**Separation of duties.** Viewers look, operators run, approvers approve production. The auditor role is on the organization, execute rights are per template, and the approval role is only on the workflow.

![RBAC model](https://raw.githubusercontent.com/bikram-singh/gcp-awx-ops-automation/main/docs/img/rbac.png)

## 🛡️ Quality gates and hardening

Config as code is only as good as its checks, so every change to playbooks or roles runs through a `lint` workflow: ansible-lint on the strictest profile, then a Molecule test of each role in a real Debian 12 container with systemd. Molecule converges the role, runs it again to prove it changes nothing, and verifies the result.

The first role is a CIS-aligned baseline: an SSH drop-in (no root login, no passwords, limited tries, idle timeout), kernel network settings, blocked unused filesystems, permissions on sensitive files and a login banner. The SSH file is validated with `sshd -t` before it is installed, so a typo can never lock a host out. I ran the dry-run template first (job 153, check mode, four dev hosts, 6 changes each, no failures), then applied it, then ran the connectivity check to prove AWX could still log in, then applied it to prod (job 177). A final run across the whole fleet showed `changed=0` on all six VMs.

![lint workflow, both jobs green](https://raw.githubusercontent.com/bikram-singh/gcp-awx-ops-automation/main/docs/snapshots/06-hardening-and-lint/02-lint-molecule-green-2.png)

![Dry run diff in check mode (job 153)](https://raw.githubusercontent.com/bikram-singh/gcp-awx-ops-automation/main/docs/snapshots/06-hardening-and-lint/05-job-153-dry-run.png)

![AWX still logs in after hardening (job 165)](https://raw.githubusercontent.com/bikram-singh/gcp-awx-ops-automation/main/docs/snapshots/06-hardening-and-lint/11-job-165-connectivity-after-hardening.png)

![Second run: changed=0 on every host (job 189)](https://raw.githubusercontent.com/bikram-singh/gcp-awx-ops-automation/main/docs/snapshots/06-hardening-and-lint/16-job-189-idempotent.png)

I also built a custom execution environment, the image every AWX job runs in: the AWX base image plus the Google libraries and collections, built by `ansible-builder` in its own workflow and pushed to a private Artifact Registry repository. The GKE nodes already have read access, so AWX pulls it with no stored credential. A small check template proves which image a job really runs in.

![ee-build pushes the image to Artifact Registry](https://raw.githubusercontent.com/bikram-singh/gcp-awx-ops-automation/main/docs/snapshots/07-execution-environment/03-ee-build.png)

![awx-config registers the execution environment](https://raw.githubusercontent.com/bikram-singh/gcp-awx-ops-automation/main/docs/snapshots/07-execution-environment/02-awx-config-ee.png)

## 🔔 Alerts when something fails

AWX notification templates send job failures, "approval needed" requests and, for chosen templates, successes to a chat webhook. They are only created when a secret is set, so the repository works without them.

![Notification template Ops alerts](https://raw.githubusercontent.com/bikram-singh/gcp-awx-ops-automation/main/docs/snapshots/09-notifications/02-awx-notification-template.png)

I tested it with a free Discord server, using its Slack-compatible webhook (add `/slack` to the URL). Two things surprised me:

- **The Test button lies.** AWX's test button sends a generic payload with no `text` field, so Discord rejects it and the badge says Failed. The real alerts carry `text` and work. The only honest test is a real job.
- **Forcing a failure takes care.** I launched the onboarding template for a VM that does not exist, and it still succeeded, twice. The check lives in a play on `localhost`, and my limit excluded it. A limit of `localhost:web-dev-01` made it fail properly.

![Template 45 launch with the localhost limit](https://raw.githubusercontent.com/bikram-singh/gcp-awx-ops-automation/main/docs/snapshots/09-notifications/04-template-45-launch.png)

After that, a red alert for the failed job and a green one for a connectivity check landed in the channel. The links said `towerhost` until I set AWX's URL base from the same domain variable the HTTPS entry uses. I deleted the webhook afterwards, because the URL had been in screenshots.

![Discord channel with a failed and a succeeded alert](https://raw.githubusercontent.com/bikram-singh/gcp-awx-ops-automation/main/docs/snapshots/09-notifications/07-discord-failed-and-success-alerts.png)

## 🚪 An optional front door

By default I reach AWX through a port-forward. For demos I added an optional Terraform stack: a global load balancer, a Google-managed certificate and a Cloud Armor allowlist. It does nothing until you set a domain *and* at least one allowed address. A domain without an allowlist is refused, and `0.0.0.0/0` is refused. AWX can start and stop every server in the fleet, so its login page should not be open to the internet. Pipelines keep using the private tunnel.

I pointed `awx.gcpcloudhub.in` at the load balancer address in my DNS host, and about 80 minutes later the certificate went ACTIVE. The AWX login worked on the first try over HTTPS.

![A record for awx at the DNS host](https://raw.githubusercontent.com/bikram-singh/gcp-awx-ops-automation/main/docs/snapshots/08-https-ingress/02-hostinger-dns-a-record.png)

![Managed certificate: PROVISIONING, then ACTIVE](https://raw.githubusercontent.com/bikram-singh/gcp-awx-ops-automation/main/docs/snapshots/08-https-ingress/04-cli-certificate-provisioning-active.png)

![AWX dashboard at https://awx.gcpcloudhub.in](https://raw.githubusercontent.com/bikram-singh/gcp-awx-ops-automation/main/docs/snapshots/08-https-ingress/06-awx-dashboard-https.png)

## 🔬 Under the hood: four details worth showing

**1. A conditional IAM binding, so AWX can start only fleet VMs.** IAM conditions cannot use regex or `contains`, so the Terraform builds one `endsWith` clause per VM from the fleet map:

```hcl
locals {
  fleet_name_checks = [
    for name, vm in var.fleet :
    "resource.name.endsWith('/zones/${local.region}-${vm.zone}/instances/${name}')"
  ]
  fleet_start_condition = format(
    "resource.type == 'compute.googleapis.com/Instance' && (%s)",
    join(" || ", local.fleet_name_checks)
  )
}

resource "google_project_iam_member" "awx_vm_start" {
  role   = "roles/compute.instanceAdmin.v1"
  member = "serviceAccount:${google_service_account.awx_inventory.email}"
  condition {
    title      = "fleet-vms-only"
    expression = local.fleet_start_condition
  }
}
```

Add a VM to the fleet map and the condition grows with it. The GKE nodes can never match.

**2. The log sink filter.** The sink only forwards the events the bridge cares about:

```
protoPayload.serviceName="compute.googleapis.com"
protoPayload.methodName:"compute.instances.stop"
protoPayload.resourceName=~"/instances/<fleet-name-regex>$"
```

**3. Passing arguments to AWX safely.** My first `ops-trigger` passed `-e key=value`, which Ansible splits on spaces. The fix builds JSON with `jq`:

```bash
ARGS="$(jq -nc --arg t "$TEMPLATE" --arg l "$LIMIT" --arg e "$EXTRA_VARS" \
  '{template: $t, limit: $l, launch_extra_vars: $e}')"
ansible-playbook ansible/awx-config/launch.yml -e "$ARGS"
```

**4. A hardening file that cannot lock you out.** The `cis` role validates the SSH drop-in with `sshd -t` before Ansible installs it:

```yaml
- name: SSH daemon hardening drop-in (checked with sshd -t before it is installed)
  ansible.builtin.copy:
    dest: /etc/ssh/sshd_config.d/50-cis-hardening.conf
    content: |
      PermitRootLogin no
      PasswordAuthentication no
      MaxAuthTries {{ cis_ssh_max_auth_tries }}
    validate: /usr/sbin/sshd -t -f %s
```

If the file is invalid, Ansible refuses to copy it. Add a dry-run template and a connectivity check after the real run, and hardening becomes a boring operation, which is exactly what you want.

## ✅ Proven on the running platform

![Proven on the running platform](https://raw.githubusercontent.com/bikram-singh/gcp-awx-ops-automation/main/docs/article/09-proven.png)

## 🧾 Cheat sheet: gotchas worth remembering

![Gotchas cheat sheet](https://raw.githubusercontent.com/bikram-singh/gcp-awx-ops-automation/main/docs/article/07-gotchas.png)

## 🔧 What broke (the useful part)

1. **Launched the wrong template.** My trigger passed `-e template=10 Health check` and Ansible split on the space, then treated a numeric-looking name as an AWX ID. It quietly ran job 23, a connectivity check. Fix: pass JSON arguments built with `jq`, and assert that the name is not numeric.
2. **"Playbook not found".** The template was created before the project had synced. Fix: an explicit project update that waits, before templates.
3. **A skipped task erased a variable.** In the heal playbook, registering a result on a skipped task overwrote the earlier value. I found it with a mock server before it cost anything.
4. **IAM conditions are not a general language.** I wanted "only these VMs" with `matches`, then `contains`. Neither is supported. Only `==`, `startsWith`, `endsWith` and `extract` are. I generated `endsWith` clauses from the fleet variable instead.
5. **403s for a minute after a deploy.** Pub/Sub IAM propagation. The bridge retried and recovered without duplicate launches.
6. **The linter died with "Could not determine home directory".** Not a lint problem: Microsoft Word's temporary files (`~$SS.docx`) had been committed, and a file name starting with `~` breaks Python's path expansion. Fix: remove them and ignore `~*`.
7. **Molecule failed on `sshd -t`.** Inside a test container sshd has never started, so its runtime directory does not exist. The role was fine; the test setup needed to create `/run/sshd`.
8. **A template that did not accept a limit.** My launcher always passes one, and AWX refuses a limit on a template that does not allow it. A one-line change.

The same list as a table:

![What broke and the fix](https://raw.githubusercontent.com/bikram-singh/gcp-awx-ops-automation/main/docs/article/08-what-broke.png)

## 🔐 Security recap

- **No keys anywhere:** Workload Identity Federation for CI, Workload Identity for pods.
- **Nothing public by default:** private GKE and database, VMs without public IPs, AWX through a tunnel.
- **Least privilege:** the bridge user runs two templates; conditional IAM lets AWX start and snapshot only fleet VMs.
- **Separate duties:** look, operate and approve are different teams.
- **Secrets stay secret:** a webhook URL is a password. Keep it as a GitHub secret, and delete test webhooks. I also checked every screenshot before publishing and removed a password, a private key and a personal IP.

## 🔭 What I would do next

A self-hosted runner or Connect Gateway for a fully private control plane, identity-aware access instead of an IP allowlist, and more roles (user management, certificate checks) on the same pattern.

## 💰 Cost and teardown

GKE nodes and Cloud SQL are the bill. The whole thing destroys in a handful of steps, in reverse order, and I wrote that down so it is a habit, not a hope.

The optional HTTPS entry adds roughly $18 to $25 a month while it is on. The teardown order is `ingress`, `selfheal`, `fleet`, `awx`, `platform`, then snapshots and the optional bootstrap.

## 📸 Snapshots

All 90 screenshots from this build, sorted by phase, are in the repository under `docs/snapshots/`, with a caption for each in `docs/SNAPSHOTS.md`.

## 🎬 The demo, minute by minute

When I present this, the story is one sentence: *servers are easy to build and hard to operate, so I built the platform that runs the operations. Terraform builds it, GitHub Actions delivers it with no stored keys, and AWX runs patching, health checks, snapshots and self-healing with approvals and audit.* The run of show:

![The demo, minute by minute](https://raw.githubusercontent.com/bikram-singh/gcp-awx-ops-automation/main/docs/article/10-demo.png)

For a ten-minute slot I skip the live provisioning merge and the HTTPS page. The strongest moment is always the self-healing one: stop a VM on purpose, watch the AWX Jobs page, and see it running again in about a minute with nobody touching anything.

## 🎯 Wrapping up

The mental model is simple: Terraform builds, Actions delivers, AWX operates, and events let the platform fix the boring incidents itself. In practice the hard part was never one tool; it was the **seams** between them: keyless identity, an AWX nobody can reach from the internet, an event path with no inbound hole, and tests that prove each safety claim. Once those held, adding a new operation is just one more template in a YAML file.

If you run servers, try building the operations plane the way you build the servers. Do it in a throwaway project first.

## 🔗 Repository

🌐 **gcp-awx-ops-automation**: https://github.com/bikram-singh/gcp-awx-ops-automation

Code: https://github.com/bikram-singh/gcp-awx-ops-automation

*Tags: GCP, DevOps, Ansible, Terraform, AWX, SRE*

*Bikram Singh is a GCP Infrastructure & DevOps Lead Engineer.*
