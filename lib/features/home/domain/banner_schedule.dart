/// Banners dinámicos de Inicio: dos colecciones (Seaside y Tropical) de cuatro imágenes cada una. El usuario elige la
/// colección; la imagen la decide la hora LOCAL del dispositivo (su zona horaria, con horario de verano incluido).
///
/// | Hora local     | Momento   |
/// |----------------|-----------|
/// | 06:00 – 08:59  | Amanecer  |
/// | 09:00 – 17:59  | Día       |
/// | 18:00 – 19:59  | Atardecer |
/// | 20:00 – 05:59  | Noche     |
library;

/// Momento del día que representa cada imagen de una colección.
enum DayPhase {
  amanecer('Amanecer', 6),
  dia('Día', 9),
  atardecer('Atardecer', 18),
  noche('Noche', 20);

  const DayPhase(this.label, this.startHour);
  final String label;
  /// Hora local (en punto) en la que empieza este momento.
  final int startHour;

  /// «06:00 – 08:59», para la ayuda del selector.
  String get range {
    final end = DayPhase.values[(index + 1) % DayPhase.values.length].startHour;
    String hh(int h) => h.toString().padLeft(2, '0');
    return '${hh(startHour)}:00 – ${hh((end + 23) % 24)}:59';
  }
}

/// Colección elegida por el usuario. [id] es el valor que se guarda en `profiles.banner_id`.
/// Los ids ('banner1'/'banner2') son los que ya están guardados en `profiles.banner_id` y las carpetas de los assets:
/// no se renombran, solo cambia el nombre visible.
enum HomeBanner {
  banner1('banner1', 'Seaside'),
  banner2('banner2', 'Tropical');

  const HomeBanner(this.id, this.name);
  final String id, name;

  /// Ruta del asset de un momento del día: `assets/images/banners/<id>/<momento>.jpg`.
  String asset(DayPhase p) => 'assets/images/banners/$id/${p.name}.jpg';

  /// Las cuatro imágenes de la colección (para precargarlas).
  List<String> get assets => [for (final p in DayPhase.values) asset(p)];

  /// Preferencia guardada → colección. Sin preferencia, o con un valor antiguo (los banners que ya no existen),
  /// se usa Seaside.
  static HomeBanner fromId(String? id) => values.where((b) => b.id == id).firstOrNull ?? banner1;
}

/// Momento del día para una hora local. Solo cuentan hora y minuto del [local] recibido: quien llama pasa
/// `DateTime.now()` (hora del dispositivo, ya en su zona horaria), nunca una hora de servidor ni UTC.
DayPhase dayPhaseAt(DateTime local) {
  final h = local.hour;
  if (h >= 20 || h < 6) return DayPhase.noche;
  if (h >= 18) return DayPhase.atardecer;
  if (h >= 9) return DayPhase.dia;
  return DayPhase.amanecer;
}

/// Próximo cambio de momento a partir de [local] (06:00, 09:00, 18:00 o 20:00). Se construye con el constructor LOCAL
/// de `DateTime`, así que en los días de cambio de hora la espera real ya incluye la hora que se gana o se pierde.
DateTime nextPhaseChange(DateTime local) {
  for (var day = 0; day < 2; day++) {
    for (final p in DayPhase.values) {
      final t = DateTime(local.year, local.month, local.day + day, p.startHour);
      if (t.isAfter(local)) return t;
    }
  }
  return DateTime(local.year, local.month, local.day + 1, DayPhase.amanecer.startHour);   // inalcanzable
}
