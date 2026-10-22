"""Bridge between Pub/Sub and a private AWX.

Runs inside the cluster. It PULLS events from a Pub/Sub subscription (so AWX needs no public address),
and for each "VM stopped" audit-log event launches an AWX job template through the AWX REST API.
Standard library only: the Pub/Sub REST API and the GKE metadata server (Workload Identity) are called directly.
"""
import base64
import json
import os
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

PROJECT = os.environ["GCP_PROJECT"]
SUBSCRIPTION = os.environ["PUBSUB_SUBSCRIPTION"]
AWX_URL = os.environ["AWX_URL"].rstrip("/")
AWX_USER = os.environ["AWX_USER"]
AWX_PASSWORD = os.environ["AWX_PASSWORD"]
TEMPLATE = os.environ["AWX_TEMPLATE"]
PUBSUB = os.environ.get("PUBSUB_ENDPOINT", "https://pubsub.googleapis.com").rstrip("/")
TOKEN_URL = os.environ.get(
    "METADATA_TOKEN_URL",
    "http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token",
)
ONCE = os.environ.get("RUN_ONCE") == "1"  # used by tests: one pull, then exit

RESOURCE = re.compile(r"^projects/([a-z][-a-z0-9]*)/zones/([a-z]+-[a-z]+[0-9]+-[a-z])/instances/([a-z][-a-z0-9]*)$")
_token = {"value": None, "expires": 0.0}


def log(**fields):
    print(json.dumps(fields, sort_keys=True), flush=True)


def gcp_token():
    if _token["value"] and time.time() < _token["expires"] - 60:
        return _token["value"]
    req = urllib.request.Request(TOKEN_URL, headers={"Metadata-Flavor": "Google"})
    with urllib.request.urlopen(req, timeout=10) as resp:
        data = json.load(resp)
    _token["value"] = data["access_token"]
    _token["expires"] = time.time() + int(data.get("expires_in", 300))
    return _token["value"]


def pubsub(method, payload, timeout=95):
    url = "%s/v1/projects/%s/subscriptions/%s:%s" % (PUBSUB, PROJECT, SUBSCRIPTION, method)
    req = urllib.request.Request(
        url,
        data=json.dumps(payload).encode(),
        headers={"Authorization": "Bearer " + gcp_token(), "Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return json.load(resp)


def awx(method, path, payload=None):
    auth = base64.b64encode(("%s:%s" % (AWX_USER, AWX_PASSWORD)).encode()).decode()
    headers = {"Authorization": "Basic " + auth, "Content-Type": "application/json"}
    data = json.dumps(payload).encode() if payload is not None else None
    req = urllib.request.Request(AWX_URL + path, data=data, headers=headers, method=method)
    with urllib.request.urlopen(req, timeout=30) as resp:
        return json.load(resp)


def launch_heal(project, zone, instance):
    found = awx("GET", "/api/v2/job_templates/?name=" + urllib.parse.quote(TEMPLATE))
    if found.get("count") != 1:
        raise LookupError("expected one job template named %r, found %s" % (TEMPLATE, found.get("count")))
    template_id = found["results"][0]["id"]
    job = awx(
        "POST",
        "/api/v2/job_templates/%d/launch/" % template_id,
        {"extra_vars": {"heal_instance": instance, "heal_zone": zone, "gcp_project": project}},
    )
    return job["id"]


def handle(message):
    """Return True when the message is finished with (acknowledge it), False to have it redelivered."""
    try:
        entry = json.loads(base64.b64decode(message["data"]))
    except (ValueError, KeyError):
        log(event="skipped", reason="not a log entry")
        return True
    payload = entry.get("protoPayload", {})
    match = RESOURCE.match(payload.get("resourceName", ""))
    if not match:
        log(event="skipped", reason="no instance in event", resource=payload.get("resourceName"))
        return True
    project, zone, instance = match.groups()
    actor = payload.get("authenticationInfo", {}).get("principalEmail", "unknown")
    try:
        job_id = launch_heal(project, zone, instance)
    except urllib.error.HTTPError as err:
        retry = err.code >= 500 or err.code in (408, 429)
        log(event="awx_http_error", code=err.code, instance=instance, retry=retry)
        return not retry
    except LookupError as err:
        log(event="awx_lookup_error", error=str(err), instance=instance)
        return True
    except (urllib.error.URLError, TimeoutError, OSError) as err:
        log(event="awx_unreachable", error=str(err), instance=instance, retry=True)
        return False
    log(event="launched", job=job_id, instance=instance, zone=zone, stopped_by=actor)
    return True


def main():
    log(event="started", subscription=SUBSCRIPTION, template=TEMPLATE)
    while True:
        try:
            received = pubsub("pull", {"maxMessages": 5}).get("receivedMessages", [])
            done = [item["ackId"] for item in received if handle(item["message"])]
            if done:
                pubsub("acknowledge", {"ackIds": done})
        except Exception as err:  # keep the loop alive across network or auth hiccups
            log(event="loop_error", error=str(err))
            time.sleep(5)
        if ONCE:
            return 0


if __name__ == "__main__":
    sys.exit(main())
