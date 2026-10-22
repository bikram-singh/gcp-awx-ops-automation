# 📝 I built the Ansible Ops Platform on GCP: Day-2 operations with Terraform, GitHub Actions and AWX

> 🏠 [README](../README.md) · 🏛️ [HLD](HLD.md) · 🗺️ [Architecture](ARCHITECTURE.md) · 🎬 [Demo](DEMO.md) · 💥 [Teardown](TEARDOWN.md) · 📸 [Snapshots](SNAPSHOTS.md)

*Draft for Medium. Replace each `[SCREENSHOT: ...]` with the image from your SS.docx.*

Building servers is the easy part. The hard part starts the next morning: patching, hardening, health checks, snapshots, and the 3 a.m. "why is that VM stopped?" I lead infrastructure and DevOps for GCP at work, and I wanted one project that shows how I think about that operational work, end to end. So I built it.

The result is a platform where Terraform provisions everything, GitHub Actions delivers it without a single stored key, and AWX (the open-source upstream of Ansible Tower) runs the operations: scheduled, approved, audited, tested, and in two cases, fully event-driven.

[SCREENSHOT: platform.png architecture diagram]

## 🧱 The shape of it

- **Terraform**, five stacks: `platform` (VPC, private GKE, Cloud SQL, image registry), `awx` (the operator and AWX), `fleet` (labelled VMs), `selfheal` (Pub/Sub, log sinks, bridge) and an optional `ingress`.
- **GitHub Actions**: plan on pull request, apply on merge behind an approval, authenticated with Workload Identity Federation. No JSON keys. Separate pipelines for lint, the execution-environment image and AWX configuration.
- **AWX**: job templates, a staged patching workflow, schedules, RBAC and notifications, all created from a YAML file in the repo.

## 📐 Principle 1: nothing is clicked into existence

AWX is configured by a playbook using the `awx.awx` collection. Credentials, project, inventory, execution environment, templates, workflow, schedule, teams and notifications all live in `awx_config.yml`. A workflow called `awx-config` applies it on every merge and adopts anything I had built by hand, by name. If someone edits AWX in the UI, the next run puts it back.

[SCREENSHOT: awx-config run, green]

## 📐 Principle 2: keyless, private by default

GitHub authenticates to GCP through OIDC. The AWX API is not on the internet, so the workflow gets cluster credentials, port-forwards to the AWX service, and talks to it locally. The VMs have no public IPs.

## ⚙️ Day-2 in practice

**Self-service operations.** A GitHub workflow, `ops-trigger`, lets me launch a template by name, with a limit and extra variables, and waits for the result. Jobs 29 and 35 were the first correct runs, after a bug I describe below.

[SCREENSHOT: ops-trigger form and run]

**Staged patching.** Workflow 50 runs: pre-check, snapshot dev disks, patch dev, verify, then a human approval, then the same for prod. If dev breaks, prod is never touched. Patching is rolling, one host at a time, with a failure threshold of zero. The approval is a real AWX approval node, gated by an RBAC role that operators do not have.

[SCREENSHOT: workflow graph, all green (workflow 48)]
[SCREENSHOT: GCP console, pre-patch snapshots]

**Self-healing.** I stop `web-dev-02` on purpose. The Admin Activity audit log records it, a log sink forwards it to Pub/Sub, a small bridge running in the cluster pulls the message and calls the AWX API, and job 138 starts the VM again. About a minute, no human.

[SCREENSHOT: selfheal.png sequence diagram]
[SCREENSHOT: AWX job 138 output]

**New VMs configure themselves.** I wanted a provisioning callback, the usual answer being an internal load balancer so a booting VM can call AWX. That is about $18 a month for a lab. Instead I added a second log sink for completed VM creations into the same topic. The bridge looks at the event type: a stop launches the heal job, a create launches "45 Onboard new VM". I added one line for `app-dev-02` to the Terraform fleet and merged it. About a minute after Terraform created the VM, job 146 started with the limit set to that single host, waited for SSH, applied the baseline and ran the connectivity and health checks. 16 tasks ok, none failed. The VM was 0.0 hours old.

[SCREENSHOT: bridge log line with "action": "onboard"]
[SCREENSHOT: AWX job 146 output]

**Separation of duties.** Viewers look, operators run, approvers approve production. The auditor role is on the organization, execute rights are per template, and the approval role is only on the workflow.

## ✅ Quality gates and hardening

Config as code is only as good as its checks, so every change to playbooks or roles runs through a `lint` workflow: ansible-lint on the strictest profile, then a Molecule test of each role in a real Debian 12 container with systemd. Molecule converges the role, runs it again to prove it changes nothing, and verifies the result.

