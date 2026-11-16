import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';
import 'package:web/web.dart' as web;
import 'image_io_types.dart';

/// Web: APIs del navegador, sin plugins.
class ImageIO {
  ImageIO._();

  static web.File _file(Uint8List png, String name) =>
      web.File(<JSAny>[png.toJS].toJS, '$name.png', web.FilePropertyBag(type: 'image/png'));

  static bool _canShareFile(web.File f) {
    try {
      return web.window.navigator.canShare(web.ShareData(files: <web.File>[f].toJS));
    } catch (_) {
      return false;   // navegadores sin Web Share API (Firefox de escritorio)
    }
  }

  /// Safari (iOS 13.4+), Chrome y Edge permiten escribir PNG en el portapapeles.
  static bool get canCopy {
    try {
      return web.window.isSecureContext && (web.window.navigator as JSObject).has('clipboard') && web.window.has('ClipboardItem');
    } catch (_) {
      return false;
    }
  }

  /// Traduce los errores del navegador a algo que la interfaz entiende.
  static Never _rethrow(Object e) {
    final name = e is web.DOMException ? e.name : (e.toString().contains('NotAllowedError') ? 'NotAllowedError' : e.toString().contains('AbortError') ? 'AbortError' : '');
    if (name == 'AbortError') throw const ImageActionCancelled();
    if (name == 'NotAllowedError') throw const ImageActionNeedsTap();
    throw e;
  }

  static Future<void> share(Uint8List png, String name, {String? text}) async {
    final f = _file(png, name);
    if (!_canShareFile(f)) { _download(png, name); return; }
    try {
      await web.window.navigator.share(web.ShareData(files: <web.File>[f].toJS, text: text ?? '')).toDart;
    } catch (e) {
      _rethrow(e);
    }
  }

  /// En iPhone no hay acceso directo a Fotos desde la web: se abre la hoja del sistema, cuya primera opción es
  /// «Guardar imagen». En ordenadores sin hoja de compartir, se descarga el PNG.
  static Future<ImageSaveResult> save(Uint8List png, String name) async {
    final f = _file(png, name);
    if (!_canShareFile(f)) { _download(png, name); return ImageSaveResult.downloaded; }
    try {
      await web.window.navigator.share(web.ShareData(files: <web.File>[f].toJS)).toDart;
    } catch (e) {
      _rethrow(e);
    }
    return ImageSaveResult.shareSheet;
  }

  static Future<void> copy(Uint8List png) async {
    try {
      final blob = web.Blob(<JSAny>[png.toJS].toJS, web.BlobPropertyBag(type: 'image/png'));
      final items = JSObject()..setProperty('image/png'.toJS, blob);
      final item = web.ClipboardItem(items);
      await web.window.navigator.clipboard.write(<web.ClipboardItem>[item].toJS).toDart;
    } catch (e) {
      _rethrow(e);
    }
  }

  static void _download(Uint8List png, String name) {
    final url = web.URL.createObjectURL(web.Blob(<JSAny>[png.toJS].toJS, web.BlobPropertyBag(type: 'image/png')));
    final a = web.HTMLAnchorElement()..href = url..download = '$name.png';
    web.document.body!.append(a);
    a.click();
    a.remove();
    web.URL.revokeObjectURL(url);
  }
}
