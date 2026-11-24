#!/usr/bin/env bash
# Compila Plobby Web para producción. Lo usa Vercel en cada despliegue (vercel.json) y sirve igual en local.
#
# Variables de entorno necesarias (en Vercel: Project → Settings → Environment Variables):
#   SUPABASE_URL               https://<ref>.supabase.co
#   SUPABASE_PUBLISHABLE_KEY   clave PÚBLICA (sb_publishable_… o la anon). NUNCA la service_role / sb_secret_.
# Opcional: FLUTTER_VERSION (por defecto la misma que la app nativa y Codemagic).
set -euo pipefail

FLUTTER_VERSION="${FLUTTER_VERSION:-3.50.0}"
cd "$(dirname "$0")/.."

: "${SUPABASE_URL:?Falta SUPABASE_URL}"
: "${SUPABASE_PUBLISHABLE_KEY:?Falta SUPABASE_PUBLISHABLE_KEY}"

# Seguridad: la web es pública por naturaleza; jamás debe llevar una clave que salte las políticas RLS.
case "$SUPABASE_PUBLISHABLE_KEY" in
  sb_secret_*) echo "ERROR: SUPABASE_PUBLISHABLE_KEY es una clave secreta (sb_secret_). Usa la publishable." >&2; exit 1 ;;
esac
if [[ "$SUPABASE_PUBLISHABLE_KEY" == eyJ* ]]; then
  payload=$(echo "$SUPABASE_PUBLISHABLE_KEY" | cut -d. -f2 | tr '_-' '/+')
  while (( ${#payload} % 4 )); do payload="$payload="; done
  if echo "$payload" | base64 -d 2>/dev/null | grep -q '"role":"service_role"'; then
    echo "ERROR: SUPABASE_PUBLISHABLE_KEY es la service_role. Usa la anon/publishable." >&2; exit 1
  fi
fi

# Flutter: el del sistema si existe; si no (Vercel), se descarga una vez y se reutiliza desde la caché de compilación.
# Flutter descomprime sus herramientas con `unzip`; la imagen de compilación de Vercel (Amazon Linux) puede no traerlo.
if ! command -v unzip >/dev/null 2>&1; then
  (dnf install -y unzip || yum install -y unzip) >/dev/null 2>&1 || echo "Aviso: no se pudo instalar unzip" >&2
fi
if ! command -v flutter >/dev/null 2>&1; then
  FLUTTER_HOME="${FLUTTER_HOME:-$PWD/.flutter-sdk}"
  if [[ ! -x "$FLUTTER_HOME/bin/flutter" ]]; then
    git clone --depth 1 --branch "$FLUTTER_VERSION" https://github.com/flutter/flutter.git "$FLUTTER_HOME"
  fi
  export PATH="$FLUTTER_HOME/bin:$PATH"
fi
flutter config --no-analytics >/dev/null 2>&1 || true
flutter --version

BUILD_ID="${VERCEL_GIT_COMMIT_SHA:-$(git rev-parse HEAD 2>/dev/null || date +%s)}"
BUILD_ID="${BUILD_ID:0:12}"

flutter pub get
# --no-web-resources-cdn: CanvasKit se sirve desde nuestro dominio (no de gstatic.com): menos dependencias externas y
# la PWA puede guardarlo en caché. --pwa-strategy no se usa: el service worker es el nuestro (web/sw.js).
# --wasm: Chrome, Edge, Firefox y Safari 18.2+ usan WebAssembly (skwasm): en 4G lento el contenido útil llega en
# ~11 s frente a ~20 s con JavaScript+CanvasKit (medido, docs/rendimiento). Los navegadores sin WasmGC siguen usando la
# versión JavaScript, que también se genera. --enable-wasm-deferred-loading: las pantallas secundarias se descargan al
# abrirlas (o en segundo plano tras la carga), no al principio.
ENGINE_ID=$(flutter --version --machine 2>/dev/null | sed -n 's/.*"engineRevision": *"\([0-9a-f]*\)".*/\1/p' | cut -c1-12)
flutter build web --release --wasm --enable-wasm-deferred-loading --no-web-resources-cdn \
  --dart-define=SUPABASE_URL="$SUPABASE_URL" \
  --dart-define=SUPABASE_PUBLISHABLE_KEY="$SUPABASE_PUBLISHABLE_KEY" \
  --dart-define=PLOBBY_BUILD="web.$BUILD_ID"

# Versión del service worker = commit: cada despliegue invalida la caché de la app (nunca la de datos: no hay).
sed -i.bak "s/__PLOBBY_BUILD_ID__/$BUILD_ID/; s/__PLOBBY_ENGINE_ID__/${ENGINE_ID:-$BUILD_ID}/" build/web/sw.js && rm -f build/web/sw.js.bak
# El service worker de Flutter 3.50 es un stub que se da de baja; no se registra (web/flutter_bootstrap.js).
rm -f build/web/flutter_service_worker.js

echo "Plobby Web listo en build/web (versión $BUILD_ID)"
