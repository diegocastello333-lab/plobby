import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/plobby_theme.dart';
import '../../profile/application/profile_providers.dart';
import '../../profile/domain/models.dart';
import '../../profile/domain/stats_calculator.dart';
import '../application/share_card_painter.dart';
import '../application/share_service.dart';

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
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ok)));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No se pudo generar la imagen')));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(profileProvider('me'));
    return Scaffold(
      appBar: AppBar(title: const Text('Compartir mis stats'), backgroundColor: PlobbyColors.ivory),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => const Center(child: Text('No se pudieron cargar tus datos')),
        data: (d) {
          final size = fmt.size;
          return ListView(padding: const EdgeInsets.all(20), children: [
            Center(child: ConstrainedBox(constraints: const BoxConstraints(maxHeight: 420),
              child: AspectRatio(aspectRatio: size.width / size.height,
                child: ClipRRect(borderRadius: BorderRadius.circular(10), child: FittedBox(child: SizedBox.fromSize(size: size,
                    child: CustomPaint(painter: ShareCardPainter(_data(d), tpl)))))))),
            const SizedBox(height: 18),
            SegmentedButton<ShareTemplate>(showSelectedIcon: false, selected: {tpl}, onSelectionChanged: (s) => setState(() => tpl = s.first),
                segments: const [ButtonSegment(value: ShareTemplate.performance, label: Text('Rendimiento')), ButtonSegment(value: ShareTemplate.streak, label: Text('Racha'))]),
            const SizedBox(height: 10),
            SegmentedButton<StatsPeriod>(showSelectedIcon: false, selected: {period}, onSelectionChanged: (s) => setState(() => period = s.first),
                segments: const [ButtonSegment(value: StatsPeriod.d30, label: Text('30 días')), ButtonSegment(value: StatsPeriod.d90, label: Text('3 meses')), ButtonSegment(value: StatsPeriod.all, label: Text('Todo'))]),
            const SizedBox(height: 10),
            SegmentedButton<ShareFormat>(showSelectedIcon: false, selected: {fmt}, onSelectionChanged: (s) => setState(() => fmt = s.first),
                segments: const [ButtonSegment(value: ShareFormat.story, label: Text('Story 9:16')), ButtonSegment(value: ShareFormat.post, label: Text('Post 4:5'))]),
            SwitchListTile(title: const Text('Mostrar club'), value: showClub && d.profile.club != null, onChanged: d.profile.club == null ? null : (v) => setState(() => showClub = v)),
            SwitchListTile(title: const Text('Mostrar pareja habitual'), value: showPartner && d.profile.partner?.status == PartnerStatus.accepted,
                onChanged: d.profile.partner?.status == PartnerStatus.accepted ? (v) => setState(() => showPartner = v) : null),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: OutlinedButton(onPressed: busy ? null : () => _run(d, (b) => _service.saveToGallery(b, 'plobby-stats-${DateTime.now().millisecondsSinceEpoch}'), 'Imagen guardada'), child: busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Guardar PNG'))),
              const SizedBox(width: 10),
              Expanded(child: FilledButton(onPressed: busy ? null : () => _run(d, (b) => _service.share(b, 'plobby-stats'), 'Compartido'), child: const Text('Compartir'))),
            ]),
          ]);
        },
      ),
    );
  }
}
