import 'dart:convert';
import 'dart:js_interop';
import 'package:web/web.dart' as web;

class FileExport {
  FileExport._();
  static Future<void> saveText(String text, String fileName, {String mime = 'application/json'}) async {
    final bytes = utf8.encode(text);
    final url = web.URL.createObjectURL(web.Blob(<JSAny>[bytes.toJS].toJS, web.BlobPropertyBag(type: mime)));
    final a = web.HTMLAnchorElement()..href = url..download = fileName;
    web.document.body?.append(a);
    a.click();
    a.remove();
    Future.delayed(const Duration(seconds: 30), () => web.URL.revokeObjectURL(url));
  }
}
