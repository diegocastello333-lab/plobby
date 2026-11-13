#!/usr/bin/env bash
# Valida TODAS las migraciones y las pruebas de gamificación en un PostgreSQL local (no toca producción).
# Uso: supabase/tests/run_local.sh <host-o-socket> <puerto>   (requiere psql y un servidor PostgreSQL 15+ vacío)
set -euo pipefail
export PGOPTIONS="-c client_min_messages=warning"
H=${1:-localhost}; PORT=${2:-5432}; P="psql -h $H -p $PORT -U postgres -v ON_ERROR_STOP=1 -q"
DIR=$(cd "$(dirname "$0")/.." && pwd)
$P -c "drop database if exists plobby_test" -c "create database plobby_test"
$P -d plobby_test -f "$DIR/tests/local_supabase_stub.sql"
for f in "$DIR"/migrations/*.sql; do echo "· $(basename "$f")"; $P -d plobby_test -f "$f" > /dev/null; done
psql -h "$H" -p "$PORT" -U postgres -d plobby_test -q -f "$DIR/tests/gamification_test.sql" | grep -E "FALLO|resumen|/[0-9]+$"
