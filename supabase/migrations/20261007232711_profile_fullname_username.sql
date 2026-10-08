-- ============================================================
-- 20261007232711: perfil con nombre completo y usuario;
-- login por "usuario o correo"
-- ============================================================

-- 1. Columnas de perfil
alter table public.profiles
  add column if not exists full_name text,
  add column if not exists username text;

create unique index if not exists profiles_username_key
  on public.profiles (username)
  where username is not null and username <> '';

-- 2. Trigger: al nacer el usuario, toma nombre/usuario de los metadatos
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

-- 3. Login por nombre de usuario: devuelve el email del perfil
--    (security definer para sortear la RLS de perfiles)
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

grant execute on function public.email_por_usuario(text) to authenticated;