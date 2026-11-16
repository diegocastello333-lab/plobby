/// Ejecuta una acción como mucho UNA vez a la vez por clave. Un segundo toque mientras la primera sigue en curso se
/// ignora (no se envía otra petición al servidor).
///
/// Por qué: en las acciones de partido (empezar, finalizar, aceptar o rechazar resultado) un doble toque enviaba la
/// petición dos veces; la primera funcionaba y la segunda fallaba porque el partido ya había cambiado de estado, y la
/// persona veía un mensaje de error aunque todo hubiera ido bien.
class SingleFlight {
  SingleFlight._();
  static final Set<Object> _running = <Object>{};

  /// true si ya hay una acción en curso con esa clave.
  static bool isRunning(Object key) => _running.contains(key);

  /// Ejecuta [action] si no hay otra en curso con [key]; si la hay, no hace nada.
  static Future<void> run(Object key, Future<void> Function() action) async {
    if (!_running.add(key)) return;
    try {
      await action();
    } finally {
      _running.remove(key);
    }
  }
}
