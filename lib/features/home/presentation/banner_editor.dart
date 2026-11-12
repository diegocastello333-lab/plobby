import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import '../../../core/theme/design_tokens.dart';
import '../../../core/theme/plobby_text.dart';
import '../../../core/widgets/plobby_components.dart';
import '../../../core/widgets/plobby_icon.dart';
import '../../../core/widgets/state_views.dart';
import '../../profile/application/profile_providers.dart';
import '../../profile/domain/models.dart';
import 'banner_catalog.dart';

/// Hoja «Banner de Inicio»: subir una foto propia (con encuadre) o elegir uno de los banners de Plobby.
Future<void> showBannerSheet(BuildContext context) => showPlobbySheet<void>(context, (_) => const _BannerSheet());

class _BannerSheet extends ConsumerStatefulWidget {
  const _BannerSheet();
  @override
  ConsumerState<_BannerSheet> createState() => _BannerSheetState();
}

class _BannerSheetState extends ConsumerState<_BannerSheet> {
  String? _busy;   // id del banner que se está guardando ('_photo' = foto)

  PlayerProfile? get _me => ref.watch(profileProvider('me')).valueOrNull?.profile;

  String get _current {
    final p = _me;
    if (p?.bannerUrl != null) return '_photo';
    return p?.bannerId ?? 'clasico';
  }

  Future<void> _choose(BannerPreset b) async {
    if (_busy != null || b.id == _current) return;
    setState(() => _busy = b.id);
    final repo = ref.read(profileRepositoryProvider);
    try {
      await repo.setBanner(presetId: b.id == 'clasico' ? null : b.id);
      await repo.deleteOldBanners();   // la foto propia anterior ya no se usa
      ref.invalidate(profileProvider('me'));
      HapticFeedback.selectionClick();
      if (mounted) { Navigator.of(context).pop(); showPlobbySnack(context, 'Banner «${b.name}» aplicado'); }
    } catch (_) {
      if (mounted) { setState(() => _busy = null); showPlobbySnack(context, 'No se pudo cambiar el banner. Revisa tu conexión.', error: true); }
    }
  }

  Future<void> _photo() async {
    if (_busy != null) return;
    final x = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 2400, imageQuality: 92);
    if (x == null || !mounted) return;
    setState(() => _busy = '_photo');
    final nav = Navigator.of(context, rootNavigator: true);
    try {
      final prepared = await compute(prepareBannerSource, await x.readAsBytes());
      if (!mounted) return;
      final rect = await nav.push<Rect>(MaterialPageRoute(fullscreenDialog: true, builder: (_) => BannerCropScreen(source: prepared)));
      if (rect == null || !mounted) { if (mounted) setState(() => _busy = null); return; }
      final jpeg = await compute(cropBannerJpeg, BannerCropJob(prepared.bytes, rect));
      final repo = ref.read(profileRepositoryProvider);
      final url = await repo.uploadBanner(jpeg);
      await repo.setBanner(url: url);
      await repo.deleteOldBanners(keepUrl: url);
      ref.invalidate(profileProvider('me'));
      if (mounted) { Navigator.of(context).pop(); showPlobbySnack(context, 'Banner actualizado'); }
    } catch (_) {
      if (mounted) { setState(() => _busy = null); showPlobbySnack(context, 'No se pudo guardar la foto. Inténtalo de nuevo.', error: true); }
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = _current;
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SheetHeader(title: 'Banner de Inicio', subtitle: 'Sube tu foto o elige uno de Plobby. Lo verás en todos tus dispositivos.'),
      SheetListItem(icon: PlobbyIcons.image, label: _busy == '_photo' ? 'Preparando la foto…' : 'Subir una foto de la galería', onTap: _photo),
      Container(padding: const EdgeInsets.only(top: 14, bottom: 10), decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0x1A171C19)))),
          child: const Text('BANNERS DE PLOBBY', style: PlobbyText.eb)),
      GridView.count(crossAxisCount: 2, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), mainAxisSpacing: 12, crossAxisSpacing: 12, childAspectRatio: kBannerAspect * .86,
        children: [for (final b in bannerPresets) _PresetTile(preset: b, selected: current == b.id, busy: _busy == b.id, onTap: () => _choose(b))]),
      const SizedBox(height: 8),
    ]);
  }
}

