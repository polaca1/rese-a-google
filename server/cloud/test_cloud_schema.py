"""Run against an isolated postgres:17 container, never against user data."""
import pathlib
import subprocess

CONTAINER = "reviewnfcgo-cloud-test"


def sql(value, fails=False):
    result = subprocess.run(
        ["docker", "exec", "-i", CONTAINER, "psql", "-U", "postgres", "-v", "ON_ERROR_STOP=1", "-Atq"],
        input=value, text=True, capture_output=True,
    )
    assert bool(result.returncode) == fails, result.stderr or result.stdout
    return result.stdout.strip()


sql("""
create role anon; create role authenticated;
create schema auth;
create table auth.users(id uuid primary key);
create function auth.uid() returns uuid language sql stable as
 $$select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid$$;
grant usage on schema auth, public to authenticated, anon;
insert into auth.users values ('00000000-0000-0000-0000-000000000001'), ('00000000-0000-0000-0000-000000000002');
""")
sql(pathlib.Path(__file__).with_name("ACTIVAR-DATOS-NUBE.sql").read_text())
A = "00000000-0000-0000-0000-000000000001"
B = "00000000-0000-0000-0000-000000000002"
payload = """'{"schema":1,"application":"reviewNfcGo","records":[]}'::jsonb"""


def as_user(owner, query, fails=False):
    return sql(f"set role authenticated; set request.jwt.claim.sub = '{owner}'; {query}", fails)


as_user(A, f"insert into public.reviewnfcgo_backups(user_id,payload) values('{A}',{payload});")
assert as_user(A, "select count(*) from public.reviewnfcgo_backups;") == "1"
assert as_user(B, "select count(*) from public.reviewnfcgo_backups;") == "0"
as_user(B, f"insert into public.reviewnfcgo_backups(user_id,payload) values('{A}',{payload});", fails=True)
assert as_user(B, f"update public.reviewnfcgo_backups set revision=2 where user_id='{A}' returning revision;") == ""
as_user(A, f"update public.reviewnfcgo_backups set user_id='{B}',revision=2 where user_id='{A}';", fails=True)
as_user(A, f"update public.reviewnfcgo_backups set revision=99 where user_id='{A}';", fails=True)
as_user(A, f"update public.reviewnfcgo_backups set revision=2,payload='{{}}' where user_id='{A}';", fails=True)
for revision in range(2, 6):
    assert as_user(A, f"update public.reviewnfcgo_backups set revision={revision} where user_id='{A}' and revision={revision-1} returning revision;") == str(revision)
assert as_user(A, f"update public.reviewnfcgo_backups set revision=2 where user_id='{A}' and revision=1 returning revision;") == ""
assert as_user(A, "select count(*) from public.reviewnfcgo_backup_history;") == "3"
assert as_user(B, "select count(*) from public.reviewnfcgo_backup_history;") == "0"
as_user(A, "delete from public.reviewnfcgo_backups;", fails=True)
as_user(A, "delete from public.reviewnfcgo_backup_history;", fails=True)
sql("set role anon; select * from public.reviewnfcgo_backups;", fails=True)
print("Postgres: aislamiento de cuentas, acceso anónimo bloqueado, revisiones, conflictos y tres copias anteriores verificados.")
