// Supabase Edge Function: admin-usuarios
// Crea y edita usuarios de la app Flota MSMIN. Solo la pueden usar administradores activos.
// La función valida la sesión de quien llama (por eso verify_jwt está desactivado).
import { createClient } from "npm:@supabase/supabase-js@2.45.4";

const DOMINIO = "flota-msmin.app"; // los usuarios entran con "usuario"; internamente es usuario@flota-msmin.app
const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const resp = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });
const normUser = (u: unknown) => String(u ?? "").trim().toLowerCase().replace(/[.\s-]/g, "");

function claveServicio(): string {
  const legacy = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (legacy) return legacy;
  const raw = Deno.env.get("SUPABASE_SECRET_KEYS");
  if (raw) {
    try { const o = JSON.parse(raw); const v = Object.values(o)[0]; if (typeof v === "string") return v; } catch { return raw; }
  }
  throw new Error("Falta la clave de servicio del proyecto.");
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  try {
    const url = Deno.env.get("SUPABASE_URL")!;
    const admin = createClient(url, claveServicio(), { auth: { persistSession: false, autoRefreshToken: false } });

    // Quién llama
    const jwt = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
    if (!jwt) return resp({ error: "Tu sesión expiró. Vuelve a ingresar." }, 401);
    const { data: quien, error: eQuien } = await admin.auth.getUser(jwt);
    if (eQuien || !quien?.user) return resp({ error: "Tu sesión expiró. Vuelve a ingresar." }, 401);
    const { data: yo } = await admin.from("perfiles").select("id,rol,activo").eq("id", quien.user.id).maybeSingle();
    if (!yo || yo.rol !== "admin" || !yo.activo) return resp({ error: "Solo un administrador puede gestionar usuarios." }, 403);

    const b = await req.json();
    const usuario = normUser(b.usuario);
    const nombre = String(b.nombre ?? "").trim();
    const rol = b.rol === "admin" ? "admin" : "conductor";
    const sap = String(b.sap ?? "").trim();

    if (b.accion === "crear") {
      if (usuario.length < 3 || !/^[a-z0-9_]+$/.test(usuario)) return resp({ error: "El usuario debe tener al menos 3 letras o números, sin espacios (puede ser el RUT sin puntos ni guion)." }, 400);
      if (!nombre) return resp({ error: "Escribe el nombre de la persona." }, 400);
      if (!b.clave || String(b.clave).length < 6) return resp({ error: "La clave debe tener al menos 6 caracteres." }, 400);
      const { data: ex } = await admin.from("perfiles").select("id").eq("usuario", usuario).maybeSingle();
      if (ex) return resp({ error: "Ese usuario ya existe." }, 400);
      const { data: nuevo, error: eNuevo } = await admin.auth.admin.createUser({
        email: `${usuario}@${DOMINIO}`, password: String(b.clave), email_confirm: true, user_metadata: { nombre },
      });
      if (eNuevo) return resp({ error: eNuevo.message.includes("already") ? "Ese usuario ya existe." : eNuevo.message }, 400);
      const { error: eP } = await admin.from("perfiles").insert({ id: nuevo.user.id, usuario, nombre, sap, rol, activo: true });
      if (eP) { await admin.auth.admin.deleteUser(nuevo.user.id); return resp({ error: eP.message }, 400); }
    } else if (b.accion === "editar") {
      const { data: p } = await admin.from("perfiles").select("id").eq("usuario", usuario).maybeSingle();
      if (!p) return resp({ error: "No encontré ese usuario." }, 404);
      const activo = b.activo !== false;
      if (p.id === yo.id && (rol !== "admin" || !activo)) return resp({ error: "No puedes quitarte el rol de administrador ni desactivarte a ti mismo." }, 400);
      const cambios: Record<string, unknown> = { ban_duration: activo ? "none" : "876000h" };
      if (b.clave) {
        if (String(b.clave).length < 6) return resp({ error: "La clave debe tener al menos 6 caracteres." }, 400);
        cambios.password = String(b.clave);
      }
      const { error: eU } = await admin.auth.admin.updateUserById(p.id, cambios);
      if (eU) return resp({ error: eU.message }, 400);
      const upd: Record<string, unknown> = { rol, activo };
      if (nombre) upd.nombre = nombre;
      if (b.sap !== undefined) upd.sap = sap;
      await admin.from("perfiles").update(upd).eq("id", p.id);
    } else if (b.accion !== "listar") {
      return resp({ error: "Acción no válida." }, 400);
    }
    const { data: lista } = await admin.from("perfiles").select("usuario,nombre,sap,rol,activo,ultimo_ingreso").order("nombre");
    return resp({ usuarios: lista ?? [] });
  } catch (e) {
    return resp({ error: String((e as Error).message ?? e) }, 500);
  }
});