class _PresetTile extends StatelessWidget {
  const _PresetTile({required this.preset, required this.selected, required this.busy, required this.onTap});
  final BannerPreset preset; final bool selected, busy; final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Semantics(button: true, selected: selected, label: 'Banner ${preset.name}', excludeSemantics: true, child: GestureDetector(
        onTap: onTap,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: AnimatedContainer(
            duration: const Duration(milliseconds: 180), padding: const EdgeInsets.all(2.5),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: selected ? AppColors.text : Colors.transparent, width: 2.5)),
            child: ClipRRect(borderRadius: BorderRadius.circular(11), child: Stack(fit: StackFit.expand, children: [
              BannerImage(presetId: preset.id),
              if (busy) const ColoredBox(color: Color(0x66171C19), child: Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: AppColors.lime300)))),
              if (selected && !busy) Positioned(right: 8, top: 8, child: Container(width: 22, height: 22, decoration: const BoxDecoration(color: AppColors.brand, shape: BoxShape.circle),
                  child: const Center(child: PlobbyIcon(PlobbyIcons.check, size: 12, strokeWidth: 3, color: AppColors.brandInk)))),
            ])),
          )),
          const SizedBox(height: 6),
          Text(preset.name, style: const TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 12.5, fontWeight: FontWeight.w600, letterSpacing: 0, color: AppColors.text)),
        ]),
      ));
}

// ───────────────────────────── Encuadre de la foto ─────────────────────────────

/// Foto lista para encuadrar: orientación EXIF aplicada (lo que se ve es lo que se recorta) y como mucho 2400 px.
@immutable
class BannerSource {
  const BannerSource(this.bytes, this.width, this.height);
  final Uint8List bytes;
  final int width, height;
}

/// En un isolate: decodifica, endereza según EXIF y limita a 2400 px (más no aporta calidad a un banner de móvil).
BannerSource prepareBannerSource(Uint8List raw) {
  var image = img.decodeImage(raw);
  if (image == null) throw const FormatException('imagen no válida');
  image = img.bakeOrientation(image);
  if (image.width > 2400 || image.height > 2400) {
    image = image.width >= image.height ? img.copyResize(image, width: 2400) : img.copyResize(image, height: 2400);
  }
  return BannerSource(Uint8List.fromList(img.encodeJpg(image, quality: 92)), image.width, image.height);
}

@immutable
class BannerCropJob {
  const BannerCropJob(this.bytes, this.rect);
  final Uint8List bytes;
  final Rect rect;   // en píxeles de la imagen preparada
}

/// En un isolate: recorta el encuadre elegido, lo reduce a 1200 px de ancho como máximo (sin ampliar nunca: no se
/// pixela) y lo guarda como JPEG de calidad 82 (≈150–300 KB).
Uint8List cropBannerJpeg(BannerCropJob job) {
  final image = img.decodeImage(job.bytes)!;
  final r = job.rect;
  final x = r.left.round().clamp(0, image.width - 1), y = r.top.round().clamp(0, image.height - 1);
  final w = r.width.round().clamp(1, image.width - x), h = r.height.round().clamp(1, image.height - y);
  var out = img.copyCrop(image, x: x, y: y, width: w, height: h);
  if (out.width > 1200) out = img.copyResize(out, width: 1200, height: (1200 / kBannerAspect).round(), interpolation: img.Interpolation.cubic);
  return Uint8List.fromList(img.encodeJpg(out, quality: 82));
}

