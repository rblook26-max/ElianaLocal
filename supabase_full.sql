-- SQL completo para este proyecto (Meridian POS + Supabase)
-- Compatible con Postgres/Supabase

begin;

-- 1) Tabla principal usada por el frontend:
--    supabaseClient.from('branch_state').upsert(...)
--    supabaseClient.from('branch_state').select('payload')...
create table if not exists public.branch_state (
  branch text primary key,
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- 2) Hardening/consistencia (idempotente)
alter table public.branch_state
  add column if not exists payload jsonb not null default '{}'::jsonb,
  add column if not exists created_at timestamptz not null default now(),
  add column if not exists updated_at timestamptz not null default now();

-- Constraint: sucursales válidas para este proyecto
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'branch_state_branch_allowed'
      AND conrelid = 'public.branch_state'::regclass
  ) THEN
    ALTER TABLE public.branch_state
      ADD CONSTRAINT branch_state_branch_allowed
      CHECK (branch IN ('Pudahuel','Maipu','La Reina'));
  END IF;
END
$$;

-- Constraint: payload debe ser objeto JSON
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'branch_state_payload_object'
      AND conrelid = 'public.branch_state'::regclass
  ) THEN
    ALTER TABLE public.branch_state
      ADD CONSTRAINT branch_state_payload_object
      CHECK (jsonb_typeof(payload) = 'object');
  END IF;
END
$$;

-- 3) Índices
create index if not exists idx_branch_state_updated_at
  on public.branch_state (updated_at desc);

-- 4) Trigger para mantener updated_at automáticamente
create or replace function public.tg_set_updated_at_branch_state()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists trg_branch_state_updated_at on public.branch_state;
create trigger trg_branch_state_updated_at
before update on public.branch_state
for each row
execute function public.tg_set_updated_at_branch_state();

-- 5) RLS + políticas para uso directo desde navegador con anon key
alter table public.branch_state enable row level security;

-- Limpieza idempotente de políticas anteriores (si existen)
drop policy if exists branch_state_select on public.branch_state;
drop policy if exists branch_state_insert on public.branch_state;
drop policy if exists branch_state_update on public.branch_state;

create policy branch_state_select
on public.branch_state
for select
to anon, authenticated
using (true);

create policy branch_state_insert
on public.branch_state
for insert
to anon, authenticated
with check (branch IN ('Pudahuel','Maipu','La Reina'));

create policy branch_state_update
on public.branch_state
for update
to anon, authenticated
using (branch IN ('Pudahuel','Maipu','La Reina'))
with check (branch IN ('Pudahuel','Maipu','La Reina'));

-- 6) Grants explícitos
grant usage on schema public to anon, authenticated;
grant select, insert, update on table public.branch_state to anon, authenticated;

-- 7) Semillas opcionales de sucursales
insert into public.branch_state (branch, payload)
values
  ('Pudahuel', '{}'::jsonb),
  ('Maipu', '{}'::jsonb),
  ('La Reina', '{}'::jsonb)
on conflict (branch) do nothing;

commit;
