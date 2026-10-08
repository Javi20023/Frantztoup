-- ============================================================================
-- panel_state: persistencia 100% en la nube del estado operativo del panel.
-- Los datos (saldos, ops, log, mvn, nts, inv, cfg) ya no viven en localStorage;
-- cada dispositivo lee/escribe esta fila y se sincroniza en tiempo real.
-- ============================================================================

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

-- mantiene updated_at/updated_by del lado del servidor (fuente de verdad)
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

-- publica la tabla para Realtime (sync entre dispositivos)
do $$
begin
  alter publication supabase_realtime add table public.panel_state;
exception when duplicate_object then
  null;
end $$;