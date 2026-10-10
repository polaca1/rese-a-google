-- Ejecutar una sola vez en Supabase > SQL Editor. No modifica cuentas ni copias.
begin;
create table if not exists public.reviewnfcgo_links (
 id uuid primary key,
 user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
 target_url text not null check (length(target_url) between 9 and 2048 and target_url ~ '^https://[^/@[:space:]]+([/?#].*)?$'),
 active boolean not null default true,
 updated_at timestamptz not null default now()
);
alter table public.reviewnfcgo_links enable row level security;
revoke all on public.reviewnfcgo_links from public, anon, authenticated;
grant select, insert, update on public.reviewnfcgo_links to authenticated;
drop policy if exists own_link_read on public.reviewnfcgo_links;
create policy own_link_read on public.reviewnfcgo_links for select to authenticated using ((select auth.uid()) = user_id);
drop policy if exists own_link_insert on public.reviewnfcgo_links;
create policy own_link_insert on public.reviewnfcgo_links for insert to authenticated with check ((select auth.uid()) = user_id);
drop policy if exists own_link_update on public.reviewnfcgo_links;
create policy own_link_update on public.reviewnfcgo_links for update to authenticated using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
-- Solo devuelve el destino de un token aleatorio conocido. No devuelve usuarios ni copias.
create or replace function public.reviewnfcgo_link_destination(p_token uuid)
returns text language sql stable security definer set search_path = '' as $$
 select target_url from public.reviewnfcgo_links where id = p_token and active = true;
$$;
revoke all on function public.reviewnfcgo_link_destination(uuid) from public;
grant execute on function public.reviewnfcgo_link_destination(uuid) to anon, authenticated;
notify pgrst, 'reload schema';
commit;
