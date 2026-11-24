/// Accesibilidad en la web bajo demanda. Mantener el árbol de accesibilidad de Flutter siempre activo costaba ~40 % del
/// trabajo de cada fotograma al desplazar (se actualizan cientos de nodos del DOM por fotograma). Ahora se activa solo
/// si alguien lo necesita: un botón «Activar lector de pantalla», el primero que encuentran VoiceOver/TalkBack/NVDA y
/// el teclado (invisible salvo con foco). La elección se recuerda en el dispositivo.
library;

export 'web_a11y_native.dart' if (dart.library.js_interop) 'web_a11y_web.dart';
