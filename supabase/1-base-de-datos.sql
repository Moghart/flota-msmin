-- Flota MSMIN · Check list diario
-- Pegar completo en Supabase > SQL Editor > New query > Run.
-- Se puede ejecutar más de una vez sin perder datos.

-- ---------- Tablas ----------
create table if not exists public.perfiles (
  id uuid primary key references auth.users(id) on delete cascade,
  usuario text unique not null,
  nombre text not null,
  sap text default '',
  rol text not null default 'conductor' check (rol in ('admin','conductor')),
  activo boolean not null default true,
  ultimo_ingreso timestamptz,
  creado timestamptz not null default now()
);

create table if not exists public.vehiculos (
  patente text primary key,
  interno text default '',
  marca text default '',
  modelo text default '',
  anio int,
  faena text default '',
  km_actual int,
  km_ultima_mant int,
  intervalo_km int not null default 10000,
  vence_rev_tec date,
  vence_extintor date,
  actualizado timestamptz not null default now()
);

create table if not exists public.checks (
  id uuid primary key default gen_random_uuid(),
  fecha timestamptz not null default now(),
  patente text not null references public.vehiculos(patente) on update cascade,
  usuario_id uuid not null default auth.uid() references public.perfiles(id),
  conductor text not null,
  sap text default '',
  km int not null,
  km_mant int,
  combustible int check (combustible between 0 and 100),
  items jsonb not null default '{}',
  fatiga jsonb not null default '{}',
  fatiga_alerta boolean not null default false,
  extintor_vence date,
  obs text default '',
  firma text
);
alter table public.checks add column if not exists tiene_firma boolean generated always as (firma is not null) stored;
create index if not exists checks_fecha_idx on public.checks (fecha desc);
create index if not exists checks_usuario_idx on public.checks (usuario_id, fecha desc);

-- ---------- Funciones de apoyo ----------
create or replace function public.es_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from perfiles where id = auth.uid() and rol = 'admin' and activo);
$$;

create or replace function public.es_activo() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from perfiles where id = auth.uid() and activo);
$$;

-- Al guardar un check, actualiza el km del vehículo si es mayor
create or replace function public.check_actualiza_km() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  update vehiculos set km_actual = new.km, actualizado = now()
   where patente = new.patente and (km_actual is null or km_actual < new.km);
  return new;
end $$;
drop trigger if exists trg_check_km on public.checks;
create trigger trg_check_km after insert on public.checks for each row execute function public.check_actualiza_km();

-- Registra el último ingreso (lo llama la app al entrar)
create or replace function public.marcar_ingreso() returns void
language sql security definer set search_path = public as $$
  update perfiles set ultimo_ingreso = now() where id = auth.uid();
$$;

-- ---------- Permisos (Row Level Security) ----------
alter table public.perfiles enable row level security;
alter table public.vehiculos enable row level security;
alter table public.checks enable row level security;

drop policy if exists perfiles_leer on public.perfiles;
create policy perfiles_leer on public.perfiles for select to authenticated
  using (id = auth.uid() or public.es_admin());
-- Crear, editar y desactivar usuarios solo se hace desde la función admin-usuarios.

drop policy if exists vehiculos_leer on public.vehiculos;
create policy vehiculos_leer on public.vehiculos for select to authenticated using (public.es_activo());
drop policy if exists vehiculos_admin on public.vehiculos;
create policy vehiculos_admin on public.vehiculos for all to authenticated using (public.es_admin()) with check (public.es_admin());

drop policy if exists checks_leer on public.checks;
create policy checks_leer on public.checks for select to authenticated
  using (usuario_id = auth.uid() or public.es_admin());
drop policy if exists checks_crear on public.checks;
create policy checks_crear on public.checks for insert to authenticated
  with check (usuario_id = auth.uid() and public.es_activo());
-- Los checks no se editan ni se borran desde la app (quedan como registro).

grant usage on schema public to authenticated;
grant select on public.perfiles to authenticated;
grant select, insert, update, delete on public.vehiculos to authenticated;
grant select, insert on public.checks to authenticated;
grant execute on function public.es_admin(), public.es_activo(), public.marcar_ingreso() to authenticated;
revoke all on public.perfiles, public.vehiculos, public.checks from anon;
