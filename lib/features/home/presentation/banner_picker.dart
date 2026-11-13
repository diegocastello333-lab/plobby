import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/design_tokens.dart';
import '../../../core/widgets/motion_widgets.dart';
import '../../../core/widgets/plobby_components.dart';
import '../../../core/widgets/plobby_icon.dart';
import '../../../core/widgets/state_views.dart';
import '../../profile/application/profile_providers.dart';
import '../application/banner_clock.dart';
import '../domain/banner_schedule.dart';
import 'banner_catalog.dart';

/// Hoja «Banner de Inicio»: el usuario elige la COLECCIÓN (Seaside o Tropical). La imagen de cada momento del día la
/// pone Plobby sola según la hora local. La elección se guarda en el perfil (`profiles.banner_id`): se conserva al
/// cerrar sesión o la app y en cualquier dispositivo.
Future<void> showBannerSheet(BuildContext context) => showPlobbySheet<void>(context, (_) => const _BannerSheet());

class _BannerSheet extends ConsumerStatefulWidget {
  const _BannerSheet();
  @override
  ConsumerState<_BannerSheet> createState() => _BannerSheetState();
}

class _BannerSheetState extends ConsumerState<_BannerSheet> {
  HomeBanner? _busy;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    for (final b in HomeBanner.values) { precacheBanner(context, b); }   // las 8 miniaturas, sin parpadeos
  }

  Future<void> _choose(HomeBanner b, HomeBanner current) async {
    if (_busy != null) return;
    if (b == current) { Navigator.of(context).pop(); return; }
    setState(() => _busy = b);
    try {
      await ref.read(profileRepositoryProvider).setBanner(b.id);
      ref.invalidate(profileProvider('me'));
      HapticFeedback.selectionClick();
      if (mounted) { Navigator.of(context).pop(); showPlobbySnack(context, '${b.name} aplicado'); }
    } catch (_) {
      if (mounted) { setState(() => _busy = null); showPlobbySnack(context, 'No se pudo cambiar el banner. Revisa tu conexión.', error: true); }
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = HomeBanner.fromId(ref.watch(profileProvider('me')).valueOrNull?.profile.bannerId);
    final phase = ref.watch(bannerClockProvider);
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SheetHeader(title: 'Banner de Inicio'),
      Padding(padding: const EdgeInsets.only(bottom: 12), child: Row(children: [
        for (final b in HomeBanner.values) ...[
          if (b != HomeBanner.values.first) const SizedBox(width: 12),
          Expanded(child: _CollectionCard(banner: b, phase: phase, selected: b == current, busy: _busy == b, onTap: () => _choose(b, current))),
        ],
      ])),
    ]);
  }
}

/// Tarjeta de una colección: la imagen que tocaría ahora mismo con ella, su nombre y la marca de seleccionada.
class _CollectionCard extends StatelessWidget {
  const _CollectionCard({required this.banner, required this.phase, required this.selected, required this.busy, required this.onTap});
  final HomeBanner banner;
  final DayPhase phase;
  final bool selected, busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(button: true, selected: selected, container: true, excludeSemantics: true,
      label: '${banner.name}${selected ? ', seleccionado' : ''}',
      child: Pressable(child: GestureDetector(onTap: onTap, behavior: HitTestBehavior.opaque, child: AnimatedContainer(
        duration: const Duration(milliseconds: 200), curve: Curves.easeOut,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(22), border: Border.all(color: selected ? AppColors.text : Colors.transparent, width: 2.5)),
        child: ClipRRect(borderRadius: BorderRadius.circular(18), child: AspectRatio(aspectRatio: .78, child: Stack(fit: StackFit.expand, children: [
          BannerImage(banner: banner, phase: phase),
          const DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter,
              colors: [Color(0x00171C19), Color(0xCC171C19)], stops: [.5, 1]))),
          Positioned(left: 14, right: 14, bottom: 14, child: Text(banner.name, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontFamily: AppTypography.displayFamily, fontSize: 18, height: 1.1, fontWeight: FontWeight.w700, letterSpacing: -0.4, color: Colors.white))),
          if (busy) const ColoredBox(color: Color(0x66171C19), child: Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: AppColors.lime300)))),
          Positioned(right: 10, top: 10, child: AnimatedScale(scale: selected && !busy ? 1 : 0, duration: const Duration(milliseconds: 220), curve: Curves.easeOutBack,
              child: Container(width: 28, height: 28, decoration: const BoxDecoration(color: AppColors.brand, shape: BoxShape.circle),
                  child: const Center(child: PlobbyIcon(PlobbyIcons.check, size: 15, strokeWidth: 3, color: AppColors.brandInk))))),
        ]))),
      ))));
}
