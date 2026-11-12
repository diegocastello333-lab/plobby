/// Identificador de la compilación, inyectado al construir el APK (`--dart-define=PLOBBY_BUILD=2026.11.12-f3`).
/// Se muestra al final del perfil: permite saber qué versión tiene instalada cada móvil. (El fallo de la pareja
/// habitual de la fase 3 venía de un móvil con un APK antiguo que aún enviaba un id de prueba.)
const plobbyBuild = String.fromEnvironment('PLOBBY_BUILD', defaultValue: 'desarrollo');
