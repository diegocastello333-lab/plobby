/// Configuración de entorno. Se inyecta en compilación (nunca se guarda en el repo):
///   flutter run --dart-define=SUPABASE_URL=https://<ref>.supabase.co --dart-define=SUPABASE_PUBLISHABLE_KEY=sb_publishable_...
/// o  flutter run --dart-define-from-file=env.json   (env.json está en .gitignore; plantilla: env.example.json)
/// Solo clave PUBLISHABLE (anon). La service_role / secret key NUNCA va en la app.
class Env {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabasePublishableKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');

  /// true cuando hay credenciales: la app usa Supabase; si no, sigue con los repositorios mock (demo/tests).
  static bool get hasSupabase => supabaseUrl.isNotEmpty && supabasePublishableKey.isNotEmpty;
}
