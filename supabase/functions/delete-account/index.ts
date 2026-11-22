// Plobby · Edge Function `delete-account` (Seguridad Fase 4, 22 nov 2026).
//
// Borra la cuenta del usuario que llama:
//   1. Verifica su JWT (además de la verificación de la pasarela: verify_jwt = true).
//   2. Borra sus ficheros de Storage (`avatars/<uid>/…`: fotos de perfil y portadas de torneo).
//   3. Borra el usuario de Auth. El trigger `plobby_anonymize_before_delete` (migración 20261130a) anonimiza en la
//      misma transacción: borra lo personal y deja «Jugador eliminado» en los partidos/torneos de los demás.
//
// La clave service_role SOLO existe aquí, como variable de entorno que Supabase inyecta (SUPABASE_SERVICE_ROLE_KEY);
// nunca está en la app ni en el repositorio. CORS: solo los orígenes de ALLOWED_ORIGINS (las apps móviles no envían
// cabecera Origin y no les afecta).
import { createClient } from 'npm:@supabase/supabase-js@2.45.4';

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SERVICE_ROLE = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const ALLOWED = (Deno.env.get('ALLOWED_ORIGINS') ?? 'https://plobby.vercel.app').split(',').map((s) => s.trim()).filter(Boolean);

function cors(origin: string | null): Record<string, string> {
  const h: Record<string, string> = {
    'Vary': 'Origin',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
    'Access-Control-Max-Age': '600',
  };
  if (origin && ALLOWED.includes(origin)) h['Access-Control-Allow-Origin'] = origin;
  return h;
}

function json(status: number, body: unknown, origin: string | null) {
  return new Response(JSON.stringify(body), { status, headers: { ...cors(origin), 'Content-Type': 'application/json', 'Cache-Control': 'no-store' } });
}

Deno.serve(async (req) => {
  const origin = req.headers.get('Origin');
  if (origin && !ALLOWED.includes(origin)) return json(403, { error: 'origin_not_allowed' }, origin);
  if (req.method === 'OPTIONS') return new Response(null, { status: 204, headers: cors(origin) });
  if (req.method !== 'POST') return json(405, { error: 'method_not_allowed' }, origin);

  const auth = req.headers.get('Authorization') ?? '';
  const jwt = auth.startsWith('Bearer ') ? auth.slice(7) : '';
  if (!jwt) return json(401, { error: 'not_authenticated' }, origin);

  let body: { confirm?: string } = {};
  try { body = await req.json(); } catch { /* cuerpo vacío o inválido */ }
  if (body.confirm !== 'ELIMINAR') return json(400, { error: 'confirmation_required' }, origin);

  const admin = createClient(SUPABASE_URL, SERVICE_ROLE, { auth: { persistSession: false, autoRefreshToken: false } });
  const { data: userData, error: userErr } = await admin.auth.getUser(jwt);
  const uid = userData?.user?.id;
  if (userErr || !uid) return json(401, { error: 'invalid_session' }, origin);

  // 1) Ficheros propios en Storage (la ruta es siempre <uid>/<fichero>: la política impide subcarpetas)
  try {
    const bucket = admin.storage.from('avatars');
    for (let page = 0; page < 20; page++) {
      const { data: files, error } = await bucket.list(uid, { limit: 100 });
      if (error) throw error;
      if (!files || files.length === 0) break;
      const { error: rmErr } = await bucket.remove(files.map((f) => `${uid}/${f.name}`));
      if (rmErr) throw rmErr;
      if (files.length < 100) break;
    }
  } catch (e) {
    console.error('storage_cleanup_failed', String(e));   // sin datos personales en el registro: solo el tipo de fallo
    return json(500, { error: 'storage_cleanup_failed' }, origin);
  }

  // 2) Usuario de Auth (dispara la anonimización en la base de datos, todo o nada)
  const { error: delErr } = await admin.auth.admin.deleteUser(uid);
  if (delErr) {
    console.error('auth_delete_failed', delErr.message);
    return json(500, { error: 'delete_failed' }, origin);
  }
  return json(200, { ok: true }, origin);
});
