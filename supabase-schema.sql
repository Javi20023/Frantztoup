-- ============================================================
-- Frantz TopUp SPA - Esquema de autenticacion (Supabase)
-- Pegar completo en: Supabase Dashboard > SQL Editor > Run
-- ============================================================

-- 0. ESTADO DEL PANEL EN LA NUBE (panel_state)
--    Reemplaza a localStorage. Una fila 'panel' con el estado
--    operativo completo + columnas por dominio. Se sincroniza
--    entre dispositivos via Realtime.
-- ------------------------------------------------------------
create table if not exists public.panel_state (
  id         text primary key default 'panel',
  data       jsonb not null default '{}'::jsonb,
  saldos     jsonb,
  ops        jsonb,
  log        jsonb,
  mvn        jsonb,
  nts        jsonb,
  inv        jsonb,
  cfg        jsonb,
  updated_at timestamptz not null default now(),
  updated_by uuid
);

insert into public.panel_state (id, data)
values ('panel', '{}'::jsonb)
on conflict (id) do nothing;

alter table public.panel_state enable row level security;

revoke all on table public.panel_state from anon, public;
grant select, insert, update on table public.panel_state to authenticated;

create or replace function public.panel_state_touch()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  new.updated_at = now();
  new.updated_by = auth.uid();
  return new;
end;
$$;

drop trigger if exists panel_state_touch_trigger on public.panel_state;
create trigger panel_state_touch_trigger
  before insert or update on public.panel_state
  for each row
  execute function public.panel_state_touch();

-- solo admin o master operan el panel
create or replace function public.es_master()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.profiles
    where id = (select auth.uid())
      and rol in ('admin', 'master')
  );
$$;

revoke all on function public.es_master() from public;
grant execute on function public.es_master() to authenticated;

drop policy if exists "panel_state: lectura" on public.panel_state;
create policy "panel_state: lectura"
  on public.panel_state for select
  to authenticated
  using (true);

drop policy if exists "panel_state: escritura" on public.panel_state;
create policy "panel_state: escritura"
  on public.panel_state for insert
  to authenticated
  with check (public.es_master());

drop policy if exists "panel_state: modificacion" on public.panel_state;
create policy "panel_state: modificacion"
  on public.panel_state for update
  to authenticated
  using (public.es_master())
  with check (public.es_master());

do $$
begin
  alter publication supabase_realtime add table public.panel_state;
exception when duplicate_object then
  null;
end $$;

-- 1. Tabla de perfiles con rol
-- ------------------------------------------------------------
create table if not exists public.profiles (
  id         uuid primary key references auth.users(id) on delete cascade,
  email      text not null,
  rol        text not null default 'master'
             check (rol in ('admin', 'master')),
  full_name  text,
  username   text,
  creado_en  timestamptz not null default now()
);

create unique index if not exists profiles_username_key
  on public.profiles (username)
  where username is not null and username <> '';

-- 1b. MIGRACION para bases ya existentes: elimina el rol 'trabajador'
--     (queda solo 'admin'/'master'). Pega SOLO este bloque en el
--     SQL Editor la primera vez.
-- ------------------------------------------------------------
-- update public.profiles set rol = 'master' where rol = 'trabajador';
-- alter table public.profiles drop constraint if exists profiles_rol_check;
-- alter table public.profiles add constraint profiles_rol_check
--   check (rol in ('admin', 'master'));

-- 2. Funcion security definer - evita la recursion infinita de RLS
--    Si la politica consultara la misma tabla sin esto, Postgres
--    entraria en bucle al evaluar su propia politica.
-- ------------------------------------------------------------
create or replace function public.es_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.profiles
    where id = (select auth.uid())
      and rol = 'admin'
  );
$$;

revoke execute on function public.es_admin() from public;
grant execute on function public.es_admin() to authenticated;

-- 3. Auto-crear el perfil cuando nace el usuario en auth.users
-- ------------------------------------------------------------
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, email, rol, full_name, username)
  values (
    new.id,
    coalesce(new.email, ''),
    'master',
    coalesce(new.raw_user_meta_data->>'full_name', ''),
    coalesce(new.raw_user_meta_data->>'username', '')
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row
  execute function public.handle_new_user();

-- 3b. Login por "usuario o correo": devuelve el email del perfil
--     (security definer para sortear la RLS de perfiles)
-- ------------------------------------------------------------
create or replace function public.email_por_usuario(uname text)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select email
  from public.profiles
  where username = uname
  limit 1;
$$;

revoke execute on function public.email_por_usuario(text) from public;
grant execute on function public.email_por_usuario(text) to authenticated;

-- 4. Row Level Security
--    Sin politicas, la tabla queda cerrada por defecto (lo correcto).
-- ------------------------------------------------------------
alter table public.profiles enable row level security;

revoke all on table public.profiles from anon, authenticated;
grant select, update on table public.profiles to authenticated;

-- Postgres no admite "create policy if not exists",
-- asi que se borra antes de crear. Puede correrse N veces.

-- Cada quien ve su propio perfil
drop policy if exists "perfil propio: lectura" on public.profiles;
create policy "perfil propio: lectura"
on public.profiles for select
to authenticated
using ((select auth.uid()) = id);

-- El admin ve todos los perfiles
drop policy if exists "admin: lectura total" on public.profiles;
create policy "admin: lectura total"
on public.profiles for select
to authenticated
using ((select public.es_admin()));

-- Solo el admin puede cambiar roles.
-- OJO: NO hay politica de update sobre el propio registro,
-- por eso un usuario NO se puede autopromover a admin.
drop policy if exists "admin: actualiza perfiles" on public.profiles;
create policy "admin: actualiza perfiles"
on public.profiles for update
to authenticated
using ((select public.es_admin()))
with check ((select public.es_admin()));

-- ============================================================
-- 5. CUENTA DE ADMIN
--
--    Si la cuenta ya existia ANTES de correr este archivo,
--    el trigger no se disparo y no hay fila en profiles.
--    Este bloque la crea si falta y te promueve a admin.
--
--    1) Cambia el correo por el tuyo
--    2) Ejecuta SOLO este bloque
-- ============================================================
insert into public.profiles (id, email, rol)
select u.id, coalesce(u.email, ''), 'admin'
from auth.users u
where u.email = 'frantztopup@gmail.com'
  and not exists (select 1 from public.profiles p where p.id = u.id)
on conflict (id) do nothing;

update public.profiles
set rol = 'admin'
where email = 'frantztopup@gmail.com';

-- Verificar que quedo bien (debe devolver una fila con rol=admin)
select p.email, p.rol
from public.profiles p
where p.email = 'frantztopup@gmail.com';
