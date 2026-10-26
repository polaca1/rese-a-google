"""Execute the production migration against an isolated PostgreSQL container."""
import json
import os
from pathlib import Path
import subprocess
import time
import uuid
from concurrent.futures import ThreadPoolExecutor

import pytest


ROOT = Path(__file__).resolve().parents[2]
A = "11111111-1111-4111-8111-111111111111"
B = "22222222-2222-4222-8222-222222222222"
LINK = "33333333-3333-4333-8333-333333333333"
OTHER = "44444444-4444-4444-8444-444444444444"
GOOGLE = "https://search.google.com/local/writereview?placeid=place-test"


@pytest.fixture(scope="module")
def database():
    name = "reviewnfcgo-stats-test-" + uuid.uuid4().hex[:12]
    env = dict(os.environ)
    for key in ("DOCKER_HOST", "DOCKER_CONTEXT", "DOCKER_TLS", "DOCKER_TLS_VERIFY", "DOCKER_CERT_PATH"):
        env.pop(key, None)
    docker = ["docker", "--host=unix:///var/run/docker.sock"]

    def command(args, **kwargs):
        return subprocess.run(docker + args, env=env, capture_output=True, text=True, **kwargs)

    started = command(["run", "--rm", "--network", "none", "--name", name, "-e", "POSTGRES_HOST_AUTH_METHOD=trust", "-d", "postgres:16-alpine"], timeout=180)
    assert started.returncode == 0, started.stderr

    def sql(query, role=None, owner=None, fail=False):
        prefix = ""
        if role:
            prefix = f"set role {role}; set request.jwt.claim.sub = '{owner or ''}';\n"
        result = command(["exec", "-i", name, "psql", "-U", "postgres", "-d", "postgres", "-X", "-qAt", "-v", "ON_ERROR_STOP=1"], input=prefix + query, timeout=30)
        if fail:
            assert result.returncode != 0, "Expected a permission/validation failure"
        else:
            assert result.returncode == 0, result.stderr
        return result.stdout.strip()

    try:
        for _ in range(60):
            if command(["exec", name, "pg_isready", "-U", "postgres"], timeout=10).returncode == 0:
                break
            time.sleep(1)
        else:
            raise AssertionError("PostgreSQL did not become ready")
        sql(f"""
        create role anon;
        create role authenticated;
        create schema auth;
        create table auth.users(id uuid primary key);
        insert into auth.users values ('{A}'), ('{B}');
        create function auth.uid() returns uuid language sql stable as $$
          select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
        $$;
        grant usage on schema auth, public to anon, authenticated;
        grant execute on function auth.uid() to anon, authenticated;
        """)
        sql((ROOT / "server/cloud/major6/ACTIVAR-ENLACES.sql").read_text())
        # Existing tokens must survive the additive migration.
        sql(f"insert into public.reviewnfcgo_links(id, user_id, target_url) values ('{LINK}','{A}','{GOOGLE}');")
        migration = (ROOT / "server/cloud/major7/ACTIVAR-ESTADISTICAS.sql").read_text()
        sql(migration)
        sql(migration)  # Reapplying is safe.
        sql(f"insert into public.reviewnfcgo_links(id, user_id, target_url) values ('{OTHER}','{B}','https://example.org/other');")
        yield sql
    finally:
        command(["stop", "--time", "2", name], timeout=20)


@pytest.fixture(autouse=True)
def reset_statistics(database):
    database(f"delete from public.reviewnfcgo_link_receipts; delete from public.reviewnfcgo_link_daily; update public.reviewnfcgo_links set active=true, target_url='{GOOGLE}' where id='{LINK}';")


def test_existing_link_and_real_zero(database):
    assert database(f"select public.reviewnfcgo_link_destination('{LINK}');", "anon") == GOOGLE
    stats = json.loads(database(f"select public.reviewnfcgo_link_stats('{LINK}');", "authenticated", A))
    assert stats["total"] == 0
    assert len(stats["daily"]) == 30 and all(day["opens"] == 0 for day in stats["daily"])


def test_opening_is_counted_once_per_request(database):
    event = uuid.uuid4()
    for _ in range(2):
        assert database(f"select public.reviewnfcgo_open_card('{LINK}','{event}');", "anon") == GOOGLE
    stats = json.loads(database(f"select public.reviewnfcgo_link_stats('{LINK}');", "authenticated", A))
    assert stats["total"] == stats["last_7_days"] == stats["last_30_days"] == 1
    assert stats["last_opened_at"] and sum(day["opens"] for day in stats["daily"]) == 1


