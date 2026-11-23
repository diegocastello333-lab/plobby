#!/usr/bin/env python3
"""Genera supabase/migrations/20261202b_clubs_seed.sql desde supabase/seed/clubes_madrid_2026_11.csv.
Carga idempotente: upsert por slug y alias con ON CONFLICT DO NOTHING. Celdas vacías → NULL (no se inventa nada)."""
import csv, re, sys, unicodedata
SRC = 'supabase/seed/clubes_madrid_2026_11.csv'
OUT = 'supabase/migrations/20261202b_clubs_seed.sql'
ZONE = {'Madrid capital': 'madrid_capital', 'Norte': 'norte', 'Oeste': 'oeste', 'Sur': 'sur', 'Este': 'este'}
TYPE = {'Club / centro privado': 'private_club', 'Club social privado': 'social_club', 'Club social': 'social_club',
        'Municipal': 'municipal', 'Público (Comunidad de Madrid)': 'public_regional', 'Federación (FMP)': 'federation',
        'Gimnasio / club deportivo': 'gym', 'Universidad': 'university', 'Colegio': 'school'}
def slug(s):
    s = unicodedata.normalize('NFKD', s.lower()); s = ''.join(c for c in s if not unicodedata.combining(c))
    return re.sub(r'[^a-z0-9]+', '-', s).strip('-')
def q(v):
    v = (v or '').strip()
    return 'null' if not v else "'" + v.replace("'", "''") + "'"
rows = [r for r in csv.DictReader(open(SRC, encoding='utf-8-sig')) if r['Nombre'].strip()]
seen = set(); clubs = []; aliases = []
for r in rows:
    s = slug(r['Nombre'])
    if s in seen: sys.exit(f'slug repetido: {s}')
    seen.add(s)
    cp = r['CP'].strip()
    if cp and not re.fullmatch(r'\d{5}', cp): sys.exit(f'CP raro: {cp}')
    if r['Tipo'] not in TYPE or r['Zona'] not in ZONE: sys.exit(f"tipo/zona desconocido: {r['Tipo']} / {r['Zona']}")
    clubs.append(f"  ({q(s)}, {q(r['Nombre'])}, {q(r['Municipio'])}, '{ZONE[r['Zona']]}', {q(r['Barrio / área'])}, {q(r['Dirección'])}, {q(cp)}, '{TYPE[r['Tipo']]}')")
    for a in r['Otros nombres (alias)'].split(';'):
        if a.strip(): aliases.append(f"  ({q(s)}, {q(a)})")
sql = f"""-- =====================================================================================================================
-- Plobby · Carga inicial de clubes de la Comunidad de Madrid ({len(clubs)} clubes, {len(aliases)} alias). GENERADO por
-- supabase/seed/build_clubs_seed.py desde supabase/seed/clubes_madrid_2026_11.csv: no editar a mano.
-- Idempotente: se puede repetir (upsert por slug; los alias no se duplican). status = verified, source = seed_2026_11.
-- Requiere 20261202a_clubs_catalog.
-- =====================================================================================================================
insert into public.clubs (slug, name, municipality, zone, area, address, postal_code, type, city, status, source)
select v.slug, v.name, v.municipality, v.zone, v.area, v.address, v.postal_code, v.type, v.municipality, 'verified', 'seed_2026_11'
from (values
{',\n'.join(clubs)}
) as v(slug, name, municipality, zone, area, address, postal_code, type)
on conflict (slug) do update set name = excluded.name, municipality = excluded.municipality, zone = excluded.zone, area = excluded.area,
  address = excluded.address, postal_code = excluded.postal_code, type = excluded.type, city = excluded.city, updated_at = now()
  where public.clubs.source = 'seed_2026_11';   -- nunca pisa un club creado o fusionado por otra vía

insert into public.club_aliases (club_id, alias, source)
select c.id, v.alias, 'seed_2026_11'
from (values
{',\n'.join(aliases)}
) as v(slug, alias) join public.clubs c on c.slug = v.slug
on conflict (club_id, alias_normalized) do nothing;
"""
open(OUT, 'w', encoding='utf-8').write(sql)
print(f'{OUT}: {len(clubs)} clubes, {len(aliases)} alias')
