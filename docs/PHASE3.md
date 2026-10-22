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
