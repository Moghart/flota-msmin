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
