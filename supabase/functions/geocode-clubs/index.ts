// Plobby · Geocodificación de clubes con Photon (Komoot, datos de OpenStreetMap). Nunca desde el cliente.
// - Solo la puede lanzar un administrador (app_metadata.plobby_admin) o quien tenga un token de un solo uso cuyo hash
//   está en la base de datos (public.geocode_token_ok, ejecutable solo por service_role).
// - Procesa clubes con geocode_status = 'pending' (máx. `limit` por llamada, por defecto 60) a 1 consulta/segundo
//   (uso responsable del servicio público) con un User-Agent identificable.
// - Solo acepta resultados dentro de la Comunidad de Madrid. Nunca usa el centro del municipio como ubicación del club:
//   si no hay un resultado preciso, el club queda como 'failed' para revisarlo a mano.
// Datos © colaboradores de OpenStreetMap (ODbL): la app lo cita donde muestra ubicaciones.
import { createClient } from 'npm:@supabase/supabase-js@2.45.4';

const URL_ = Deno.env.get('SUPABASE_URL')!;
const SERVICE = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const UA = 'Plobby/1.0 (+https://plobby.vercel.app)';
const MADRID = { minLat: 39.88, maxLat: 41.17, minLng: -4.58, maxLng: -3.05 };
const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

type Club = { id: string; name: string; address: string | null; postal_code: string | null; municipality: string | null; area: string | null };

// Photon (Komoot): datos de OpenStreetMap, sin clave. (Nominatim devuelve 403 a las IPs de Supabase.)
const REJECT = ['city', 'town', 'village', 'district', 'locality', 'county', 'state', 'country', 'region', 'suburb', 'postcode'];
async function geocode(q: string): Promise<{ lat: number; lng: number; label: string } | null> {
  const u = new URL('https://photon.komoot.io/api/');
  u.searchParams.set('q', q); u.searchParams.set('limit', '1');
  u.searchParams.set('bbox', `${MADRID.minLng},${MADRID.minLat},${MADRID.maxLng},${MADRID.maxLat}`);
  const r = await fetch(u, { headers: { 'User-Agent': UA } });
  if (!r.ok) throw new Error(`photon ${r.status}: ${(await r.text()).slice(0, 160)}`);
  const j = await r.json();
  const f = j?.features?.[0];
  if (!f) return null;
  const [lng, lat] = f.geometry?.coordinates ?? [];
  if (!(lat >= MADRID.minLat && lat <= MADRID.maxLat && lng >= MADRID.minLng && lng <= MADRID.maxLng)) return null;
  const p = f.properties ?? {};
  // un municipio, barrio o código postal no es la ubicación del club: se descarta
  if (REJECT.includes(String(p.type)) || ['place', 'boundary'].includes(String(p.osm_key))) return null;
  return { lat, lng, label: [p.name, p.street, p.housenumber, p.city].filter(Boolean).join(', ') };
}

Deno.serve(async (req) => {
  if (req.method !== 'POST') return new Response('method_not_allowed', { status: 405 });
  const db = createClient(URL_, SERVICE, { auth: { persistSession: false } });
  // autorización: secreto o administrador
  const token = req.headers.get('x-geocode-token') ?? '';
  let allowed = false;
  if (token.length >= 32) {
    const { data } = await db.rpc('geocode_token_ok', { p: token });
    allowed = data === true;
  }
  if (!allowed) {
    const jwt = (req.headers.get('authorization') ?? '').replace(/^Bearer\s+/i, '');
    if (jwt) {
      const { data } = await db.auth.getUser(jwt);
      allowed = data.user?.app_metadata?.plobby_admin === true;
    }
  }
  if (!allowed) return new Response('forbidden', { status: 403 });

  const body = await req.json().catch(() => ({}));
  // modo prueba: una sola consulta, sin escribir nada
  if (typeof body.probe === 'string') {
    try { return Response.json({ probe: body.probe, result: await geocode(body.probe) }); }
    catch (e) { return Response.json({ probe: body.probe, error: String(e) }, { status: 502 }); }
  }
  const limit = Math.min(Math.max(Number(body.limit ?? 60), 1), 100);
  const { data: clubs, error } = await db.from('clubs').select('id, name, address, postal_code, municipality, area')
    .eq('geocode_status', 'pending').in('status', ['verified']).order('name').limit(limit);
  if (error) return new Response(JSON.stringify({ error: error.message }), { status: 500 });

  const out = { ok: [] as string[], failed: [] as string[] };
  for (const c of (clubs ?? []) as Club[]) {
    const muni = c.municipality ?? '';
    const tries = [
      c.address ? `${c.address}, ${c.postal_code ?? ''} ${muni}, Madrid` : null,   // dirección exacta
      `${c.name}, ${muni}`,                                                       // nombre del club (pádel/club deportivo en OSM)
    ].filter(Boolean) as string[];
    let hit: { lat: number; lng: number } | null = null;
    for (const q of tries) {
      await sleep(1100);
      try { hit = await geocode(q); } catch (e) {
        // error del servicio (bloqueo, límite…): se para SIN marcar el club como fallido
        return Response.json({ error: String(e), stopped_at: c.name, ok: out.ok.length, failed: out.failed }, { status: 502 });
      }
      if (hit) break;
    }
    if (hit) {
      await db.from('clubs').update({ lat: hit.lat, lng: hit.lng, geocode_status: 'ok', updated_at: new Date().toISOString() }).eq('id', c.id);
      out.ok.push(c.name);
    } else {
      await db.from('clubs').update({ geocode_status: 'failed', updated_at: new Date().toISOString() }).eq('id', c.id);
      out.failed.push(c.name);
    }
  }
  const { count } = await db.from('clubs').select('id', { count: 'exact', head: true }).eq('geocode_status', 'pending').eq('status', 'verified');
  return new Response(JSON.stringify({ processed: (clubs ?? []).length, ok: out.ok.length, failed: out.failed, remaining: count ?? 0 }),
    { headers: { 'content-type': 'application/json' } });
});
