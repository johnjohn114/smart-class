#!/usr/bin/env python3
"""Local PostgREST integration test with short-lived CI-only HS256 JWTs.

This validates PostgREST role-claim handling and PostgreSQL RLS in an isolated
CI database. It does not issue tokens through GoTrue/Supabase Auth.
"""
import base64
import concurrent.futures
import hashlib
import hmac
import json
import os
import time
import urllib.error
import urllib.request
import uuid
from datetime import datetime, timedelta, timezone

BASE = os.environ["POSTGREST_URL"].rstrip("/")
SECRET = os.environ["TEST_JWT_SECRET"].encode()
ADMIN = "00000000-0000-4000-8000-000000000001"
MEMBER = "00000000-0000-4000-8000-000000000002"


def b64(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


def token(sub: str | None, role: str = "anon", expired: bool = False) -> str:
    now = int(time.time())
    claims = {
        "iss": "supabase",
        "aud": "authenticated" if role == "authenticated" else "anon",
        "role": role,
        "iat": now - 5,
        "exp": now - 3600 if expired else now + 300,
    }
    if sub:
        claims["sub"] = sub
    head = b64(json.dumps({"alg": "HS256", "typ": "JWT"}, separators=(",", ":")).encode())
    body = b64(json.dumps(claims, separators=(",", ":")).encode())
    signing = f"{head}.{body}".encode()
    signature = hmac.new(SECRET, signing, hashlib.sha256).digest()
    return f"{head}.{body}.{b64(signature)}"


def request(path: str, jwt: str | None = None, payload=None):
    headers = {"Accept": "application/json"}
    if jwt:
        headers["Authorization"] = f"Bearer {jwt}"
    data = None
    if payload is not None:
        data = json.dumps(payload).encode()
        headers["Content-Type"] = "application/json"
    req = urllib.request.Request(BASE + path, data=data, headers=headers, method="POST" if payload is not None else "GET")
    try:
        with urllib.request.urlopen(req, timeout=15) as response:
            raw = response.read().decode()
            return response.status, json.loads(raw) if raw else None
    except urllib.error.HTTPError as error:
        raw = error.read().decode()
        try:
            body = json.loads(raw)
        except json.JSONDecodeError:
            body = raw
        return error.code, body


def rpc(name: str, payload: dict, jwt: str | None):
    return request(f"/rpc/{name}", jwt, {"p_request": payload})


def assert_true(condition, message):
    if not condition:
        raise AssertionError(message)
    print(f"PASS: {message}")


def iso(dt):
    return dt.astimezone(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")


def main():
    anon = token(None, "anon")
    member = token(MEMBER, "authenticated")
    admin = token(ADMIN, "authenticated")
    expired = token(ADMIN, "authenticated", expired=True)

    status, body = rpc("maintenance_status_public", {}, None)
    assert_true(status == 200 and body.get("ok") is True, "no-token request maps to anon and public RPC succeeds")

    status, body = rpc("maintenance_status_public", {}, anon)
    assert_true(status == 200 and body.get("ok") is True, "signed anon JWT can call public status RPC")
    assert_true("internal_note" not in json.dumps(body), "public status response does not disclose internal_note")

    status, _ = rpc("maintenance_admin_list", {}, member)
    assert_true(status in (401, 403), "authenticated non-admin cannot call admin RPC")

    status, body = rpc("maintenance_admin_list", {}, admin)
    assert_true(status == 200 and body.get("ok") is True, "admin JWT can call admin list RPC")

    status, _ = rpc("maintenance_admin_list", {}, expired)
    assert_true(status == 401, "expired JWT is rejected by PostgREST")

    # private schema is deliberately not in PGRST_DB_SCHEMAS.
    status, _ = request("/maintenance_events", admin)
    assert_true(status == 404, "private tables are not exposed through PostgREST")

    # Two simultaneous global maintenance creates overlap in a future window.
    start = datetime.now(timezone.utc) + timedelta(hours=3)
    end = start + timedelta(minutes=30)
    base = {
        "title": "CI concurrent maintenance",
        "message": "Concurrent schedule race test",
        "is_global": True,
        "scope_codes": [],
        "starts_at": iso(start),
        "ends_at": iso(end),
        "status": "scheduled",
        "reason": "isolated concurrent integration test",
    }
    requests = []
    for index in range(2):
        item = dict(base)
        item["idempotency_key"] = str(uuid.uuid4())
        requests.append(item)

    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
        results = list(pool.map(lambda item: rpc("maintenance_event_create", item, admin), requests))

    successes = [r for r in results if r[0] == 200 and r[1] and r[1].get("ok") is True]
    failures = [r for r in results if r[0] in (400, 409, 422)]
    assert_true(len(successes) == 1 and len(failures) == 1,
                "concurrent overlapping global schedules serialize: exactly one succeeds")

    print("PASS: PostgREST JWT/RPC/RLS/concurrency integration suite")


if __name__ == "__main__":
    main()
