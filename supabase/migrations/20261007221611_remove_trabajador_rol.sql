-- ============================================================
-- 20261007221611: eliminar rol 'trabajador' (solo admin/master)
-- ============================================================

-- 1. Promover cualquier usuario 'trabajador' a 'master'
update public.profiles
set rol = 'master'
where rol = 'trabajador';

-- 2. Recrear la funcion del trigger para insertar 'master' por defecto
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, email, rol)
  values (new.id, coalesce(new.email, ''), 'master')
  on conflict (id) do nothing;
  return new;
end;
$$;

-- 3. Quitar cualquier check de rol existente sobre profiles.rol
do $$
declare r record;
begin
  for r in
    select conname
    from pg_constraint
    where conrelid = 'public.profiles'::regclass
      and contype = 'c'
      and pg_get_constraintdef(oid) ilike '%rol%'
  loop
    execute format('alter table public.profiles drop constraint %I', r.conname);
  end loop;
end $$;

-- 4. Restriccion restringida a admin/master y default 'master'
alter table public.profiles
  add constraint profiles_rol_check check (rol in ('admin', 'master'));

alter table public.profiles
  alter column rol set default 'master';