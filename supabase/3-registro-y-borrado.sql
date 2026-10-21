-- Flota MSMIN · cambios de octubre 2026 (ya aplicados en el proyecto)
-- 1) Se pueden borrar camionetas sin perder su historial de checks
alter table public.checks drop constraint if exists checks_patente_fkey;
alter policy checks_crear on public.checks
  with check (usuario_id = auth.uid() and es_activo() and exists (select 1 from public.vehiculos v where v.patente = checks.patente));

-- 2) RUT y correo en el perfil
alter table public.perfiles add column if not exists rut text not null default '';
alter table public.perfiles add column if not exists email text not null default '';

-- 3) Auto-registro: cada cuenta nueva recibe su perfil como conductor
create or replace function public.crear_perfil_nuevo_usuario()
returns trigger language plpgsql security definer set search_path = public as $$
declare m jsonb := coalesce(new.raw_user_meta_data, '{}'::jsonb);
begin
  insert into perfiles (id, usuario, nombre, sap, rut, email, rol, activo)
  values (new.id,
          case when new.email like '%@flota-msmin.app' then split_part(new.email, '@', 1) else lower(new.email) end,
          coalesce(nullif(trim(m->>'nombre'), ''), split_part(new.email, '@', 1)),
          coalesce(trim(m->>'sap'), ''), coalesce(trim(m->>'rut'), ''),
          case when new.email like '%@flota-msmin.app' then '' else lower(new.email) end,
          'conductor', true)
  on conflict (id) do nothing;
  return new;
end $$;
revoke execute on function public.crear_perfil_nuevo_usuario() from public, anon, authenticated;
drop trigger if exists trg_nuevo_usuario on auth.users;
create trigger trg_nuevo_usuario after insert on auth.users for each row execute function public.crear_perfil_nuevo_usuario();

-- 4) Vencimiento del permiso de circulación
alter table public.vehiculos add column if not exists vence_permiso date;

-- 5) Fechas de vencimiento confirmadas por el conductor en cada check
alter table public.checks add column if not exists rev_tec_vence date;
alter table public.checks add column if not exists permiso_vence date;
create or replace function public.check_actualiza_km()
 returns trigger language plpgsql security definer set search_path to 'public' as $function$
begin
  update vehiculos set km_actual = new.km, actualizado = now()
   where patente = new.patente and (km_actual is null or km_actual < new.km);
  -- Las fechas que confirma el conductor quedan como las vigentes de la camioneta
  update vehiculos set vence_rev_tec = coalesce(new.rev_tec_vence, vence_rev_tec),
                       vence_permiso = coalesce(new.permiso_vence, vence_permiso),
                       vence_extintor = coalesce(new.extintor_vence, vence_extintor),
                       actualizado = now()
   where patente = new.patente and (new.rev_tec_vence is not null or new.permiso_vence is not null or new.extintor_vence is not null);
  return new;
end $function$;

-- 6) Camionetas nuevas creadas desde el check del conductor ("por revisar")
alter table public.checks add column if not exists interno text not null default '';
alter table public.checks add column if not exists vehiculo text not null default '';
alter table public.vehiculos add column if not exists revisar boolean not null default false;
alter policy checks_crear on public.checks with check (usuario_id = auth.uid() and es_activo() and length(patente) between 5 and 8);
create or replace function public.check_actualiza_km()
 returns trigger language plpgsql security definer set search_path to 'public' as $function$
begin
  insert into vehiculos (patente, interno, modelo, km_actual, vence_rev_tec, vence_permiso, vence_extintor, revisar, actualizado)
  values (new.patente, coalesce(new.interno, ''), coalesce(new.vehiculo, ''), new.km, new.rev_tec_vence, new.permiso_vence, new.extintor_vence, true, now())
  on conflict (patente) do nothing;
  update vehiculos set km_actual = new.km, actualizado = now()
   where patente = new.patente and (km_actual is null or km_actual < new.km);
  update vehiculos set vence_rev_tec = coalesce(new.rev_tec_vence, vence_rev_tec),
                       vence_permiso = coalesce(new.permiso_vence, vence_permiso),
                       vence_extintor = coalesce(new.extintor_vence, vence_extintor),
                       interno = case when coalesce(interno, '') = '' then coalesce(new.interno, '') else interno end,
                       actualizado = now()
   where patente = new.patente;
  return new;
end $function$;

-- 7) Km de próxima mantención anotado por el conductor (para precargarlo en el siguiente check)
alter table public.vehiculos add column if not exists km_prox_mant integer;
-- check_actualiza_km() además hace: km_prox_mant = coalesce(nullif(new.km_mant, 0), km_prox_mant)