def test_statistics_and_tables_are_private(database):
    for role, owner in [("anon", None), ("authenticated", B)]:
        database(f"select public.reviewnfcgo_link_stats('{LINK}');", role, owner, fail=True)
    for table in ["reviewnfcgo_link_daily", "reviewnfcgo_link_receipts"]:
        database(f"select * from public.{table};", "anon", fail=True)
        database(f"insert into public.{table} default values;", "authenticated", A, fail=True)
    assert database(f"select count(*) from public.reviewnfcgo_links where id='{LINK}';", "authenticated", B) == "0"


def test_destination_can_change_without_changing_written_token(database):
    revision = database(f"select revision from public.reviewnfcgo_links where id='{LINK}';", "authenticated", A)
    changed = database(f"update public.reviewnfcgo_links set target_url='https://example.org/new' where id='{LINK}' and revision={revision} returning id;", "authenticated", A)
    assert changed == LINK
    assert database(f"select public.reviewnfcgo_link_destination('{LINK}');", "anon") == "https://example.org/new"
    assert database(f"update public.reviewnfcgo_links set target_url='{GOOGLE}' where id='{LINK}' and revision={revision} returning id;", "authenticated", A) == ""
    database(f"update public.reviewnfcgo_links set target_url='{GOOGLE}' where id='{LINK}';", "authenticated", A)


def test_inactive_and_missing_tokens_do_not_redirect_or_count(database):
    before = json.loads(database(f"select public.reviewnfcgo_link_stats('{LINK}');", "authenticated", A))["total"]
    database(f"update public.reviewnfcgo_links set active=false where id='{LINK}';", "authenticated", A)
    assert database(f"select public.reviewnfcgo_open_card('{LINK}','{uuid.uuid4()}');", "anon") == ""
    assert database(f"select public.reviewnfcgo_open_card('{uuid.uuid4()}','{uuid.uuid4()}');", "anon") == ""
    assert json.loads(database(f"select public.reviewnfcgo_link_stats('{LINK}');", "authenticated", A))["total"] == before
    database(f"update public.reviewnfcgo_links set active=true where id='{LINK}';", "authenticated", A)


def test_tenant_cannot_change_token_or_owner(database):
    database(f"update public.reviewnfcgo_links set user_id='{B}' where id='{LINK}';", "authenticated", A, fail=True)
    database(f"update public.reviewnfcgo_links set id='{uuid.uuid4()}' where id='{LINK}';", "authenticated", A, fail=True)
    assert database(f"update public.reviewnfcgo_links set active=false where id='{LINK}' returning id;", "authenticated", B) == ""


def test_legacy_preview_does_not_inflate_statistics(database):
    before = json.loads(database(f"select public.reviewnfcgo_link_stats('{LINK}');", "authenticated", A))["total"]
    database(f"select public.reviewnfcgo_link_destination('{LINK}');", "anon")
    assert json.loads(database(f"select public.reviewnfcgo_link_stats('{LINK}');", "authenticated", A))["total"] == before


def test_concurrent_openings_do_not_lose_counts(database):
    events = [uuid.uuid4() for _ in range(12)]
    def opening(event):
        return database(f"select public.reviewnfcgo_open_card('{LINK}','{event}');", "anon")
    with ThreadPoolExecutor(max_workers=4) as pool:
        assert all(result == GOOGLE for result in pool.map(opening, events))
    value = json.loads(database(f"select public.reviewnfcgo_link_stats('{LINK}');", "authenticated", A))
    assert value["total"] == 12


def test_receipt_retention_does_not_erase_lifetime_totals(database):
    old = uuid.uuid4()
    database(f"insert into public.reviewnfcgo_link_receipts values ('{old}','{LINK}',now()-interval '8 days');")
    database(f"insert into public.reviewnfcgo_link_daily values ('{LINK}',(now() at time zone 'UTC')::date-60,12,now()-interval '60 days');")
    database(f"select public.reviewnfcgo_open_card('{LINK}','{uuid.uuid4()}');", "anon")
    assert database(f"select count(*) from public.reviewnfcgo_link_receipts where request_id='{old}';") == "0"
    value = json.loads(database(f"select public.reviewnfcgo_link_stats('{LINK}');", "authenticated", A))
    assert value["total"] == 13 and value["last_30_days"] == 1
