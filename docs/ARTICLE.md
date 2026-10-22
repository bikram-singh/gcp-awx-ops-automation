# I built the platform that runs my servers: Day-2 operations on GCP with Terraform, GitHub Actions and AWX

*Draft for Medium. Replace each `[SCREENSHOT: ...]` with the image from your SS.docx.*

Building servers is the easy part. The hard part starts the next morning: patching, health checks, snapshots, access, and the 3 a.m. "why is that VM stopped?" I lead infrastructure and DevOps for GCP at work, and I wanted one project that shows how I think about that operational work, end to end. So I built it.

The result is a platform where Terraform provisions everything, GitHub Actions delivers it without a single stored key, and AWX (the open-source upstream of Ansible Tower) runs the operations: scheduled, approved, audited, and in one case, fully self-healing.

[SCREENSHOT: platform.png architecture diagram]

## The shape of it

- **Terraform**, four stacks: `platform` (VPC, private GKE, Cloud SQL), `awx` (the operator and AWX), `fleet` (labelled VMs) and `selfheal` (Pub/Sub, log sink, bridge).
- **GitHub Actions**: plan on pull request, apply on merge behind an approval, authenticated with Workload Identity Federation. No JSON keys.
- **AWX**: job templates, a staged patching workflow, schedules and RBAC, all created from a YAML file in the repo.

## Principle 1: nothing is clicked into existence

AWX is configured by a playbook using the `awx.awx` collection. Credentials, project, inventory, templates, workflow, schedule and teams all live in `awx_config.yml`. A workflow called `awx-config` applies it on every merge and adopts anything I had built by hand, by name. If someone edits AWX in the UI, the next run puts it back.

[SCREENSHOT: awx-config run, green]

## Principle 2: keyless, private by default

GitHub authenticates to GCP through OIDC. The AWX API is not on the internet, so the workflow gets cluster credentials, port-forwards to the AWX service, and talks to it locally. The VMs have no public IPs.

## Day-2 in practice

**Self-service operations.** A GitHub workflow, `ops-trigger`, lets me launch a template by name, with a limit and extra variables, and waits for the result. Job 29 and 35 were the first correct runs, after a bug I describe below.

[SCREENSHOT: ops-trigger form and run]

**Staged patching.** Workflow 50 runs: pre-check, snapshot dev disks, patch dev, verify, then a human approval, then the same for prod. If dev breaks, prod is never touched. Patching is rolling, one host at a time, with a failure threshold of zero. The approval is a real AWX approval node, gated by an RBAC role that operators do not have.

[SCREENSHOT: workflow graph, all green (workflow 48)]
[SCREENSHOT: GCP console, pre-patch snapshots]

**Self-healing.** I stop `web-dev-02` on purpose. The Admin Activity audit log records it, a log sink forwards it to Pub/Sub, a small bridge running in the cluster pulls the message and calls the AWX API, and job 138 starts the VM again. About a minute, no human.

[SCREENSHOT: selfheal.png sequence diagram]
[SCREENSHOT: AWX job 138 output]

**Separation of duties.** Viewers look, operators run, approvers approve production. The auditor role is on the organization, execute rights are per template, and the approval role is only on the workflow.

## What broke (the useful part)

1. **Launched the wrong template.** My trigger passed `-e template=10 Health check` and Ansible split on the space, then treated a numeric-looking name as an AWX ID. It quietly ran job 23, a connectivity check. Fix: pass JSON arguments built with `jq`, and assert that the name is not numeric.
2. **"Playbook not found".** The template was created before the project had synced. Fix: an explicit project update that waits, before templates.
3. **A skipped task erased a variable.** In the heal playbook, registering a result on a skipped task overwrote the earlier value. I found it with a mock server before it cost anything.
4. **IAM conditions are not a general language.** I wanted "only these VMs" with `matches`, then `contains`. Neither is supported. Only `==`, `startsWith`, `endsWith` and `extract` are. I generated `endsWith` clauses from the fleet variable instead.
5. **403s for a minute after a deploy.** Pub/Sub IAM propagation. The bridge retried and recovered without duplicate launches. Worth knowing before you panic.

## What I would do next

A self-hosted runner or Connect Gateway for a fully private control plane, a custom execution environment, Molecule tests, Slack or Teams notifications, and a provisioning callback so new VMs configure themselves on first boot.

## Cost and teardown

GKE nodes and Cloud SQL are the bill. The whole thing destroys in four steps, in reverse order, and I wrote that down so it is a habit, not a hope.

Code: https://github.com/bikram-singh/gcp-awx-ops-automation

*Tags: GCP, DevOps, Ansible, Terraform, AWX, SRE*
