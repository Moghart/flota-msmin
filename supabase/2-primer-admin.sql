-- Ejecutar DESPUÉS de crear el usuario en Authentication > Users > Add user > Create new user:
--   Email: admin@flota-msmin.app   ·  Password: la clave que quieras  ·  Auto Confirm User: activado
-- Luego pega esto en el SQL Editor y presiona Run.
insert into public.perfiles (id, usuario, nombre, rol)
select id, 'admin', 'Administrador', 'admin' from auth.users where email = 'admin@flota-msmin.app'
on conflict (id) do update set rol = 'admin', activo = true;