/// Encuadre: la foto llena siempre el marco del banner (proporción 6:5, sin bandas ni deformación); se mueve con un
/// dedo y se amplía con dos. Encima se ve el degradado y el saludo tal y como quedará en Inicio. Devuelve el
/// rectángulo elegido en píxeles de la imagen.
class BannerCropScreen extends StatefulWidget {
  const BannerCropScreen({super.key, required this.source});
  final BannerSource source;
  @override
  State<BannerCropScreen> createState() => _BannerCropScreenState();
}

class _BannerCropScreenState extends State<BannerCropScreen> {
  final _ctrl = TransformationController();
  Size? _frame;
  double _base = 1;   // escala a la que la foto cubre exactamente el marco

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  void _layout(Size frame) {
    if (_frame == frame) return;
    _frame = frame;
    final s = widget.source;
    _base = [frame.width / s.width, frame.height / s.height].reduce((a, b) => a > b ? a : b);
    final dx = (s.width * _base - frame.width) / 2, dy = (s.height * _base - frame.height) / 2;
    _ctrl.value = Matrix4.translationValues(-dx, -dy, 0);   // centrada
  }

  Rect _cropRect() {
    final f = _frame!;
    final inv = Matrix4.inverted(_ctrl.value);
    final a = MatrixUtils.transformPoint(inv, Offset.zero), b = MatrixUtils.transformPoint(inv, Offset(f.width, f.height));
    return Rect.fromPoints(a / _base, b / _base);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.source;
    return Scaffold(
      backgroundColor: AppColors.ink900,
      body: SafeArea(child: Column(children: [
        Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 8), child: Row(children: [
          IconSquareButton(icon: PlobbyIcons.close, tooltip: 'Cancelar', glass: true, onPressed: () => Navigator.of(context).pop()),
          const Expanded(child: Center(child: Text('AJUSTA TU BANNER', style: TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 1.47, color: AppColors.ink50)))),
          const SizedBox(width: 40),
        ])),
        const Padding(padding: EdgeInsets.fromLTRB(24, 0, 24, 14), child: Text('Arrastra para encuadrar y pellizca para acercar.', textAlign: TextAlign.center,
            style: TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 13, letterSpacing: 0, color: Color(0xB8F6F8F1)))),
        Expanded(child: Center(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: AspectRatio(aspectRatio: kBannerAspect, child: LayoutBuilder(builder: (_, c) {
          _layout(c.biggest);
          return ClipRRect(borderRadius: BorderRadius.circular(18), child: Stack(fit: StackFit.expand, children: [
            InteractiveViewer(transformationController: _ctrl, constrained: false, minScale: 1, maxScale: 4, boundaryMargin: EdgeInsets.zero, clipBehavior: Clip.hardEdge,
                child: SizedBox(width: s.width * _base, height: s.height * _base, child: Image.memory(s.bytes, fit: BoxFit.fill, gaplessPlayback: true))),
            // Vista previa: mismo degradado y textos que el banner real (no reciben toques).
            const IgnorePointer(child: DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter,
                colors: [Color(0x94171C19), Color(0x0D171C19), Color(0x1F171C19), Color(0xC7171C19)], stops: [0, .30, .52, 1])))),
            const IgnorePointer(child: Padding(padding: EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('plobby', style: TextStyle(fontFamily: AppTypography.displayFamily, fontWeight: FontWeight.w700, fontSize: 20, height: 1, letterSpacing: -0.6, color: AppColors.lime300)),
              Spacer(),
              Text('Hola de nuevo', style: TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 22, height: 1.1, fontWeight: FontWeight.w800, letterSpacing: -0.22, color: AppColors.surface)),
            ]))),
          ]));
        }))))),
        // Cancelar = la ✕ de arriba (un botón con borde oscuro no se veía sobre el fondo tinta).
        Padding(padding: const EdgeInsets.fromLTRB(16, 16, 16, 16), child: SizedBox(width: double.infinity,
            child: PlobbyButton(label: 'Guardar banner', onPressed: () => Navigator.of(context).pop(_cropRect())))),
      ])),
    );
  }
}
