# Phase 8: provisioning callback (6b) and notifications (7b)

## 6b. New VMs configure themselves

No load balancer and no extra cost. The self-healing path from Phase 6 already sees every Compute Engine audit event, so a second log sink sends **completed VM creations** to the same Pub/Sub topic.

```
Terraform adds a VM --> audit log (instances.insert, last=true) --> sink awx-onboard-vm-insert
  --> Pub/Sub --> selfheal-bridge --> AWX job "45 Onboard new VM" (limit = the new VM)
```

The bridge looks at the method name: `stop` launches `40 Heal`, `insert` launches `45 Onboard new VM`, anything else is skipped. Only VMs whose name matches `vm_name_regex` (web|app|db-dev|prod-N) are forwarded, so GKE nodes never trigger it.

What `45 Onboard new VM` does (`ansible/playbooks/onboard_vm.yml`):
1. Fails early with a clear message if the VM is not in the inventory (it must be RUNNING and labelled `ansible_managed=true`). AWX refreshes the inventory itself at launch.
2. Waits up to 5 minutes for SSH (the startup script is still creating the `ansible` user).
3. Baseline: installs and enables chrony, writes a "managed by AWX" banner, records the onboarding time.
4. Runs the connectivity check and the health check on that one host.

The `selfheal` AWX user may run templates 40 and 45 and nothing else.

### Roll out

1. Merge to `main`. `infra` applies `selfheal` (second sink, bridge restarts with the new code). `awx-config` creates template 45 and grants the bridge user access. Order does not matter; if the bridge runs first it logs `awx_lookup_error` and skips.
2. Check the bridge: `kubectl -n awx logs deploy/selfheal-bridge --tail=5` shows `onboard_template` set.

### Prove it (about 5 minutes, about 1 cent)

Add one line to `var.fleet` in `terraform/fleet/variables.tf`:

```hcl
"app-dev-02" = { env = "dev", role = "app", patch_group = "a", zone = "a" }
```

Merge. `infra` creates the VM; within a minute AWX shows job **45 Onboard new VM** with limit `app-dev-02`, and the bridge log shows `"action": "onboard"`. Remove the line later to delete the VM again.

## 7b. Notifications

AWX notification template **Ops alerts (webhook)**, attached to every job template and workflow:
- job or workflow **failed**
- workflow **approval needed**, approved, denied, timed out

It is a plain JSON webhook with a `{"text": "..."}` body, which Slack, Mattermost and Teams workflow webhooks accept. It is **only created when the secret exists**. Without it nothing changes.

### Turn it on

1. Create an incoming webhook in your chat tool and copy the URL.
2. GitHub repo, Settings, Secrets and variables, Actions, new repository secret `NOTIFY_WEBHOOK_URL`.
3. Run **awx-config** (Run workflow).
4. In AWX, Administration, Notifications, open "Ops alerts (webhook)" and press the bell/test button. A message should arrive.
5. Real test: in AWX launch `45 Onboard new VM` with limit `web-dev-01` and extra variables `onboard_host: missing-vm`. It fails at the first check and the alert arrives.

The webhook URL is stored as an AWX secret and is never printed in logs (`no_log`). If the message body does not look right in your tool, change the `body` strings under `awx_notifications` in `awx_config.yml`; no other file is involved.

### Email or Teams instead

For email, change `notification_type` to `email` in `configure.yml` and add SMTP settings; for classic Teams connectors use `notification_type: webhook` with the connector's own JSON shape.

## Files changed

- `ansible/playbooks/onboard_vm.yml` (new)
- `ansible/awx-config/awx_config.yml`, `configure.yml`: template 45, bridge permissions, notification template and attachments
- `terraform/selfheal/bridge.py`, `main.tf`, `variables.tf`: second sink and dispatch
- `.github/workflows/awx-config.yml`, `ops-trigger.yml`: `NOTIFY_WEBHOOK_URL` secret, template 45 in the picker
