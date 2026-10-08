// ============================================================
// Funcion: admin-users
// Proposito: permitirle al DUENO crear, restablecer y eliminar
//            cuentas de usuario (admin/master) sin exponer la clave
//            service_role en el navegador.
//
// Despliegue:
//   supabase functions deploy admin-users --no-verify-jwt
//   (o desde el Dashboard: Edge Functions > deploy)
//
// La clave SERVICE_ROLE solo vive aqui, en el servidor.
// El cliente solo manda su propio JWT de Supabase Auth;
// la funcion verifica que ese JWT pertenezca a un admin.
// ============================================================

import {
  createClient,
  type SupabaseClient,
} from "https://esm.sh/@supabase/supabase-js@2.117.2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, "Content-Type": "application/json" },
  });
}

// El service role NUNCA debe salir de este archivo.
const svc: SupabaseClient = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
  auth: { persistSession: false, autoRefreshToken: false },
});

// ------------------------------------------------------------
// Devuelve el id del usuario si (y solo si) es admin.
// Usa el cliente anon + el JWT que manda el navegador, asi la
// verificacion corre contra las politicas RLS de la base.
// ------------------------------------------------------------
async function reqAdmin(req: Request): Promise<string | null> {
  const raw = req.headers.get("Authorization") ?? "";
  const token = raw.replace(/^Bearer\s+/i, "").trim();
  if (!token) return null;

  try {
    const caller = createClient(SUPABASE_URL, ANON_KEY, {
      global: { headers: { Authorization: `Bearer ${token}` } },
      auth: { persistSession: false, autoRefreshToken: false },
    });

    const { data, error } = await caller.auth.getUser(token);
    if (error || !data?.user) return null;

    const { data: perfil } = await caller
      .from("profiles")
      .select("rol")
      .eq("id", data.user.id)
      .maybeSingle();

    return perfil?.rol === "admin" ? data.user.id : null;
  } catch {
    return null;
  }
}

const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/;

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: CORS });
  }
  if (req.method !== "POST") {
    return json({ error: "Metodo no permitido" }, 405);
  }

  const adminId = await reqAdmin(req);
  if (!adminId) {
    return json({ error: "Se requiere cuenta de administrador" }, 403);
  }

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return json({ error: "Cuerpo invalido" }, 400);
  }

  const op = String(body.op ?? "");

  // ----------------------------------------------------------
  // create - crear cuenta de usuario (rol: admin | master)
  // ----------------------------------------------------------
  if (op === "create") {
    const email = String(body.email ?? "").trim().toLowerCase();
    const password = String(body.password ?? "");
    const rol = ["admin", "master"].includes(String(body.rol))
      ? String(body.rol)
      : "master";

    if (!EMAIL_RE.test(email)) {
      return json({ error: "Correo invalido" }, 400);
    }
    if (password.length < 6) {
      return json({ error: "La contraseña debe tener al menos 6 caracteres" }, 400);
    }

    const { data, error } = await svc.auth.admin.createUser({
      email,
      password,
      email_confirm: true,
    });
    if (error) return json({ error: error.message }, 400);

    const uid = data.user?.id;
    if (uid) {
      const { error: e2 } = await svc
        .from("profiles")
        .update({ rol })
        .eq("id", uid);
      if (e2) return json({ error: e2.message }, 400);
    }

    return json({ ok: true, id: uid, email, rol });
  }

  // ----------------------------------------------------------
  // reset - enviar enlace para que el usuario ponga su clave
  // ----------------------------------------------------------
  if (op === "reset") {
    const email = String(body.email ?? "").trim().toLowerCase();
    if (!EMAIL_RE.test(email)) {
      return json({ error: "Correo invalido" }, 400);
    }

    const { error } = await svc.auth.admin.generateLink({
      type: "recovery",
      email,
    });
    if (error) return json({ error: error.message }, 400);

    return json({ ok: true });
  }

  // ----------------------------------------------------------
  // delete - eliminar cuenta y su perfil (cascade)
  // ----------------------------------------------------------
  if (op === "delete") {
    const id = String(body.id ?? "");
    if (!/^[0-9a-f-]{36}$/i.test(id)) {
      return json({ error: "Identificador invalido" }, 400);
    }
    if (id === adminId) {
      return json({ error: "No puedes eliminar tu propia cuenta" }, 400);
    }

    const { error } = await svc.auth.admin.deleteUser(id);
    if (error) return json({ error: error.message }, 400);

    return json({ ok: true });
  }

  return json({ error: "Operacion desconocida" }, 400);
});
