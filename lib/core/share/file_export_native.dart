import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class FileExport {
  FileExport._();
  static Future<void> saveText(String text, String fileName, {String mime = 'application/json'}) async {
    final dir = await getTemporaryDirectory();
    final f = File('${dir.path}/$fileName')..writeAsBytesSync(utf8.encode(text));
    try {
      await Share.shareXFiles([XFile(f.path, mimeType: mime, name: fileName)]);
    } finally {
      // el archivo temporal contiene datos personales: no se deja en el móvil más de lo necesario
      Future.delayed(const Duration(minutes: 5), () { try { f.deleteSync(); } catch (_) {} });
    }
  }
}
