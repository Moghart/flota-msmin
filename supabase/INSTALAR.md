# Conectar la app Flota MSMIN a Supabase

Proyecto: **Check List camionetas** (https://atbsumphjckdhygefuld.supabase.co)

## 1. Crear las tablas (2 min)
Supabase > **SQL Editor** > New query > pega todo `1-base-de-datos.sql` > **Run**.
Crea las tablas `perfiles`, `vehiculos` y `checks`, con permisos:
- Conductor: ve la flota, crea sus checks y ve solo los suyos.
- Administrador: ve y gestiona todo.

## 2. Crear la función de usuarios (3 min)
Supabase > **Edge Functions** > Deploy a new function > **Via Editor**.
- Nombre: `admin-usuarios` (exacto).
- Borra el ejemplo y pega todo `admin-usuarios.ts` > **Deploy**.
Con esta función, los administradores crean, editan, desactivan y cambian la clave de usuarios desde la app.

## 3. Crear el primer administrador (2 min)
1. **Authentication > Users > Add user > Create new user**
   - Email: `admin@flota-msmin.app`
   - Password: la clave que quieras
   - Activa **Auto Confirm User**
2. **SQL Editor** > pega `2-primer-admin.sql` > **Run**.

En la app ingresas con usuario **admin** y esa clave. Los demás usuarios los creas desde la pestaña Usuarios de la app.

## 4. Desactivar el registro público
**Authentication > Sign In / Providers > Email**: desactiva **Allow new users to sign up**.
Así nadie puede crearse una cuenta por su cuenta; solo los administradores desde la app.

## 5. Clave pública de la app
**Project Settings > API Keys**: copia la **publishable key** (o la **anon public**). Esa clave es pública y está hecha para ir en la app.
Nunca compartas la **secret** ni la **service_role**.
