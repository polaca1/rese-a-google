-- Migración aditiva: conserva cuentas, copias y enlaces ya escritos.
-- Ejecutar en el proyecto Supabase de reviewNfcGo, no en una base de otra app.
begin;

create table if not exists public.reviewnfcgo_links (
 id uuid primary key,
 user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
 target_url text not null check (length(target_url) between 9 and 2048 and target_url ~ '^https://[^/@[:space:]]+([/?#].*)?$'),
 active boolean not null default true,
 updated_at timestamptz not null default now()
);
alter table public.reviewnfcgo_links add column if not exists business_id uuid;
alter table public.reviewnfcgo_links add column if not exists label text not null default '';
alter table public.reviewnfcgo_links add column if not exists revision bigint not null default 1;
alter table public.reviewnfcgo_links add column if not exists created_at timestamptz not null default now();
create index if not exists reviewnfcgo_links_owner_business on public.reviewnfcgo_links(user_id, business_id);
create unique index if not exists reviewnfcgo_links_one_business on public.reviewnfcgo_links(user_id, business_id) where business_id is not null;
alter table public.reviewnfcgo_links enable row level security;
revoke all on public.reviewnfcgo_links from public, anon, authenticated;
grant select, insert, update on public.reviewnfcgo_links to authenticated;
drop policy if exists own_link_read on public.reviewnfcgo_links;
create policy own_link_read on public.reviewnfcgo_links for select to authenticated using ((select auth.uid()) = user_id);
drop policy if exists own_link_insert on public.reviewnfcgo_links;
create policy own_link_insert on public.reviewnfcgo_links for insert to authenticated with check ((select auth.uid()) = user_id);
drop policy if exists own_link_update on public.reviewnfcgo_links;
create policy own_link_update on public.reviewnfcgo_links for update to authenticated using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);

create or replace function public.reviewnfcgo_link_revision()
returns trigger language plpgsql set search_path = '' as $$
begin
 if new.id is distinct from old.id or new.user_id is distinct from old.user_id then
  raise exception 'La identidad del enlace no se puede cambiar' using errcode = '42501';
 end if;
 new.revision := old.revision + 1;
 new.updated_at := clock_timestamp();
 return new;
end;
$$;
drop trigger if exists reviewnfcgo_link_revision on public.reviewnfcgo_links;
create trigger reviewnfcgo_link_revision before update on public.reviewnfcgo_links
for each row execute function public.reviewnfcgo_link_revision();
revoke all on function public.reviewnfcgo_link_revision() from public, anon, authenticated;

-- Solo contadores agregados. No guardamos IP, ubicación, cookies ni identificadores de personas.
create table if not exists public.reviewnfcgo_link_daily (
 link_id uuid not null references public.reviewnfcgo_links(id) on delete cascade,
 day date not null,
 opens bigint not null default 0 check (opens >= 0),
 last_opened_at timestamptz not null,
 primary key (link_id, day)
);
-- UUID aleatorio por apertura para no contar dos veces un reintento de red.
create table if not exists public.reviewnfcgo_link_receipts (
 request_id uuid primary key,
 link_id uuid not null references public.reviewnfcgo_links(id) on delete cascade,
 created_at timestamptz not null default now()
);
create index if not exists reviewnfcgo_link_receipts_age on public.reviewnfcgo_link_receipts(created_at);
alter table public.reviewnfcgo_link_daily enable row level security;
alter table public.reviewnfcgo_link_receipts enable row level security;
revoke all on public.reviewnfcgo_link_daily, public.reviewnfcgo_link_receipts from public, anon, authenticated;

-- Mantener el lector antiguo: permite que tarjetas ya escritas sigan abriendo.
create or replace function public.reviewnfcgo_link_destination(p_token uuid)
returns text language sql stable security definer set search_path = '' as $$
 select target_url from public.reviewnfcgo_links where id = p_token and active = true;
$$;
revoke all on function public.reviewnfcgo_link_destination(uuid) from public;
grant execute on function public.reviewnfcgo_link_destination(uuid) to anon, authenticated;

create or replace function public.reviewnfcgo_open_card(p_token uuid, p_request_id uuid)
returns text language plpgsql volatile security definer set search_path = '' as $$
declare
 destination text;
 accepted uuid;
 instant timestamptz := clock_timestamp();
begin
 if p_request_id is null then raise exception 'Falta el identificador de apertura' using errcode = '22023'; end if;
 select target_url into destination from public.reviewnfcgo_links where id = p_token and active = true for share;
 if not found then return null; end if;
 insert into public.reviewnfcgo_link_receipts(request_id, link_id, created_at)
 values (p_request_id, p_token, instant) on conflict (request_id) do nothing returning request_id into accepted;
 if accepted is not null then
  insert into public.reviewnfcgo_link_daily(link_id, day, opens, last_opened_at)
  values (p_token, (instant at time zone 'UTC')::date, 1, instant)
  on conflict (link_id, day) do update set
   opens = public.reviewnfcgo_link_daily.opens + 1,
   last_opened_at = greatest(public.reviewnfcgo_link_daily.last_opened_at, excluded.last_opened_at);
 end if;
 -- Limpieza acotada del recibo técnico; los totales diarios se conservan.
 delete from public.reviewnfcgo_link_receipts where request_id in (
  select request_id from public.reviewnfcgo_link_receipts
  where created_at < instant - interval '7 days' order by created_at limit 100
 );
 return destination;
end;
$$;
revoke all on function public.reviewnfcgo_open_card(uuid, uuid) from public;
grant execute on function public.reviewnfcgo_open_card(uuid, uuid) to anon, authenticated;

create or replace function public.reviewnfcgo_link_stats(p_token uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
 result jsonb;
 today date := (now() at time zone 'UTC')::date;
begin
 if auth.uid() is null or not exists (
  select 1 from public.reviewnfcgo_links where id = p_token and user_id = auth.uid()
 ) then raise exception 'No se puede consultar este enlace' using errcode = '42501'; end if;
 select jsonb_build_object(
  'link_id', p_token,
  'total', coalesce(sum(opens), 0),
  'last_7_days', coalesce(sum(opens) filter (where day >= today - 6), 0),
  'last_30_days', coalesce(sum(opens) filter (where day >= today - 29), 0),
  'last_opened_at', max(last_opened_at),
  'first_recorded_day', min(day),
  'daily', (
   select coalesce(jsonb_agg(jsonb_build_object('day', d.day::date, 'opens', coalesce(s.opens, 0)) order by d.day), '[]'::jsonb)
   from pg_catalog.generate_series(today - 29, today, interval '1 day') d(day)
   left join public.reviewnfcgo_link_daily s on s.link_id = p_token and s.day = d.day::date
  )
 ) into result from public.reviewnfcgo_link_daily where link_id = p_token;
 return result;
end;
$$;
revoke all on function public.reviewnfcgo_link_stats(uuid) from public, anon;
grant execute on function public.reviewnfcgo_link_stats(uuid) to authenticated;

notify pgrst, 'reload schema';
commit;
