import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/design_tokens.dart';
import '../../../core/theme/plobby_text.dart';
import '../../../core/widgets/plobby_components.dart';
import '../../../core/widgets/plobby_icon.dart';
import '../../../core/widgets/state_views.dart';
import '../../profile/application/profile_providers.dart';
import '../application/banner_clock.dart';
import '../domain/banner_schedule.dart';
import 'banner_catalog.dart';

/// Hoja «Banner de Inicio»: el usuario elige la COLECCIÓN (Banner 1 o Banner 2). La imagen de cada momento del día la
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
      const SheetHeader(title: 'Banner de Inicio', subtitle: 'Elige una colección. La imagen cambia sola con tu hora local: amanecer, día, atardecer y noche.'),
      for (final b in HomeBanner.values) Padding(padding: const EdgeInsets.only(bottom: 14),
          child: _CollectionCard(banner: b, phase: phase, selected: b == current, busy: _busy == b, onTap: () => _choose(b, current))),
    ]);
  }
}

class _CollectionCard extends StatelessWidget {
  const _CollectionCard({required this.banner, required this.phase, required this.selected, required this.busy, required this.onTap});
  final HomeBanner banner;
  final DayPhase phase;
  final bool selected, busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(button: true, selected: selected, container: true, excludeSemantics: true,
      label: '${banner.name}, ${banner.description}${selected ? ', seleccionado' : ''}',
      child: GestureDetector(onTap: onTap, behavior: HitTestBehavior.opaque, child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(18), border: Border.all(color: selected ? AppColors.text : const Color(0x1A171C19), width: selected ? 2.5 : 1)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          // Vista grande: la imagen que tocaría AHORA con esta colección.
          ClipRRect(borderRadius: BorderRadius.circular(14), child: AspectRatio(aspectRatio: 2.3, child: Stack(fit: StackFit.expand, children: [
            BannerImage(banner: banner, phase: phase),
            const DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter,
                colors: [Color(0x00171C19), Color(0xB3171C19)], stops: [.45, 1]))),
            Positioned(left: 12, bottom: 10, right: 50, child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(banner.name, style: const TextStyle(fontFamily: AppTypography.displayFamily, fontSize: 16, fontWeight: FontWeight.w700, letterSpacing: -0.3, color: Colors.white)),
              Text(banner.description, style: const TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 12, fontWeight: FontWeight.w500, letterSpacing: 0, color: Color(0xE6FFFFFF))),
            ])),
            if (busy) const ColoredBox(color: Color(0x66171C19), child: Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: AppColors.lime300)))),
            if (selected && !busy) Positioned(right: 10, top: 10, child: Container(width: 26, height: 26, decoration: const BoxDecoration(color: AppColors.brand, shape: BoxShape.circle),
                child: const Center(child: PlobbyIcon(PlobbyIcons.check, size: 14, strokeWidth: 3, color: AppColors.brandInk)))),
          ]))),
          const SizedBox(height: 8),
          // Las cuatro imágenes de la colección, con su franja horaria; la del momento actual, resaltada.
          Padding(padding: const EdgeInsets.fromLTRB(2, 0, 2, 4), child: Row(children: [
            for (final p in DayPhase.values) ...[
              if (p != DayPhase.amanecer) const SizedBox(width: 6),
              Expanded(child: Column(children: [
                Container(
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), border: Border.all(color: p == phase ? AppColors.brand : Colors.transparent, width: 2)),
                  child: ClipRRect(borderRadius: BorderRadius.circular(6), child: AspectRatio(aspectRatio: 16 / 10, child: BannerImage(banner: banner, phase: p))),
                ),
                const SizedBox(height: 4),
                Text(p.label, maxLines: 1, style: TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 11.5, letterSpacing: 0,
                    fontWeight: p == phase ? FontWeight.w800 : FontWeight.w600, color: AppColors.text)),
                Text(p.range.replaceAll(' – ', '–'), maxLines: 1, style: PlobbyText.help.copyWith(fontSize: 10, letterSpacing: 0)),
              ])),
            ],
          ])),
        ]),
      )));
}
