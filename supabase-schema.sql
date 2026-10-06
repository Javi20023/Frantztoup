-- ============================================================
-- Frantz TopUp SPA - Esquema de autenticacion (Supabase)
-- Pegar completo en: Supabase Dashboard > SQL Editor > Run
-- ============================================================

-- 1. Tabla de perfiles con rol
-- ------------------------------------------------------------
create table if not exists public.profiles (
  id         uuid primary key references auth.users(id) on delete cascade,
  email      text not null,
  rol        text not null default 'trabajador'
             check (rol in ('admin', 'trabajador')),
  creado_en  timestamptz not null default now()
);

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
  insert into public.profiles (id, email, rol)
  values (new.id, coalesce(new.email, ''), 'trabajador')
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row
  execute function public.handle_new_user();

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
-- por eso un trabajador NO se puede autopromover a admin.
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
