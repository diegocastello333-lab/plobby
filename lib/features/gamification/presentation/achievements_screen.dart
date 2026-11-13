import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/design_tokens.dart';
import '../../../core/theme/plobby_text.dart';
import '../../../core/widgets/motion_widgets.dart';
import '../../../core/widgets/plobby_components.dart';
import '../../../core/widgets/plobby_icon.dart';
import '../../../core/widgets/state_views.dart';
import '../application/gamification_providers.dart';
import '../domain/gamification_models.dart';
import 'gamification_widgets.dart';

/// LOGROS: nivel y XP (progresión personal, no habilidad), logros conseguidos, próximos y el catálogo completo.
class AchievementsScreen extends ConsumerWidget {
  const AchievementsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(achievementsProvider);
    return Scaffold(body: SafeArea(bottom: false, child: Column(children: [
      PlobbyHeaderBar(title: 'Logros', onBack: () => context.pop(),
          trailing: IconSquareButton(icon: PlobbyIcons.bell, tooltip: 'Avisos de competición', onPressed: () => showNotificationPrefsSheet(context))),
      Expanded(child: RefreshIndicator(
        color: AppColors.text,
        onRefresh: () async { ref.invalidate(achievementsProvider); await ref.read(achievementsProvider.future); },
        child: async.when(
          skipLoadingOnReload: true,
          loading: () => ListView(padding: const EdgeInsets.all(20), children: const [LoadingBlock(height: 110), SizedBox(height: 16), LoadingBlock(height: 240)]),
          error: (_, __) => ListView(padding: const EdgeInsets.all(20), children: [ErrorStateCard(onRetry: () => ref.invalidate(achievementsProvider))]),
          data: (a) => _Body(a: a),
        ),
      )),
    ])));
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.a});
  final AchievementsData a;
  @override
  Widget build(BuildContext context) {
    final unlocked = a.unlocked, next = a.next.take(3).toList();
    return ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 48), children: [
      AppearOnce(child: LevelCard(data: a)),
      const SizedBox(height: 8),
      Text('El nivel mide tu actividad en Plobby: 100 XP por partido confirmado, +50 si ganas y extra por cada logro.', style: PlobbyText.help),
      if (next.isNotEmpty) ...[
        const SizedBox(height: 24),
        const SectionHeader(title: 'Próximos logros'),
        for (final (i, x) in next.indexed) AppearOnce(index: i, child: _NextTile(x)),
      ],
      const SizedBox(height: 24),
      SectionHeader(title: 'Conseguidos (${unlocked.length}/${a.items.length})'),
      const SizedBox(height: 6),
      if (unlocked.isEmpty) Text('Juega tu primer partido para estrenar la vitrina.', style: PlobbyText.sub)
      else Wrap(spacing: 14, runSpacing: 16, children: [for (final x in unlocked) _BadgeCell(x)]),
      for (final cat in categoryLabels.entries) ...[
        const SizedBox(height: 24),
        SectionHeader(title: cat.value),
        for (final x in a.items.where((i) => i.category == cat.key)) _CatalogTile(x),
      ],
      if (a.history.isNotEmpty) ...[
        const SizedBox(height: 24),
        const SectionHeader(title: 'Historial de XP'),
        for (final e in a.history.take(15)) Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Row(children: [
          Expanded(child: Text(switch (e.type) { 'match' => 'Partido confirmado', 'win' => 'Victoria',
            _ => 'Logro: ${a.items.where((i) => i.id == e.source).firstOrNull?.title ?? e.source}' }, style: PlobbyText.value)),
          Text(shortDate(e.at), style: PlobbyText.help),
          const SizedBox(width: 12),
          Text('+${e.xp} XP', style: const TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 13, fontWeight: FontWeight.w800, letterSpacing: 0, color: AppColors.text)),
        ])),
      ],
    ]);
  }
}

