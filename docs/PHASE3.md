# Phase 3: quality gates and hardening

Three parts. This page covers 3a (lint, Molecule, hardening role). 3b (custom execution environment) is a separate page.

## 3a-1. Lint on every change

`.github/workflows/lint.yml` runs on pull requests and pushes that touch `ansible/`, `roles/` or `collections/`:

- **ansible-lint** with profile `production` (the strictest). Config is `.ansible-lint` at the repo root.
- **Molecule** for each role: converge, idempotence check (a second run must change nothing), and a verify play.

Run locally: `ansible-lint` from the repo root; `cd roles/cis && molecule test` (needs Docker).

## 3a-2. The `cis` role

`roles/cis/` applies a CIS-aligned baseline for Debian 12:

| Area | What it does |
|---|---|
| SSH | Drop-in `/etc/ssh/sshd_config.d/50-cis-hardening.conf`: no root login, no passwords, 4 auth tries, idle timeout, banner. Validated with `sshd -t` before it is installed, so a bad file can never lock the host out. |
| Kernel network | `/etc/sysctl.d/60-cis.conf`: no redirects or source routing, reverse path filter, SYN cookies, ASLR, no suid core dumps. Applied live except inside containers. |
| Filesystems | Blocks unused modules: cramfs, freevxfs, jffs2, hfs, hfsplus, udf. |
| Permissions | passwd, group, shadow, gshadow, sshd_config. |
| Banner | `/etc/issue` and `/etc/issue.net`. |

Every setting is a role default (`roles/cis/defaults/main.yml`) and can be overridden from AWX extra variables. Tags: `ssh`, `sysctl`, `filesystems`, `permissions`, `banner`.

AWX logs in with a key as a non-root user and uses sudo, so refusing root and passwords does not affect it.

## 3a-3. AWX templates

| Template | Use |
|---|---|
| `61 Harden Linux DEV (dry run)` | Check mode on `env_dev`. Shows what would change. Run this first. |
| `60 Harden Linux (CIS baseline)` | Applies it, one host at a time, stops on the first failure. In ops-trigger it needs a `production` reviewer, like patching. |

## Try it

1. Merge. `lint` runs; `awx-config` creates the two templates.
2. ops-trigger, template `61 Harden Linux DEV (dry run)`, limit `env_dev`. Read the diff.
3. ops-trigger, template `60 Harden Linux (CIS baseline)`, limit `env_dev`. Then run `00 Connectivity check` on `env_dev` to prove AWX can still log in.
4. Run `60` again: every host should report `changed=0`.

Tested here: ansible-lint (production profile) passes, and the role was run twice against a test host (second run `changed=0`) and checked with the same asserts Molecule uses. Molecule itself needs Docker, so its first real run is in the `lint` workflow.

## 3b. Custom execution environment

An execution environment (EE) is the container image AWX runs every job in. The default one is generic. This project builds its own, so the Google libraries and collections are baked in and jobs install nothing at run time.

```
execution-env/ (definition) --ee-build workflow--> Artifact Registry (awx-ee/gcp-ops) --> AWX pulls it --> jobs run in it
```

- `execution-env/execution-environment.yml`: ansible-builder definition, based on `quay.io/ansible/awx-ee:24.6.1` (the AWX version this platform runs). Adds `google-auth`, `google-api-python-client`, `requests` and the collections `google.cloud`, `ansible.posix`, `community.general`.
- `terraform/platform/registry.tf`: the private Docker repository `awx-ee`. The GKE node service account already has `artifactregistry.reader`, so AWX pulls with no stored credential.
- `.github/workflows/ee-build.yml`: builds on changes to `execution-env/`, authenticates keylessly, pushes `:<sha>` and `:latest`.
- `awx_config.yml`: registers the EE in AWX (`gcp-ops-ee`) and attaches it to the new template **05 Execution environment check**. Other templates keep the default EE until you set `use_for_all: true`.

### Roll out (order matters)

1. **Give the deployer account registry access** (once, existing project):

   ```bash
   gcloud projects add-iam-policy-binding gcp-awx-ops \
     --member="serviceAccount:tf-deployer@gcp-awx-ops.iam.gserviceaccount.com" \
     --role="roles/artifactregistry.admin"
   ```

2. Push. `infra` creates the repository (approve `production` for the platform stack).
3. Run **ee-build** (Actions, Run workflow) and wait for green. The first build takes several minutes.
4. Run **awx-config** so the EE is registered.
5. ops-trigger, template `05 Execution environment check`. It should print the ansible-core version and `google-auth ... and the required collections are present`.
6. Optional: set `use_for_all: true` in `awx_config.yml`, merge, and run `10 Health check` to prove the normal templates work in the new image. Setting it back to `false` does not move templates back, so change them in AWX if you want to undo it.

Tested here: the definition renders with ansible-builder, ansible-lint and tofu fmt pass, and the check playbook fails (as it should) where the libraries are missing. The image build and the pull by AWX run for the first time in step 3 and 5.
