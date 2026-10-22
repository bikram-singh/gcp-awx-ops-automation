# Architecture diagrams

GitHub renders the diagrams below. PNG copies for slides and the article are in [docs/img](img).

## 1. The platform

Everything is private. AWX runs inside a private GKE cluster, reaches its database over a private IP, and manages VMs that have no public address. GitHub deploys with short-lived tokens, so there are no stored keys.

```mermaid
%%{init: {'theme': 'neutral'}}%%
flowchart TB
  subgraph GH["GitHub"]
    direction LR
    repo["Repository<br/>Terraform + Ansible + AWX config"] --> actions["Actions<br/>infra, awx-config, ops-trigger, daily-report"]
  end

  actions -- "short-lived OIDC token, no stored keys" --> wif["Workload Identity Federation"]

  subgraph GCP["GCP project, private VPC"]
    wif --> awx
    subgraph GKE["Private GKE cluster"]
      direction LR
      awx["AWX<br/>web, task, job pods"]
      bridge["selfheal-bridge"]
    end
    awx -- "private IP" --> sql[("Cloud SQL")]
    awx -- "SSH from the IAP range" --> fleet["VM fleet<br/>6 private VMs, no public IP"]
    awx -- "Workload Identity" --> api["Compute API"]
    fleet -- "egress" --> nat["Cloud NAT"]
    api --> logs["Audit log + sink"]
    logs --> topic["Pub/Sub"]
    topic -- "pull" --> bridge
    bridge -- "REST API" --> awx
  end
```

## 2. From a commit to a running system

Infrastructure and AWX configuration are separate pipelines, so changing a template never touches the cluster.

```mermaid
%%{init: {'theme': 'neutral'}}%%
flowchart TD
  push["git push to main"] --> paths{"What changed?"}
  paths -- "terraform/" --> infra["infra workflow"]
  paths -- "ansible/awx-config/" --> cfg["awx-config workflow"]
  infra --> val["validate: fmt, init, validate"]
  val --> appr["apply, one stack at a time<br/>approval on the production environment"]
  appr --> stacks["platform, then awx, fleet, selfheal"]
  cfg --> tunnel["keyless login + kubectl tunnel to private AWX"]
  tunnel --> play["configure.yml<br/>credential, project, inventory, templates,<br/>workflows, schedules, teams"]
  play --> awxok["AWX matches Git"]
  ops["ops-trigger<br/>run from the Actions tab"] --> tunnel2["same tunnel"]
  tunnel2 --> job["launch template, wait for the result"]
```

## 3. Staged patching workflow

Nothing reaches production until dev has been snapshotted, patched, verified, and a person has approved.

```mermaid
%%{init: {'theme': 'neutral'}}%%
flowchart LR
  pre["Pre-check<br/>health, all hosts"] --> sd["Snapshot dev disks"]
  sd --> pd["Patch dev<br/>one host at a time"]
  pd --> vd["Verify dev<br/>strict health check"]
  vd --> ap{{"Approval<br/>Promote to prod?"}}
  ap -- "approve" --> sp["Snapshot prod disks"]
  ap -. "deny" .-> stop(["Stop, prod untouched"])
  sp --> pp["Patch prod<br/>one host at a time"]
  pp --> vp["Verify prod<br/>strict health check"]
  vp --> done(["Done"])
```

## 4. Self-healing

A VM is stopped. About a minute later AWX has started it again, with nobody involved.

```mermaid
%%{init: {'theme': 'neutral'}}%%
sequenceDiagram
  participant U as Person or script
  participant C as Compute Engine
  participant L as Audit log and sink
  participant P as Pub/Sub
  participant B as Bridge (in cluster)
  participant A as AWX
  U->>C: stop web-dev-02
  C->>L: audit entry, stop completed
  L->>P: matching entry published
  B->>P: pull (long poll)
  P-->>B: event with VM name and zone
  B->>A: launch "40 Heal: start stopped VM"
  A->>C: start the VM (Workload Identity token)
  C-->>A: status RUNNING
  B->>P: acknowledge
```

## 5. Who can do what

```mermaid
%%{init: {'theme': 'neutral'}}%%
flowchart LR
  v["ops-readonly"] -- "see everything" --> org["Organization"]
  o["ops-operators"] -- "run" --> safe["connectivity, health,<br/>dry-run patch, snapshots"]
  a["prod-approvers"] -- "approve or deny" --> gate["Promote to prod?"]
  admin["admin"] -. "not used day to day" .-> org
```
