# Optional: HTTPS entry to AWX

By default AWX is private and you reach it with `kubectl port-forward`. This optional stack (`terraform/ingress`) adds a public HTTPS address for people, without changing how GitHub Actions connects (it keeps using the private tunnel).

```
browser --HTTPS--> global load balancer (Google-managed certificate, Cloud Armor allowlist)
        --> network endpoint group --> AWX web pods
```

## Safety rules built in

- **Off by default.** Nothing is created until both `AWX_DOMAIN` and `AWX_ALLOWED_CIDRS` are set.
- **Allowlist is mandatory.** A domain without allowed addresses is refused, and `0.0.0.0/0` is refused. Cloud Armor returns 403 to everyone else.
- **HTTPS only.** Plain HTTP is not served. The certificate is issued and renewed by Google.

## Cost

About $18 a month for the load balancer forwarding rule plus about $5 for the Cloud Armor policy, billed per hour. A few days costs well under a dollar or two. Remove it with the teardown steps when you are done.

## Turn it on

1. Find your public address: `curl ifconfig.me` (use `/32`). Add more ranges for other locations.
2. GitHub, Settings, Secrets and variables, Actions, **Variables**:
   - `AWX_DOMAIN` = `awx.gcpcloudhub.in` (or another name in a domain you control)
   - `AWX_ALLOWED_CIDRS` = `["203.0.113.10/32"]` (your address, as a JSON list)
3. Actions, **infra**, Run workflow, and approve `production`. The `ingress` stack creates the address, certificate, policy, service and ingress.
4. Read the address: in the `ingress` apply log, or `gcloud compute addresses describe awx-ingress-ip --global --format="value(address)"`.
5. **DNS:** create an `A` record for the domain pointing to that address (at your DNS host, or in Cloud DNS if you use it for the domain).
6. Wait. The managed certificate becomes `ACTIVE` only after DNS resolves to the address; this usually takes 10 to 60 minutes. Check:

   ```bash
   gcloud compute ssl-certificates describe awx-cert --global --format="value(managed.status,managed.domainStatus)"
   ```

7. Open `https://<your domain>` from an allowed address and log in as `admin`.

## If something is off

| Symptom | Cause and fix |
|---|---|
| 403 from the address | Your current public address is not in `AWX_ALLOWED_CIDRS`. Update the variable and re-run infra. |
| 502 for the first minutes | The load balancer health check (`/api/v2/ping/`) has not turned healthy yet. Wait, then check Network services, Load balancing, the backend. |
| Certificate stuck in `PROVISIONING` | DNS does not point to the address yet, or has not propagated. |
| Login page loads but login fails with "CSRF" or 403 | AWX sits behind a proxy that ends TLS. Add to the AWX custom resource `extra_settings`: `CSRF_TRUSTED_ORIGINS` containing `https://<your domain>`, and tell me; I will add it to the awx stack. |
| Job output stops streaming | A long-lived connection was cut. The backend timeout is already 3600 s; check that nothing else sits in front. |

## Turn it off

Clear `AWX_DOMAIN` and run infra again, or destroy the `ingress` stack (first in docs/TEARDOWN.md). AWX itself is untouched.

## Not tested here

The stack formats cleanly, but it could not be validated or planned in the build environment (no access to the Terraform provider registry, no cluster). The first real plan is the `infra` run in step 3, and the AWX behavior behind the proxy (CSRF row above) is untested.
