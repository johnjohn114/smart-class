#!/usr/bin/env python3
"""PostgREST integration using access tokens issued by Supabase GoTrue."""
import concurrent.futures
import json
import os
import urllib.error
import urllib.parse
import urllib.request
import uuid
import time
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

    for rpc_name in ("maintenance_admin_list", "maintenance_event_create",
                     "maintenance_event_update", "maintenance_event_action"):
        status, _ = rpc(rpc_name, {}, None)
        assert_true(status in (401, 403, 404),
                    f"anonymous caller cannot execute {rpc_name} (HTTP {status})")

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

    # Keyset pagination must return every matching event exactly once.
    page_start = datetime.now(timezone.utc) + timedelta(days=45)
    page_end = page_start + timedelta(hours=3)
    page_events = []
    for offset, title in ((0, "Cursor page first"), (1, "Cursor page second")):
        starts_at = page_start + timedelta(hours=offset)
        payload = {
            "title": title,
            "message": "Cursor pagination integration test",
            "is_global": True,
            "scope_codes": [],
            "starts_at": iso(starts_at),
            "ends_at": iso(starts_at + timedelta(minutes=20)),
            "status": "draft",
            "reason": "admin list cursor integration test",
            "idempotency_key": str(uuid.uuid4()),
        }
        status, created = rpc("maintenance_event_create", payload, admin)
        assert_true(status == 200 and created.get("ok") is True,
                    f"created pagination fixture: {title}")
        page_events.append(created["data"]["event_id"])

    list_filter = {
        "from": iso(page_start - timedelta(minutes=1)),
        "to": iso(page_end),
        "limit": 1,
    }
    status, first_page = rpc("maintenance_admin_list", list_filter, admin)
    first_data = first_page.get("data", {}) if isinstance(first_page, dict) else {}
    first_items = first_data.get("events", [])
    cursor = first_data.get("next_cursor")
    assert_true(status == 200 and len(first_items) == 1 and bool(cursor),
                "admin list returns one event and a next_cursor when another page exists")

    second_filter = dict(list_filter)
    second_filter["cursor"] = cursor
    status, second_page = rpc("maintenance_admin_list", second_filter, admin)
    second_data = second_page.get("data", {}) if isinstance(second_page, dict) else {}
    second_items = second_data.get("events", [])
    assert_true(status == 200 and len(second_items) == 1
                and first_items[0]["id"] != second_items[0]["id"]
                and {first_items[0]["id"], second_items[0]["id"]} == set(page_events)
                and not second_data.get("next_cursor"),
                "admin list cursor returns the remaining event exactly once and ends pagination")

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
    event_ids = []
    for item_index in range(2):
        item = dict(base)
        item["status"] = "draft"
        item["idempotency_key"] = str(uuid.uuid4())
        create_status, created = rpc("maintenance_event_create", item, admin)
        assert_true(create_status == 200 and created.get("ok") is True,
                    f"created concurrent schedule draft {item_index + 1}")
        event_ids.append(created["data"]["event_id"])

    def schedule_concurrently(event_id):
        action = {
            "event_id": event_id,
            "expected_version": 1,
            "action": "schedule",
            "reason": "concurrent schedule race test",
            "idempotency_key": str(uuid.uuid4()),
        }
        return rpc("maintenance_event_action", action, admin)

    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
        results = list(pool.map(schedule_concurrently, event_ids))

    successes = [r for r in results if r[0] == 200 and r[1] and r[1].get("ok") is True]
    conflicts = [r for r in results if r[0] in (400, 409, 422)]
    assert_true(
        len(successes) == 1 and len(conflicts) == 1,
        "GoTrue admin tokens preserve the overlapping global schedule concurrency guard",
    )

    # Local-scope overlap must conflict; adjacent half-open windows must not.
    scope_start = datetime.now(timezone.utc) + timedelta(days=4)
    scope_end = scope_start + timedelta(minutes=40)

    def create_scope_draft(title, starts_at, ends_at, scope_codes, is_global=False):
        payload = {
            "title": title,
            "message": "Scope conflict integration test",
            "is_global": is_global,
            "scope_codes": scope_codes,
            "starts_at": iso(starts_at),
            "ends_at": iso(ends_at),
            "status": "draft",
            "reason": "local scope conflict test",
            "idempotency_key": str(uuid.uuid4()),
        }
        status, result = rpc("maintenance_event_create", payload, admin)
        assert_true(status == 200 and result.get("ok") is True,
                    f"created local-scope draft: {title}")
        return result["data"]["event_id"]

    def run_action(event_id, action, version=1):
        payload = {
            "event_id": event_id,
            "expected_version": version,
            "action": action,
            "reason": f"local scope {action} test",
            "idempotency_key": str(uuid.uuid4()),
        }
        return rpc("maintenance_event_action", payload, admin)

    first_local_id = create_scope_draft(
        "Local scope primary", scope_start, scope_end, ["events_competitions"])
    status, first_local = run_action(first_local_id, "schedule")
    assert_true(status == 200 and first_local.get("data", {}).get("status") == "scheduled",
                "first local-scope schedule succeeds")

    overlapping_local_id = create_scope_draft(
        "Local scope overlap", scope_start + timedelta(minutes=10),
        scope_end + timedelta(minutes=10), ["events_competitions"])
    status, overlap_result = run_action(overlapping_local_id, "schedule")
    assert_true(status in (400, 409, 422) and isinstance(overlap_result, dict)
                and overlap_result.get("message") == "CONFLICT",
                f"overlapping events in the same local scope are rejected (HTTP {status}; body={overlap_result!r})")

    adjacent_local_id = create_scope_draft(
        "Local scope adjacent", scope_end, scope_end + timedelta(minutes=20),
        ["events_competitions"])
    status, adjacent_result = run_action(adjacent_local_id, "schedule")
    assert_true(status == 200 and adjacent_result.get("data", {}).get("status") == "scheduled",
                "half-open adjacent local-scope windows do not conflict")

    global_overlap_id = create_scope_draft(
        "Global overlaps local", scope_start + timedelta(minutes=5),
        scope_end - timedelta(minutes=5), [], is_global=True)
    # Convert this draft to global before scheduling; scope_codes remains empty.
    global_update = {
        "event_id": global_overlap_id,
        "expected_version": 1,
        "is_global": True,
        "reason": "global scope conflict test",
        "idempotency_key": str(uuid.uuid4()),
    }
    status, global_updated = rpc("maintenance_event_update", global_update, admin)
    assert_true(status == 200 and global_updated.get("data", {}).get("version") == 2,
                "global conflict fixture is updated")
    status, global_conflict = run_action(global_overlap_id, "schedule", version=2)
    assert_true(status in (400, 409, 422) and isinstance(global_conflict, dict)
                and global_conflict.get("message") == "CONFLICT",
                f"global schedule conflicts with an overlapping local-scope event (HTTP {status}; body={global_conflict!r})")

    # Database-side text length limits must match the admin UI and Edge Function contract.
    length_start = datetime.now(timezone.utc) + timedelta(days=12)
    length_end = length_start + timedelta(minutes=30)
    max_length_payload = {
        "title": "T" * 200,
        "message": "M" * 4000,
        "internal_note": "N" * 4000,
        "is_global": True,
        "scope_codes": [],
        "starts_at": iso(length_start),
        "ends_at": iso(length_end),
        "status": "draft",
        "reason": "R" * 500,
        "idempotency_key": str(uuid.uuid4()),
    }
    status, max_length_result = rpc("maintenance_event_create", max_length_payload, admin)
    assert_true(status == 200 and max_length_result.get("ok") is True,
                "database accepts exact documented maximum lengths for title, message, internal_note and reason")

    for field, too_long in (
        ("title", "T" * 201),
        ("message", "M" * 4001),
        ("internal_note", "N" * 4001),
        ("reason", "R" * 501),
    ):
        invalid_length_payload = dict(max_length_payload)
        invalid_length_payload[field] = too_long
        invalid_length_payload["idempotency_key"] = str(uuid.uuid4())
        status, invalid_length_result = rpc(
            "maintenance_event_create", invalid_length_payload, admin
        )
        assert_true(status in (400, 422),
                    f"database rejects {field} longer than its documented maximum (HTTP {status})")

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

    # A scheduled event whose end time has passed can be completed.
    past_start = datetime.now(timezone.utc) - timedelta(hours=2)
    past_end = past_start + timedelta(minutes=30)
    past_event_payload = {
        "title": "Completed lifecycle fixture",
        "message": "Lifecycle completion test",
        "is_global": True,
        "scope_codes": [],
        "starts_at": iso(past_start),
        "ends_at": iso(past_end),
        "status": "draft",
        "reason": "complete lifecycle integration test",
        "idempotency_key": str(uuid.uuid4()),
    }
    past_event_payload["starts_at"] = iso(datetime.now(timezone.utc) + timedelta(seconds=1))
    past_event_payload["ends_at"] = iso(datetime.now(timezone.utc) + timedelta(seconds=3))
    status, past_event = rpc("maintenance_event_create", past_event_payload, admin)
    assert_true(status == 200 and past_event.get("ok") is True,
                "created a draft for the completion lifecycle test")
    past_event_id = past_event["data"]["event_id"]
    status, past_event_scheduled = rpc("maintenance_event_action", {
        "event_id": past_event_id,
        "expected_version": 1,
        "action": "schedule",
        "reason": "schedule completion lifecycle fixture",
        "idempotency_key": str(uuid.uuid4()),
    }, admin)
    assert_true(status == 200 and past_event_scheduled.get("data", {}).get("status") == "scheduled",
                "completion fixture was scheduled through the lifecycle RPC")
    time.sleep(4)
    complete_request = {
        "event_id": past_event_id,
        "expected_version": 2,
        "action": "complete",
        "reason": "GoTrue complete action test",
        "idempotency_key": str(uuid.uuid4()),
    }
    status, completed = rpc("maintenance_event_action", complete_request, admin)
    assert_true(status == 200 and completed.get("data", {}).get("status") == "completed"
                and completed.get("data", {}).get("version") == 3,
                "ended scheduled event can be completed through lifecycle action RPC")

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


    # Public status is scope-specific and returns only the public field whitelist.
    active_start = datetime.now(timezone.utc) - timedelta(minutes=5)
    active_end = datetime.now(timezone.utc) + timedelta(minutes=30)
    public_scope_payload = {
        "title": "GoTrue CI public scope status",
        "message": "Public scope notice",
        "internal_note": "PRIVATE_NOTE_MUST_NOT_LEAK",
        "is_global": False,
        "scope_codes": ["membership_growth"],
        "starts_at": iso(active_start),
        "ends_at": iso(active_end),
        "status": "draft",
        "reason": "public scope status test",
        "idempotency_key": str(uuid.uuid4()),
    }
    public_scope_payload["starts_at"] = iso(datetime.now(timezone.utc) + timedelta(seconds=1))
    public_scope_payload["ends_at"] = iso(datetime.now(timezone.utc) + timedelta(minutes=30))
    status, active_scope_created = rpc("maintenance_event_create", public_scope_payload, admin)
    assert_true(status == 200 and active_scope_created.get("ok") is True,
                "admin can create a draft for public scope status")
    status, active_scope_scheduled = rpc("maintenance_event_action", {
        "event_id": active_scope_created["data"]["event_id"],
        "expected_version": 1,
        "action": "schedule",
        "reason": "schedule public scope status fixture",
        "idempotency_key": str(uuid.uuid4()),
    }, admin)
    assert_true(status == 200 and active_scope_scheduled.get("data", {}).get("status") == "scheduled",
                "public scope fixture is scheduled through lifecycle RPC")
    time.sleep(2)

    status, matching_scope_status = rpc(
        "maintenance_status_public", {"scope": "membership_growth"}, None
    )
    assert_true(status == 200
                and matching_scope_status.get("data", {}).get("is_maintenance") is True,
                "public status returns an active event for its matching scope")
    assert_true("PRIVATE_NOTE_MUST_NOT_LEAK" not in json.dumps(matching_scope_status),
                "public status response never exposes internal notes")

    status, unrelated_scope_status = rpc(
        "maintenance_status_public", {"scope": "video_content"}, None
    )
    assert_true(status == 200
                and unrelated_scope_status.get("data", {}).get("is_maintenance") is False,
                "public status does not leak an unrelated local-scope event")

    # site_core is a shared scope: an overlapping event in any other local
    # scope must be rejected even though the two named scopes differ.
    site_core_start = scope_start + timedelta(days=2)
    site_core_end = site_core_start + timedelta(minutes=35)
    site_core_id = create_scope_draft(
        "Shared site core", site_core_start, site_core_end, ["site_core"])
    status, site_core_scheduled = run_action(site_core_id, "schedule")
    assert_true(status == 200
                and site_core_scheduled.get("data", {}).get("status") == "scheduled",
                "site_core event can be scheduled")

    unrelated_local_id = create_scope_draft(
        "Site core blocks other local scope",
        site_core_start + timedelta(minutes=5),
        site_core_end - timedelta(minutes=5),
        ["video_content"],
    )
    status, site_core_conflict = run_action(unrelated_local_id, "schedule")
    assert_true(status in (400, 409, 422)
                and isinstance(site_core_conflict, dict)
                and site_core_conflict.get("message") == "CONFLICT",
                "site_core conflicts with every overlapping local scope")

    print("PASS: GoTrue-issued JWT / PostgREST / RPC / role / concurrency / idempotency suite")


if __name__ == "__main__":
    main()
