#!/usr/bin/env python3
"""PostgREST integration using access tokens issued by Supabase GoTrue."""
import concurrent.futures
import json
import os
import urllib.error
import urllib.parse
import urllib.request
import uuid
from datetime import datetime, timedelta, timezone

POSTGREST = os.environ["POSTGREST_URL"].rstrip("/")
GOTRUE = os.environ["GOTRUE_URL"].rstrip("/")


def http_request(base: str, path: str, token: str | None = None, payload=None):
    headers = {"Accept": "application/json"}
    data = None
    method = "GET"
    if token:
        headers["Authorization"] = f"Bearer {token}"
    if payload is not None:
        data = json.dumps(payload).encode()
        headers["Content-Type"] = "application/json"
        method = "POST"
    request = urllib.request.Request(base + path, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(request, timeout=25) as response:
            raw = response.read().decode()
            return response.status, json.loads(raw) if raw else None
    except urllib.error.HTTPError as error:
        raw = error.read().decode(errors="replace")
        try:
            body = json.loads(raw)
        except json.JSONDecodeError:
            body = raw
        return error.code, body


def post_auth(path: str, payload: dict):
    status, body = http_request(GOTRUE, path, payload=payload)
    if status < 200 or status >= 300:
        raise AssertionError(f"GoTrue {path} failed ({status}): {body}")
    return body


def assert_true(condition, message):
    if not condition:
        raise AssertionError(message)
    print(f"PASS: {message}")


def login(email: str, password: str, expected_id: str) -> str:
    result = post_auth(
        "/token?grant_type=password",
        {"email": email, "password": password},
    )
    token = result.get("access_token")
    assert_true(bool(token), f"GoTrue issued an access token for {email.split('@')[0]}")
    status, user = http_request(GOTRUE, "/user", token=token)
    assert_true(status == 200 and user.get("id") == expected_id,
                "GoTrue validates the issued token and returns the matching auth user")
    return token


def rpc(name: str, payload: dict, token: str | None):
    return http_request(POSTGREST, f"/rpc/{name}", token, {"p_request": payload})


def iso(value: datetime) -> str:
    return value.astimezone(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")


def main():
    admin = login(
        os.environ["TEST_ADMIN_EMAIL"],
        os.environ["TEST_ADMIN_PASSWORD"],
        os.environ["TEST_ADMIN_ID"],
    )
    member = login(
        os.environ["TEST_MEMBER_EMAIL"],
        os.environ["TEST_MEMBER_PASSWORD"],
        os.environ["TEST_MEMBER_ID"],
    )

    status, body = rpc("maintenance_status_public", {}, None)
    assert_true(status == 200 and body.get("ok") is True,
                "request without a bearer token maps to anon and public status RPC succeeds")

    status, body = rpc("maintenance_status_public", {}, member)
    assert_true(status == 200 and body.get("ok") is True,
                f"GoTrue-issued member JWT can call the public status RPC (HTTP {status}; body={body!r})")
    assert_true("admin_bypass" not in body.get("data", {}),
                "ordinary member does not receive admin_bypass")

    status, body = rpc("maintenance_status_public", {}, admin)
    assert_true(status == 200 and body.get("ok") is True,
                "GoTrue-issued admin JWT can call the public status RPC")
    assert_true(body.get("data", {}).get("admin_bypass") is True,
                "admin_bypass is derived from the database profile role")

    for rpc_name in ("maintenance_admin_list", "maintenance_event_create",
                     "maintenance_event_update", "maintenance_event_action"):
        status, _ = rpc(rpc_name, {}, member)
        assert_true(status in (400, 401, 403),
                    f"GoTrue-issued non-admin token cannot execute {rpc_name}")

    status, body = rpc("maintenance_admin_list", {}, admin)
    assert_true(status == 200 and body.get("ok") is True,
                "GoTrue-issued admin token can execute the admin list RPC")

    # A modified token must not be accepted by PostgREST.
    tampered = admin[:-1] + ("A" if admin[-1] != "A" else "B")
    status, _ = rpc("maintenance_admin_list", {}, tampered)
    assert_true(status == 401, "tampered GoTrue JWT signature is rejected by PostgREST")

    # private is deliberately not in PGRST_DB_SCHEMAS.
    status, _ = http_request(POSTGREST, "/maintenance_events", admin)
    assert_true(status == 404, "private maintenance tables are not exposed by PostgREST")

    start = datetime.now(timezone.utc) + timedelta(hours=3)
    end = start + timedelta(minutes=30)
    base = {
        "title": "GoTrue CI concurrent maintenance",
        "message": "Concurrent schedule race test",
        "is_global": True,
        "scope_codes": [],
        "starts_at": iso(start),
        "ends_at": iso(end),
        "status": "scheduled",
        "reason": "isolated GoTrue/PostgREST integration test",
    }
    requests = []
    for _ in range(2):
        item = dict(base)
        item["idempotency_key"] = str(uuid.uuid4())
        requests.append(item)

    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
        results = list(pool.map(
            lambda item: rpc("maintenance_event_create", item, admin),
            requests,
        ))

    successes = [r for r in results if r[0] == 200 and r[1] and r[1].get("ok") is True]
    conflicts = [r for r in results if r[0] in (400, 409, 422)]
    assert_true(
        len(successes) == 1 and len(conflicts) == 1,
        "GoTrue admin tokens preserve the overlapping global schedule concurrency guard",
    )

    # A draft create isolates idempotency behavior from schedule conflict checks.
    idem_start = datetime.now(timezone.utc) + timedelta(days=2)
    idem_end = idem_start + timedelta(minutes=45)
    idem_request = {
        "title": "  GoTrue CI idempotency baseline  ",
        "message": "  Idempotency replay test  ",
        "is_global": True,
        "scope_codes": [],
        "starts_at": iso(idem_start),
        "ends_at": iso(idem_end),
        "status": "draft",
        "reason": "  isolated GoTrue/PostgREST idempotency integration test  ",
        "idempotency_key": str(uuid.uuid4()),
    }
    spoofed_create = dict(idem_request)
    spoofed_create["actor_id"] = os.environ["TEST_MEMBER_ID"]
    status, spoofed_body = rpc("maintenance_event_create", spoofed_create, admin)
    assert_true(status == 400,
                f"create RPC rejects caller-supplied actor_id (HTTP {status}; body={spoofed_body!r})")

    status, first = rpc("maintenance_event_create", idem_request, admin)
    assert_true(status == 200 and first and first.get("ok") is True,
                "GoTrue admin can create a draft for idempotency validation")
    # Equivalent semantic request: trim text and use an equivalent UTC offset.
    equivalent_request = dict(idem_request)
    equivalent_request["title"] = "GoTrue CI idempotency baseline"
    equivalent_request["message"] = "Idempotency replay test"
    equivalent_request["reason"] = "isolated GoTrue/PostgREST idempotency integration test"
    equivalent_request["starts_at"] = equivalent_request["starts_at"].replace("Z", "+00:00")
    equivalent_request["ends_at"] = equivalent_request["ends_at"].replace("Z", "+00:00")
    status, replay = rpc("maintenance_event_create", equivalent_request, admin)
    assert_true(status == 200 and replay == first,
                "equivalent normalized request returns the original idempotent response")
    changed_request = dict(idem_request)
    changed_request["title"] = "GoTrue CI changed title"
    status, conflict = rpc("maintenance_event_create", changed_request, admin)
    assert_true(
        status == 400 and isinstance(conflict, dict)
        and conflict.get("message") == "IDEMPOTENCY_KEY_REUSED",
        f"same actor and key with a different payload is rejected (HTTP {status}; body={conflict!r})",
    )

    event_id = first["data"]["event_id"]
    update_request = {
        "event_id": event_id,
        "expected_version": 1,
        "title": "Updated idempotency baseline",
        "reason": "GoTrue update integration test",
        "idempotency_key": str(uuid.uuid4()),
    }
    spoofed_update = dict(update_request)
    spoofed_update["actor_id"] = os.environ["TEST_MEMBER_ID"]
    status, spoofed_body = rpc("maintenance_event_update", spoofed_update, admin)
    assert_true(status == 400,
                f"update RPC rejects caller-supplied actor_id (HTTP {status}; body={spoofed_body!r})")

    status, updated = rpc("maintenance_event_update", update_request, admin)
    assert_true(status == 200 and updated.get("data", {}).get("version") == 2,
                "admin can update an event with the expected version")
    status, update_replay = rpc("maintenance_event_update", update_request, admin)
    assert_true(status == 200 and update_replay == updated,
                "same update key replays the original update response")

    changed_update = dict(update_request)
    changed_update["title"] = "Different update payload"
    status, update_conflict = rpc("maintenance_event_update", changed_update, admin)
    assert_true(status == 400 and isinstance(update_conflict, dict)
                and update_conflict.get("message") == "IDEMPOTENCY_KEY_REUSED",
                "update idempotency key cannot be reused with changed content")

    stale_update = dict(update_request)
    stale_update["expected_version"] = 1
    stale_update["title"] = "Stale version update"
    stale_update["idempotency_key"] = str(uuid.uuid4())
    status, version_conflict = rpc("maintenance_event_update", stale_update, admin)
    assert_true(status == 400 and isinstance(version_conflict, dict)
                and version_conflict.get("message") == "VERSION_CONFLICT",
                "stale expected_version is rejected")

    schedule_request = {
        "event_id": event_id,
        "expected_version": 2,
        "action": "schedule",
        "reason": "GoTrue schedule action test",
        "idempotency_key": str(uuid.uuid4()),
    }
    spoofed_action = dict(schedule_request)
    spoofed_action["actor_id"] = os.environ["TEST_MEMBER_ID"]
    status, spoofed_body = rpc("maintenance_event_action", spoofed_action, admin)
    assert_true(status == 400,
                f"action RPC rejects caller-supplied actor_id (HTTP {status}; body={spoofed_body!r})")

    status, scheduled = rpc("maintenance_event_action", schedule_request, admin)
    assert_true(status == 200 and scheduled.get("data", {}).get("status") == "scheduled"
                and scheduled.get("data", {}).get("version") == 3,
                "draft event can be scheduled through the lifecycle action RPC")
    status, schedule_replay = rpc("maintenance_event_action", schedule_request, admin)
    assert_true(status == 200 and schedule_replay == scheduled,
                "same lifecycle action key replays the original response")

    early_complete_request = {
        "event_id": event_id,
        "expected_version": 3,
        "action": "complete",
        "reason": "early completion must be rejected",
        "idempotency_key": str(uuid.uuid4()),
    }
    status, early_complete = rpc("maintenance_event_action", early_complete_request, admin)
    assert_true(status == 400 and isinstance(early_complete, dict)
                and early_complete.get("message") == "VALIDATION_ERROR",
                "scheduled event cannot be completed before its end time")

    cancel_request = {
        "event_id": event_id,
        "expected_version": 3,
        "action": "cancel",
        "reason": "GoTrue cancel action test",
        "idempotency_key": str(uuid.uuid4()),
    }
    status, cancelled = rpc("maintenance_event_action", cancel_request, admin)
    assert_true(status == 200 and cancelled.get("data", {}).get("status") == "cancelled"
                and cancelled.get("data", {}).get("version") == 4,
                "scheduled event can be cancelled through the lifecycle action RPC")

    print("PASS: GoTrue-issued JWT / PostgREST / RPC / role / concurrency / idempotency suite")


if __name__ == "__main__":
    main()
