#!/usr/bin/env python3
"""Exercise Deno.serve + real Edge handler + GoTrue + PostgREST in disposable CI."""
import json
import os
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid
from datetime import datetime, timedelta, timezone

GOTRUE = "http://127.0.0.1:9999"
EDGE = "http://127.0.0.1:8002/functions/v1"

def request(url, method="GET", token=None, payload=None):
    headers = {"Accept": "application/json"}
    data = None
    if token:
        headers["Authorization"] = "Bearer " + token
    if payload is not None:
        data = json.dumps(payload).encode()
        headers["Content-Type"] = "application/json"
    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=25) as response:
            raw = response.read().decode()
            return response.status, json.loads(raw) if raw else None
    except urllib.error.HTTPError as error:
        raw = error.read().decode(errors="replace")
        try:
            body = json.loads(raw)
        except json.JSONDecodeError:
            body = raw
        return error.code, body

def check(ok, message):
    if not ok:
        raise AssertionError(message)
    print("PASS: " + message)

def login(email, password, expected_id):
    status, body = request(GOTRUE + "/token?grant_type=password", "POST",
                           payload={"email": email, "password": password})
    check(status == 200 and body.get("access_token"),
          "GoTrue issued a user access token for Edge runtime test")
    token = body["access_token"]
    status, user = request(GOTRUE + "/user", token=token)
    check(status == 200 and user.get("id") == expected_id,
          "GoTrue validates the runtime test access token")
    return token

def main():
    admin = login(os.environ["TEST_ADMIN_EMAIL"], os.environ["TEST_ADMIN_PASSWORD"],
                  os.environ["TEST_ADMIN_ID"])
    member = login(os.environ["TEST_MEMBER_EMAIL"], os.environ["TEST_MEMBER_PASSWORD"],
                   os.environ["TEST_MEMBER_ID"])

    status, body = request(EDGE + "/maintenance-status")
    check(status == 200 and body.get("ok") is True,
          f"Deno Edge handler serves public status without a bearer token (HTTP {status}; body={body!r})")

    status, body = request(EDGE + "/maintenance-admin-list")
    check(status == 401 and body.get("error", {}).get("code") == "UNAUTHENTICATED",
          f"Deno Edge handler rejects an unauthenticated admin-list request (HTTP {status}; body={body!r})")

    status, body = request(EDGE + "/maintenance-admin-list", token=member)
    check(status == 403 and body.get("error", {}).get("code") == "FORBIDDEN",
          "Deno Edge handler rejects a non-admin GoTrue user")

    status, body = request(EDGE + "/maintenance-admin-list", token=admin)
    check(status == 200 and body.get("ok") is True,
          "Deno Edge handler forwards an admin JWT to the admin-list RPC")

    start = datetime.now(timezone.utc) + timedelta(days=400)
    end = start + timedelta(minutes=30)
    iso = lambda value: value.isoformat(timespec="seconds").replace("+00:00", "Z")
    create = {
        "title": "Edge runtime integration fixture",
        "message": "Disposable CI runtime test",
        "internal_note": "must remain private",
        "is_global": True,
        "scope_codes": [],
        "starts_at": iso(start),
        "ends_at": iso(end),
        "status": "draft",
        "reason": "Deno Edge runtime integration test",
        "idempotency_key": str(uuid.uuid4()),
    }
    status, created = request(EDGE + "/maintenance-event-create", "POST", admin, create)
    check(status == 200 and created.get("ok") is True,
          "Deno Edge handler validates and creates an event through PostgREST")
    event_id = created["data"]["event_id"]

    update = {
        "event_id": event_id,
        "expected_version": 1,
        "title": "Edge runtime integration fixture updated",
        "reason": "Deno Edge runtime update test",
        "idempotency_key": str(uuid.uuid4()),
    }
    status, updated = request(EDGE + "/maintenance-event-update", "POST", admin, update)
    check(status == 200 and updated.get("data", {}).get("version") == 2,
          "Deno Edge handler updates an event with optimistic version control")

    action = {
        "event_id": event_id,
        "expected_version": 2,
        "action": "cancel",
        "reason": "Deno Edge runtime lifecycle test",
        "idempotency_key": str(uuid.uuid4()),
    }
    status, cancelled = request(EDGE + "/maintenance-event-action", "POST", admin, action)
    check(status == 200 and cancelled.get("data", {}).get("status") == "cancelled",
          "Deno Edge handler executes the lifecycle action RPC")

    status, rejected = request(EDGE + "/maintenance-event-create", "POST", member, create)
    check(status == 403 and rejected.get("error", {}).get("code") == "FORBIDDEN",
          "Deno Edge handler does not allow non-admin writes")

    bad = dict(create)
    bad["unrecognized_field"] = True
    bad["idempotency_key"] = str(uuid.uuid4())
    status, rejected = request(EDGE + "/maintenance-event-create", "POST", admin, bad)
    check(status == 400 and rejected.get("error", {}).get("code") == "INVALID_REQUEST",
          "Deno Edge handler rejects unknown request fields before database access")

    print("PASS: Deno Edge handler / GoTrue / PostgREST runtime integration suite")

if __name__ == "__main__":
    import urllib.request
    last_error = "no response"
    for _ in range(30):
        try:
            with urllib.request.urlopen("http://127.0.0.1:8002/__health", timeout=3) as response:
                if response.status == 200:
                    break
                last_error = f"HTTP {response.status}"
        except Exception as error:
            last_error = repr(error)
        time.sleep(1)
    else:
        raise SystemExit(f"Deno maintenance runtime did not become ready: {last_error}")
    main()
