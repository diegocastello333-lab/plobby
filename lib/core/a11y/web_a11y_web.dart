import 'dart:js_interop';
import 'package:flutter/semantics.dart';
import 'package:web/web.dart' as web;

const _key = 'plobby.a11y';
SemanticsHandle? _handle;

void _enable() {
  _handle ??= SemanticsBinding.instance.ensureSemantics();
  try { web.window.localStorage.setItem(_key, '1'); } catch (_) {}
}

/// Si el usuario ya lo activó en este dispositivo, se enciende al arrancar; si no, se añade el botón de activación.
void installWebA11yToggle() {
  var on = false;
  try { on = web.window.localStorage.getItem(_key) == '1'; } catch (_) {}
  if (on) { _enable(); return; }
  final b = web.document.createElement('button') as web.HTMLButtonElement;
  b.textContent = 'Activar lector de pantalla';
  b.id = 'plobby-a11y-on';
  final s = b.style;
  // Visualmente oculto (patrón «sr-only»), pero accesible y enfocable; con el foco del teclado se muestra.
  void hide() { s.position = 'fixed'; s.left = '0'; s.top = '0'; s.width = '1px'; s.height = '1px'; s.overflow = 'hidden';
    s.setProperty('clip-path', 'inset(50%)'); s.whiteSpace = 'nowrap'; s.zIndex = '10000'; s.border = '0'; s.padding = '0'; }
  void show() { s.width = 'auto'; s.height = 'auto'; s.setProperty('clip-path', 'none'); s.padding = '12px 16px';
    s.left = '8px'; s.top = '8px'; s.background = '#171C19'; s.color = '#D2F548'; s.font = '600 15px Inter, sans-serif'; s.borderRadius = '12px'; }
  hide();
  b.addEventListener('focus', ((web.Event _) => show()).toJS);
  b.addEventListener('blur', ((web.Event _) => hide()).toJS);
  b.addEventListener('click', ((web.Event _) { _enable(); b.remove(); }).toJS);
  final body = web.document.body;
  if (body != null) body.insertBefore(b, body.firstChild);
}
