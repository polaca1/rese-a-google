-- Ejecutar una vez en el SQL Editor del proyecto Supabase de reviewNfcGo.
-- No cambia las cuentas ni borra datos existentes.
begin;
create table if not exists public.reviewnfcgo_backups (
  user_id uuid primary key references auth.users(id) on delete cascade,
  revision bigint not null default 1 check (revision > 0),
  payload jsonb not null check (jsonb_typeof(payload) = 'object'
    and payload @> '{"application":"reviewNfcGo","schema":1}'::jsonb
    and octet_length(payload::text) <= 25000000),
  updated_at timestamptz not null default now()
);
create table if not exists public.reviewnfcgo_backup_history (
  user_id uuid not null references auth.users(id) on delete cascade,
  revision bigint not null,
  payload jsonb not null,
  updated_at timestamptz not null,
  primary key (user_id, revision)
);
alter table public.reviewnfcgo_backups enable row level security;
alter table public.reviewnfcgo_backup_history enable row level security;
revoke all on public.reviewnfcgo_backups from public, anon, authenticated;
revoke all on public.reviewnfcgo_backup_history from public, anon, authenticated;
grant select, insert, update on public.reviewnfcgo_backups to authenticated;
grant select on public.reviewnfcgo_backup_history to authenticated;
drop policy if exists own_backup_read on public.reviewnfcgo_backups;
create policy own_backup_read on public.reviewnfcgo_backups for select to authenticated
  using ((select auth.uid()) = user_id);
drop policy if exists own_backup_insert on public.reviewnfcgo_backups;
create policy own_backup_insert on public.reviewnfcgo_backups for insert to authenticated
  with check ((select auth.uid()) = user_id and revision = 1);
drop policy if exists own_backup_update on public.reviewnfcgo_backups;
create policy own_backup_update on public.reviewnfcgo_backups for update to authenticated
  using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
drop policy if exists own_backup_history on public.reviewnfcgo_backup_history;
create policy own_backup_history on public.reviewnfcgo_backup_history for select to authenticated
  using ((select auth.uid()) = user_id);

-- Conservar tres versiones anteriores sin dar permisos de borrado al cliente.
create or replace function public.reviewnfcgo_archive_backup()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.user_id <> old.user_id or new.revision <> old.revision + 1 then
    raise exception 'Invalid backup revision' using errcode = '23514';
  end if;
  insert into public.reviewnfcgo_backup_history (user_id, revision, payload, updated_at)
    values (old.user_id, old.revision, old.payload, old.updated_at);
  delete from public.reviewnfcgo_backup_history
    where user_id = old.user_id and revision < new.revision - 3;
  new.updated_at := now();
  return new;
end;
$$;
revoke all on function public.reviewnfcgo_archive_backup() from public, anon, authenticated;
drop trigger if exists reviewnfcgo_archive_backup on public.reviewnfcgo_backups;
create trigger reviewnfcgo_archive_backup before update on public.reviewnfcgo_backups
  for each row execute function public.reviewnfcgo_archive_backup();
notify pgrst, 'reload schema';
commit;