The first role is a CIS-aligned baseline: an SSH drop-in (no root login, no passwords, limited tries, idle timeout), kernel network settings, blocked unused filesystems, permissions on sensitive files and a login banner. The SSH file is validated with `sshd -t` before it is installed, so a typo can never lock a host out. I ran the dry-run template first (job 153, check mode, four dev hosts, 6 changes each, no failures), then applied it, then ran the connectivity check to prove AWX could still log in, then applied it to prod (job 177). A final run across the whole fleet showed `changed=0` on all six VMs.

[SCREENSHOT: lint workflow, both jobs green]
[SCREENSHOT: dry run diff, then the changed=0 recap]

I also built a custom execution environment, the image every AWX job runs in: the AWX base image plus the Google libraries and collections, built by `ansible-builder` in its own workflow and pushed to a private Artifact Registry repository. The GKE nodes already have read access, so AWX pulls it with no stored credential. A small check template proves which image a job really runs in.

[SCREENSHOT: ee-build and the "05 Execution environment check" output]

## 🔔 Alerts when something fails

AWX notification templates send job failures, "approval needed" requests and, for chosen templates, successes to a chat webhook. They are only created when a secret is set, so the repository works without them.

I tested it with a free Discord server, using its Slack-compatible webhook (add `/slack` to the URL). Two things surprised me:

- **The Test button lies.** AWX's test button sends a generic payload with no `text` field, so Discord rejects it and the badge says Failed. The real alerts carry `text` and work. The only honest test is a real job.
- **Forcing a failure takes care.** I launched the onboarding template for a VM that does not exist, and it still succeeded, twice. The check lives in a play on `localhost`, and my limit excluded it. A limit of `localhost:web-dev-01` made it fail properly.

After that, a red alert for the failed job and a green one for a connectivity check landed in the channel. The links said `towerhost` until I set AWX's URL base from the same domain variable the HTTPS entry uses. I deleted the webhook afterwards, because the URL had been in screenshots.

[SCREENSHOT: Discord channel with a failed and a succeeded alert]

## 🚪 An optional front door

By default I reach AWX through a port-forward. For demos I added an optional Terraform stack: a global load balancer, a Google-managed certificate and a Cloud Armor allowlist. It does nothing until you set a domain *and* at least one allowed address. A domain without an allowlist is refused, and `0.0.0.0/0` is refused. AWX can start and stop every server in the fleet, so its login page should not be open to the internet. Pipelines keep using the private tunnel.

I pointed `awx.gcpcloudhub.in` at the load balancer address in my DNS host, and about 80 minutes later the certificate went ACTIVE. The AWX login worked on the first try over HTTPS.

[SCREENSHOT: AWX dashboard at https://awx.gcpcloudhub.in]

## 🔧 What broke (the useful part)

1. **Launched the wrong template.** My trigger passed `-e template=10 Health check` and Ansible split on the space, then treated a numeric-looking name as an AWX ID. It quietly ran job 23, a connectivity check. Fix: pass JSON arguments built with `jq`, and assert that the name is not numeric.
2. **"Playbook not found".** The template was created before the project had synced. Fix: an explicit project update that waits, before templates.
3. **A skipped task erased a variable.** In the heal playbook, registering a result on a skipped task overwrote the earlier value. I found it with a mock server before it cost anything.
4. **IAM conditions are not a general language.** I wanted "only these VMs" with `matches`, then `contains`. Neither is supported. Only `==`, `startsWith`, `endsWith` and `extract` are. I generated `endsWith` clauses from the fleet variable instead.
5. **403s for a minute after a deploy.** Pub/Sub IAM propagation. The bridge retried and recovered without duplicate launches.
6. **The linter died with "Could not determine home directory".** Not a lint problem: Microsoft Word's temporary files (`~$SS.docx`) had been committed, and a file name starting with `~` breaks Python's path expansion. Fix: remove them and ignore `~*`.
7. **Molecule failed on `sshd -t`.** Inside a test container sshd has never started, so its runtime directory does not exist. The role was fine; the test setup needed to create `/run/sshd`.
8. **A template that did not accept a limit.** My launcher always passes one, and AWX refuses a limit on a template that does not allow it. A one-line change.

## 🔭 What I would do next

A self-hosted runner or Connect Gateway for a fully private control plane, identity-aware access instead of an IP allowlist, and more roles (user management, certificate checks) on the same pattern.

## 💰 Cost and teardown

GKE nodes and Cloud SQL are the bill. The whole thing destroys in a handful of steps, in reverse order, and I wrote that down so it is a habit, not a hope.

Code: https://github.com/bikram-singh/gcp-awx-ops-automation

*Tags: GCP, DevOps, Ansible, Terraform, AWX, SRE*

---

<div align="center">

**Maintained by Bikram Singh** · [⬆ Back to README](../README.md)

</div>
