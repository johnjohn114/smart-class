#!/usr/bin/env python3
"""Create ephemeral test identities through GoTrue's public signup endpoint."""
import json
import os
import secrets
import urllib.error
import urllib.request

BASE = os.environ["GOTRUE_URL"].rstrip("/")
RUN_ID = os.environ.get("GITHUB_RUN_ID", "local")
SUFFIX = os.environ.get("GITHUB_RUN_ATTEMPT", "1")


def post(path: str, payload: dict) -> dict:
    request = urllib.request.Request(
        BASE + path,
        data=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=20) as response:
            return json.loads(response.read().decode())
    except urllib.error.HTTPError as error:
        detail = error.read().decode(errors="replace")
        raise RuntimeError(f"GoTrue signup failed ({error.code}): {detail}") from error


def create_user(label: str, role: str) -> tuple[str, str, str]:
    email = f"maintenance-{label}-{RUN_ID}-{SUFFIX}@example.com"
    password = secrets.token_urlsafe(32)
    result = post("/signup", {"email": email, "password": password})
    user = result.get("user") if isinstance(result.get("user"), dict) else result
    user_id = user.get("id") if isinstance(user, dict) else None
    if not user_id:
        raise RuntimeError(f"GoTrue signup did not return a user id for {role}")
    return email, password, user_id


admin = create_user("admin", "admin")
member = create_user("member", "member")

# These credentials exist only in the disposable CI GoTrue database. Mask them
# before later steps inherit them through GITHUB_ENV.
for password in (admin[1], member[1]):
    print(f"::add-mask::{password}")

env_path = os.environ.get("GITHUB_ENV")
if not env_path:
    raise RuntimeError("GITHUB_ENV is required for this CI provisioning step")

with open(env_path, "a", encoding="utf-8") as env:
    for key, value in (
        ("TEST_ADMIN_EMAIL", admin[0]),
        ("TEST_ADMIN_PASSWORD", admin[1]),
        ("TEST_ADMIN_ID", admin[2]),
        ("TEST_MEMBER_EMAIL", member[0]),
        ("TEST_MEMBER_PASSWORD", member[1]),
        ("TEST_MEMBER_ID", member[2]),
    ):
        env.write(f"{key}={value}\n")

print("PASS: two ephemeral users were created by GoTrue signup")
