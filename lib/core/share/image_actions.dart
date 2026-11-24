import 'dart:async';
import 'package:flutter/material.dart';
import 'dart:typed_data';
import '../theme/design_tokens.dart';
import '../theme/plobby_text.dart';
import '../widgets/plobby_components.dart';
import '../widgets/plobby_icon.dart';
import 'image_io.dart';

/// Resultado de una acción de imagen vista desde la interfaz.
enum ImageActionOutcome { done, cancelled }

/// Ejecuta guardar / compartir / copiar. En la web, si el navegador exige un toque reciente (Safari, cuando generar la
/// imagen tardó), muestra una hoja con la imagen ya lista y un botón: ese segundo toque sí está permitido.
/// [ImageActionCancelled] (la persona cerró la hoja de compartir) no es un error.
Future<ImageActionOutcome> runImageAction(BuildContext context, Uint8List png, Future<void> Function() action, {required String label}) async {
  try {
    await action();
    return ImageActionOutcome.done;
  } on ImageActionCancelled {
    return ImageActionOutcome.cancelled;
  } on ImageActionNeedsTap {
    if (!context.mounted) return ImageActionOutcome.cancelled;
    final done = Completer<ImageActionOutcome>();
    await showPlobbySheet<void>(context, (ctx) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const SheetHeader(title: 'Tu imagen está lista'),
          ConstrainedBox(constraints: const BoxConstraints(maxHeight: 280),
              child: ClipRRect(borderRadius: AppRadius.rMd, child: Image.memory(png, fit: BoxFit.contain, semanticLabel: 'Vista previa de la imagen'))),
          const SizedBox(height: 12),
          Text('Pulsa el botón para continuar.', textAlign: TextAlign.center, style: PlobbyText.sub),
          const SizedBox(height: 14),
          PlobbyButton(label: label, icon: PlobbyIcons.share, onPressed: () {
            // Sin `await` antes de la llamada: el navegador la acepta porque nace de este toque.
            action().then((_) {
              if (!done.isCompleted) done.complete(ImageActionOutcome.done);
            }, onError: (Object e) {
              if (!done.isCompleted) done.complete(ImageActionOutcome.cancelled);
            });
            Navigator.of(ctx).pop();
          }),
        ]));
    if (!done.isCompleted) done.complete(ImageActionOutcome.cancelled);
    return done.future;
  }
}

/// Texto de confirmación tras «Guardar»: solo se dice «guardada» cuando de verdad se guardó.
String? saveMessage(ImageSaveResult r) => switch (r) {
      ImageSaveResult.savedToGallery => 'Imagen guardada en tu galería',
      ImageSaveResult.downloaded => 'Imagen descargada',
      ImageSaveResult.shareSheet => null,   // la hoja del sistema ya es la confirmación
    };
