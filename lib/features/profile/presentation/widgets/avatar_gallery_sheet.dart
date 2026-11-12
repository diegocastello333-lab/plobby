import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../../../../core/theme/design_tokens.dart';
import '../../../../core/theme/plobby_text.dart';
import '../../../../core/widgets/plobby_components.dart';
import '../../../../core/widgets/plobby_icon.dart';
import '../../../auth/domain/auth_models.dart' show avatarIds;
import '../../../auth/presentation/avatar_catalog.dart';

/// Resultado de [AvatarGallerySheet] además del id de un avatar (`a1`…`a12`).
const kPhotoFromGallery = '_gallery', kPhotoRemove = '_remove';

/// Hoja «Foto de perfil» de Editar perfil: subir foto, galería de los 12 avatares de Plobby (siempre disponible, aunque
/// ya haya una foto) y «Eliminar foto». Devuelve [kPhotoFromGallery], [kPhotoRemove] o el id del avatar elegido.
class AvatarGallerySheet extends StatelessWidget {
  const AvatarGallerySheet({super.key, this.selectedId, this.canRemove = false});
  /// Avatar vigente (se marca con el aro de tinta); null si la imagen actual es una foto o no hay ninguna.
  final String? selectedId;
  final bool canRemove;
  @override
  Widget build(BuildContext context) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const SheetHeader(title: 'Foto de perfil', subtitle: 'Sube una foto o elige un avatar de Plobby.'),
        SheetListItem(icon: PlobbyIcons.image, label: 'Subir foto de la galería', onTap: () => Navigator.of(context).pop(kPhotoFromGallery)),
        Container(
          padding: const EdgeInsets.only(top: 14, bottom: 10),
          decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0x1A171C19)))),
          child: const Text('AVATARES', style: PlobbyText.eb),
        ),
        GridView.count(crossAxisCount: 4, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), mainAxisSpacing: 12, crossAxisSpacing: 12, children: [
          for (final id in avatarIds)
            Semantics(button: true, selected: selectedId == id, label: 'Avatar ${avatarName(id)}', excludeSemantics: true,
                child: InkWell(customBorder: const CircleBorder(), onTap: () => Navigator.of(context).pop(id),
                    child: AnimatedContainer(duration: const Duration(milliseconds: 150), padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: selectedId == id ? AppColors.text : Colors.transparent, width: 2.5)),
                        child: Stack(fit: StackFit.expand, children: [
                          LayoutBuilder(builder: (_, c) => PlobbyAvatar(id: id, size: c.maxWidth)),
                          if (selectedId == id) Align(alignment: Alignment.bottomRight, child: Container(width: 20, height: 20,
                              decoration: BoxDecoration(color: AppColors.brand, shape: BoxShape.circle, border: Border.all(color: AppColors.bg, width: 2)),
                              child: const Center(child: PlobbyIcon(PlobbyIcons.check, size: 11, color: AppColors.text)))),
                        ])))),
        ]),
        const SizedBox(height: 14),
        if (canRemove) SheetListItem(icon: PlobbyIcons.trash, label: 'Eliminar foto', danger: true, onTap: () => Navigator.of(context).pop(kPhotoRemove)),
      ]);
}

/// Dibuja el avatar predefinido [id] como PNG cuadrado de [size] px (mismo pintor que [PlobbyAvatar]).
Future<List<int>> renderAvatarPng(String id, {int size = 512}) async {
  final rec = ui.PictureRecorder();
  if (!paintPlobbyAvatar(Canvas(rec), size.toDouble(), id)) throw ArgumentError.value(id, 'id', 'avatar desconocido');
  final img = await rec.endRecording().toImage(size, size);
  try {
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  } finally {
    img.dispose();
  }
}