class _BadgeCell extends StatelessWidget {
  const _BadgeCell(this.x);
  final AchievementItem x;
  @override
  Widget build(BuildContext context) => Semantics(label: '${x.title}, conseguido el ${shortDate(x.unlockedAt!)}', excludeSemantics: true,
      child: SizedBox(width: 76, child: Column(children: [
        AchievementBadge(x, size: 60),
        const SizedBox(height: 6),
        Text(x.title, maxLines: 2, textAlign: TextAlign.center, style: PlobbyText.help.copyWith(fontSize: 11.5, fontWeight: FontWeight.w700, color: AppColors.text)),
      ])));
}

class _NextTile extends StatelessWidget {
  const _NextTile(this.x);
  final AchievementItem x;
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.only(bottom: 10), child: SurfaceCard(child: Row(children: [
        AchievementBadge(x, size: 48),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(x.title, style: PlobbyText.cardTitle),
          Text(x.description, style: PlobbyText.help),
          if (x.goal > 1) ...[
            const SizedBox(height: 8),
            ClipRRect(borderRadius: BorderRadius.circular(3), child: LinearProgressIndicator(value: x.fraction, minHeight: 6, color: AppColors.text, backgroundColor: AppColors.surfaceSunken)),
            const SizedBox(height: 4),
            Text('${x.progress.clamp(0, x.goal)} / ${x.goal}', style: PlobbyText.help.copyWith(fontSize: 11.5)),
          ],
        ])),
        const SizedBox(width: 8),
        Text('+${x.xp} XP', style: PlobbyText.help.copyWith(fontWeight: FontWeight.w700)),
      ])));
}

class _CatalogTile extends StatelessWidget {
  const _CatalogTile(this.x);
  final AchievementItem x;
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Row(children: [
        AchievementBadge(x, size: 40),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(x.title, style: PlobbyText.value.copyWith(fontWeight: FontWeight.w700, color: x.unlocked ? AppColors.text : AppColors.textMuted)),
          Text(x.unlocked ? 'Conseguido el ${shortDate(x.unlockedAt!)}' : x.description, style: PlobbyText.help),
        ])),
        if (x.unlocked) const PlobbyIcon(PlobbyIcons.check, size: 16) else Text('+${x.xp}', style: PlobbyText.help),
      ]));
}

/// Preferencias de avisos de competición (se guardan en el servidor: valen en todos los dispositivos).
Future<void> showNotificationPrefsSheet(BuildContext context) => showPlobbySheet<void>(context, (_) => const _PrefsSheet());

class _PrefsSheet extends ConsumerStatefulWidget {
  const _PrefsSheet();
  @override
  ConsumerState<_PrefsSheet> createState() => _PrefsSheetState();
}

class _PrefsSheetState extends ConsumerState<_PrefsSheet> {
  NotificationPrefs? _p;
  @override
  Widget build(BuildContext context) {
    final async = ref.watch(notificationPrefsProvider);
    final p = _p ?? async.valueOrNull;
    Future<void> save(NotificationPrefs n) async {
      setState(() => _p = n);
      try {
        await ref.read(gamificationRepositoryProvider).savePrefs(n);
        ref.invalidate(notificationPrefsProvider);
      } catch (_) {
        if (mounted) { setState(() => _p = null); showPlobbySnack(context, 'No se pudo guardar. Revisa tu conexión.', error: true); }
      }
    }
    Widget row(String title, String sub, bool v, NotificationPrefs Function(bool) f) => SwitchListTile.adaptive(
        contentPadding: EdgeInsets.zero, value: v, onChanged: p == null ? null : (x) => save(f(x)), activeTrackColor: AppColors.text,
        title: Text(title, style: PlobbyText.value.copyWith(fontWeight: FontWeight.w700)), subtitle: Text(sub, style: PlobbyText.help));
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SheetHeader(title: 'Avisos de competición', subtitle: 'Como mucho 3 avisos de ranking al día.'),
      if (p == null) const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator(color: AppColors.text)))
      else ...[
        row('Ranking', 'Si un amigo te adelanta, subes de puesto o termina una temporada.', p.ranking, (x) => p.copyWith(ranking: x)),
        row('Logros', 'Cuando desbloqueas un logro.', p.achievements, (x) => p.copyWith(achievements: x)),
        row('Niveles', 'Cuando subes de nivel.', p.levels, (x) => p.copyWith(levels: x)),
        row('Plobby Wrapped', 'Cuando tu resumen del mes está listo.', p.wrapped, (x) => p.copyWith(wrapped: x)),
      ],
    ]);
  }
}

