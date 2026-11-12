import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/design_tokens.dart';
import '../../../core/theme/plobby_text.dart';
import '../../../core/widgets/plobby_components.dart';
import '../../../core/widgets/plobby_icon.dart';
import '../../../core/widgets/state_views.dart';
import '../../profile/application/profile_providers.dart';
import '../../profile/domain/models.dart';
import '../../profile/domain/stats_calculator.dart';
import '../application/share_card_painter.dart';
import '../application/share_service.dart';

/// «Compartir mis stats» — `scShare` del prototipo HTML: vista previa de la imagen y opciones en botones-filtro
/// (plantilla, periodo, formato y qué mostrar). La imagen la pinta [ShareCardPainter].
class ShareStatsScreen extends ConsumerStatefulWidget {
  const ShareStatsScreen({super.key});
  @override
  ConsumerState<ShareStatsScreen> createState() => _State();
}

class _State extends ConsumerState<ShareStatsScreen> {
  ShareTemplate tpl = ShareTemplate.performance;
  ShareFormat fmt = ShareFormat.story;
  StatsPeriod period = StatsPeriod.d30;
  bool showClub = true, showPartner = true, busy = false;
  final _service = ShareService();

  static const _labels = {StatsPeriod.all: 'Todo el tiempo', StatsPeriod.d30: 'Últimos 30 días', StatsPeriod.d90: 'Últimos 3 meses'};

  ShareCardData _data(ProfileData d) {
    final calc = ref.read(calculatorProvider);
    final stats = calc.stats(d.matches, period), k = calc.streak(d.matches), p = d.profile;
    final range = period == StatsPeriod.all ? EloRange.d365 : period == StatsPeriod.d30 ? EloRange.d30 : EloRange.d90;
    return ShareCardData(
      name: p.fullName, username: p.username, elo: d.currentElo, eloDelta: calc.eloChange(d.matches, d.currentElo, range),
      category: calc.category(d.currentElo), played: stats.played, winRate: stats.winRate, wins: stats.won, losses: stats.lost,
      streak: k.current, bestStreak: k.best, periodLabel: _labels[period]!,
      last: calc.confirmed(d.matches).take(10).map((m) => m.won).toList(),
      club: showClub ? p.club?.name : null,
      partner: showPartner && p.partner?.status == PartnerStatus.accepted ? p.partner!.name : null,
    );
  }

  Future<Uint8List> _png(ProfileData d) => ShareCardPainter.toPng(_data(d), tpl, fmt);

  Future<void> _run(ProfileData d, Future<void> Function(Uint8List) action, String ok) async {
    setState(() => busy = true);
    try {
      await action(await _png(d));
      if (mounted) showPlobbySnack(context, ok);
    } catch (_) {
      if (mounted) showPlobbySnack(context, 'No se pudo generar la imagen', error: true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(profileProvider('me'));
    Widget group<T>(String label, List<(T, String)> opts, T sel, ValueChanged<T> on) => Padding(padding: const EdgeInsets.only(bottom: 14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: PlobbyText.label), const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [for (final o in opts) PlobbyFilterChip(label: o.$2, selected: sel == o.$1, onTap: () => on(o.$1))]),
        ]));
    return Scaffold(
      body: Column(children: [
        PlobbyHeaderBar(title: 'Compartir mis stats', onBack: () => context.pop()),
        Expanded(child: async.when(
          loading: () => const Center(child: CircularProgressIndicator(color: AppColors.text)),
          error: (e, _) => Padding(padding: const EdgeInsets.all(20), child: ErrorStateCard(title: 'No se pudieron cargar tus datos', onRetry: () => ref.invalidate(profileProvider('me')))),
          data: (d) {
            final size = fmt.size;
            final hasClub = d.profile.club != null, hasPartner = d.profile.partner?.status == PartnerStatus.accepted;
            return ListView(padding: EdgeInsets.fromLTRB(20, 16, 20, 40 + MediaQuery.paddingOf(context).bottom), children: [
              Center(child: ConstrainedBox(constraints: const BoxConstraints(maxHeight: 420),
                child: AspectRatio(aspectRatio: size.width / size.height,
                  child: Semantics(label: 'Vista previa de la imagen a compartir', image: true, child: DecoratedBox(
                    decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), boxShadow: AppShadows.pop),
                    child: ClipRRect(borderRadius: BorderRadius.circular(12), child: FittedBox(child: SizedBox.fromSize(size: size,
                        child: CustomPaint(painter: ShareCardPainter(_data(d), tpl)))))))))),
              const SizedBox(height: 20),
              group('Plantilla', const [(ShareTemplate.performance, 'Rendimiento'), (ShareTemplate.streak, 'Racha')], tpl, (v) => setState(() => tpl = v)),
              group('Periodo', const [(StatsPeriod.d30, '30 días'), (StatsPeriod.d90, '3 meses'), (StatsPeriod.all, 'Todo')], period, (v) => setState(() => period = v)),
              group('Formato', const [(ShareFormat.story, 'Story 9:16'), (ShareFormat.post, 'Post 4:5')], fmt, (v) => setState(() => fmt = v)),
              const Text('Mostrar', style: PlobbyText.label), const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: [
                Opacity(opacity: hasClub ? 1 : .45, child: PlobbyFilterChip(label: 'Club', selected: showClub && hasClub, onTap: hasClub ? () => setState(() => showClub = !showClub) : () {})),
                Opacity(opacity: hasPartner ? 1 : .45, child: PlobbyFilterChip(label: 'Pareja habitual', selected: showPartner && hasPartner, onTap: hasPartner ? () => setState(() => showPartner = !showPartner) : () {})),
              ]),
              const SizedBox(height: 20),
              Row(children: [
                Expanded(child: PlobbyButton(label: 'Guardar PNG', kind: PlobbyButtonKind.outline, busy: busy, icon: PlobbyIcons.arrdn,
                    onPressed: () => _run(d, (b) => _service.saveToGallery(b, 'plobby-stats-${DateTime.now().millisecondsSinceEpoch}'), 'Imagen guardada'))),
                const SizedBox(width: 10),
                Expanded(child: PlobbyButton(label: 'Compartir', icon: PlobbyIcons.share, onPressed: busy ? null : () => _run(d, (b) => _service.share(b, 'plobby-stats'), 'Compartido'))),
              ]),
            ]);
          },
        )),
      ]),
    );
  }
}
