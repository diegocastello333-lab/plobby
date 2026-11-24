/// Nombre corto para listas y parejas: «Ana Rodríguez Pérez» → «Ana R.». Un solo nombre se deja tal cual. Así las
/// parejas («Ana R. · Bea S.») caben en una línea en vez de cortarse a mitad de palabra.
String shortName(String full) {
  final parts = full.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.length < 2) return parts.isEmpty ? '' : parts.first;
  return '${parts.first} ${String.fromCharCode(parts[1].runes.first).toUpperCase()}.';
}