/// Celebración de logros nuevos: se muestra una vez (al abrir la app o al volver a ella) y los marca como vistos.
class AchievementCelebration extends ConsumerStatefulWidget {
  const AchievementCelebration({super.key, required this.child});
  final Widget child;
  @override
  ConsumerState<AchievementCelebration> createState() => _AchievementCelebrationState();
}

class _AchievementCelebrationState extends ConsumerState<AchievementCelebration> with WidgetsBindingObserver {
  bool _showing = false;
  final _celebrated = <String>{};
  @override
  void initState() { super.initState(); WidgetsBinding.instance.addObserver(this); }
  @override
  void dispose() { WidgetsBinding.instance.removeObserver(this); super.dispose(); }
  @override
  void didChangeAppLifecycleState(AppLifecycleState s) { if (s == AppLifecycleState.resumed) ref.invalidate(achievementsProvider); }

  Future<void> _celebrate(List<AchievementItem> items) async {
    if (_showing || items.isEmpty || !mounted) return;
    _showing = true;
    _celebrated.addAll(items.map((a) => a.id));
    HapticFeedback.mediumImpact();
    await showPlobbySheet<void>(context, (_) => _CelebrationSheet(items: items));
    try { await ref.read(gamificationRepositoryProvider).markAchievementsSeen(); } catch (_) {/* se reintentará la próxima vez */}
    ref.invalidate(achievementsProvider);
    _showing = false;
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(achievementsProvider, (_, next) {
      // Solo con datos definitivos: durante una recarga Riverpod conserva los datos ANTERIORES (aún «sin ver»), y eso
      // volvía a lanzar la celebración. Además, cada logro se celebra una sola vez por sesión.
      if (next.isLoading || !next.hasValue) return;
      final unseen = next.value!.unseen.where((a) => !_celebrated.contains(a.id)).toList();
      if (unseen.isNotEmpty) WidgetsBinding.instance.addPostFrameCallback((_) => _celebrate(unseen));
    });
    return widget.child;
  }
}

class _CelebrationSheet extends StatelessWidget {
  const _CelebrationSheet({required this.items});
  final List<AchievementItem> items;
  @override
  Widget build(BuildContext context) => Column(mainAxisSize: MainAxisSize.min, children: [
        const SizedBox(height: 8),
        PopOnEvent(trigger: 1, glow: true, child: AchievementBadge(items.first, size: 112)),
        const SizedBox(height: 18),
        Text(items.length == 1 ? '¡Logro desbloqueado!' : '¡${items.length} logros desbloqueados!', style: PlobbyText.t2),
        const SizedBox(height: 6),
        Text(items.first.title, textAlign: TextAlign.center, style: PlobbyText.sec),
        const SizedBox(height: 4),
        Text(items.first.description, textAlign: TextAlign.center, style: PlobbyText.sub),
        if (items.length > 1) Padding(padding: const EdgeInsets.only(top: 10), child: Text('Y además: ${items.skip(1).map((i) => i.title).join(', ')}',
            textAlign: TextAlign.center, style: PlobbyText.help)),
        const SizedBox(height: 10),
        Text('+${items.fold<int>(0, (a, b) => a + b.xp)} XP', style: const TextStyle(fontFamily: AppTypography.displayFamily, fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: 0, color: AppColors.text)),
        const SizedBox(height: 18),
        PlobbyButton(label: 'Ver mis logros', onPressed: () { Navigator.of(context).pop(); context.push('/achievements'); }),
      ]);
}
