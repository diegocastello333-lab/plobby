import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import '../../../core/errors/failure.dart';
import '../../../core/theme/design_tokens.dart';
import '../../../core/theme/plobby_text.dart';
import '../../../core/widgets/motion_widgets.dart';
import '../../../core/widgets/plobby_components.dart';
import '../../../core/widgets/plobby_icon.dart';
import '../../../core/widgets/state_views.dart';
import '../../gamification/domain/gamification_models.dart';
import '../../gamification/presentation/gamification_widgets.dart';
import '../application/club_providers.dart';
import '../domain/club_models.dart';
import 'club_search_sheet.dart';

/// Página del club (`/club/:id`): datos, jugadores que lo tienen como club habitual ordenados por ELO, y ligas del club.
/// Da un motivo para invitar a los compañeros del club.
class ClubScreen extends ConsumerWidget {
  const ClubScreen({super.key, required this.clubId});
  final String clubId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(clubPageProvider(clubId));
    return Scaffold(body: SafeArea(bottom: false, child: Column(children: [
      PlobbyHeaderBar(title: 'Club', onBack: () => context.pop(), trailing: async.valueOrNull == null ? null
          : IconSquareButton(icon: PlobbyIcons.share, tooltip: 'Invitar a jugadores del club',
              onPressed: () => Share.share('Juega con nosotros en ${async.value!.name} con Plobby: https://plobby.vercel.app'))),
      Expanded(child: async.when(
        loading: () => ListView(padding: const EdgeInsets.all(20), children: const [LoadingBlock(height: 140), SizedBox(height: 14), LoadingBlock(height: 260)]),
        error: (e, _) => ListView(padding: const EdgeInsets.all(20), children: [ErrorStateCard(error: e, onRetry: () => ref.invalidate(clubPageProvider(clubId)))]),
        data: (c) => c == null
            ? ListView(padding: const EdgeInsets.all(20), children: const [EmptyStateCard(icon: Icons.sports_tennis, title: 'Club no disponible',
                text: 'Este club no existe o todavía está pendiente de revisión.')])
            : _Body(c: c),
      )),
    ])));
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.c});
  final ClubPage c;
  @override
  Widget build(BuildContext context) {
    final place = [c.area, c.municipality].whereType<String>().where((s) => s.isNotEmpty).join(' · ');
    return ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 40), children: [
      AppearOnce(child: Container(
        padding: const EdgeInsets.all(18),
        decoration: const BoxDecoration(color: AppColors.inverse, borderRadius: AppRadius.rLg),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(spacing: 6, runSpacing: 6, children: [
            _DarkTag(c.type.label),
            if (c.pending) const _DarkTag('Pendiente de revisión'),
          ]),
          const SizedBox(height: 12),
          Semantics(header: true, child: Text(c.name, style: PlobbyText.t1.copyWith(color: AppColors.brand))),
          if (place.isNotEmpty) ...[const SizedBox(height: 6), Text(place, style: PlobbyText.sub.copyWith(color: const Color(0xD9FFFFFF)))],
          if ((c.address ?? '').isNotEmpty) ...[
            const SizedBox(height: 4),
            Text('${c.address}${c.postalCode != null ? ' · ${c.postalCode}' : ''}', style: PlobbyText.help.copyWith(color: const Color(0xB3FFFFFF))),
          ],
          if (c.aliases.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('También conocido como ${c.aliases.join(', ')}', style: PlobbyText.help.copyWith(color: const Color(0xB3FFFFFF))),
          ],
          const SizedBox(height: 14),
          Text(c.playersCount == 1 ? '1 jugador lo tiene como club habitual' : '${c.playersCount} jugadores lo tienen como club habitual',
              style: PlobbyText.value.copyWith(color: AppColors.brand, fontWeight: FontWeight.w700)),
        ]),
      )),
      const SizedBox(height: 22),
      const SectionHeader(title: 'Ranking del club'),
      const SizedBox(height: 8),
      if (c.ranking.isEmpty)
        const EmptyStateCard(icon: Icons.groups_2_outlined, title: 'Aún no hay jugadores', text: 'Invita a tus compañeros del club para competir en su ranking.')
      else
        for (final (i, p) in c.ranking.indexed) AppearOnce(index: i, child: _PlayerRow(pos: i + 1, p: p)),
      const SizedBox(height: 22),
      const SectionHeader(title: 'Ligas del club'),
      const SizedBox(height: 8),
      if (c.leagues.isEmpty)
        Text('Este club todavía no tiene ligas en Plobby.', style: PlobbyText.sub)
      else
        for (final (id, name) in c.leagues) SurfaceCard(margin: const EdgeInsets.only(bottom: 8), onTap: () => context.push('/leagues/$id'),
            child: Row(children: [
              const PlobbyIcon(PlobbyIcons.trophy, size: 18), const SizedBox(width: 10),
              Expanded(child: Text(name, style: PlobbyText.value.copyWith(fontWeight: FontWeight.w700))),
              const PlobbyIcon(PlobbyIcons.chev, size: 16, color: AppColors.textMuted),
            ])),
    ]);
  }
}

class _PlayerRow extends StatelessWidget {
  const _PlayerRow({required this.pos, required this.p});
  final int pos;
  final ClubPlayer p;
  @override
  Widget build(BuildContext context) => Semantics(button: true, label: 'Puesto $pos: ${p.name}${p.elo != null ? ', ${p.elo} de ELO' : ''}', excludeSemantics: true,
      child: SurfaceCard(margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        onTap: p.id == 'me' ? null : () => context.push('/player/${p.id}'),
        child: Row(children: [
          SizedBox(width: 28, child: Text('$pos', textAlign: TextAlign.center, style: PlobbyText.cardTitle)),
          const SizedBox(width: 8),
          GAvatar(GPlayer(id: p.id, name: p.name, username: p.username, avatarUrl: p.avatarUrl), size: 40),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: PlobbyText.cardTitle.copyWith(fontSize: 14)),
            Text([if (p.username.isNotEmpty) '@${p.username}', if ((p.level ?? '').isNotEmpty) p.level!].join(' · '), style: PlobbyText.help),
          ])),
          if (p.elo != null) Text('${p.elo}', style: PlobbyText.cardTitle),
        ])));
}

class _DarkTag extends StatelessWidget {
  const _DarkTag(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: const Color(0x26FFFFFF), borderRadius: BorderRadius.circular(999)),
      child: Text(text, style: PlobbyText.help.copyWith(fontSize: 11.5, fontWeight: FontWeight.w700, color: Colors.white)));
}

/// Cola de moderación (solo administradores): aprobar, rechazar o fusionar propuestas, y añadir alias.
class ClubModerationScreen extends ConsumerWidget {
  const ClubModerationScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(pendingClubsProvider);
    Future<void> act(Future<void> Function() job, String ok) async {
      try {
        await job();
        ref.invalidate(pendingClubsProvider);
        if (context.mounted) showPlobbySnack(context, ok);
      } catch (e) {
        if (context.mounted) showPlobbySnack(context, actionErrorText(e, fallback: 'No se pudo completar. Inténtalo de nuevo.'), error: true);
      }
    }
    return Scaffold(body: SafeArea(bottom: false, child: Column(children: [
      PlobbyHeaderBar(title: 'Moderación de clubes', onBack: () => context.pop()),
      Expanded(child: async.when(
        loading: () => ListView(padding: const EdgeInsets.all(20), children: const [LoadingBlock(height: 120), SizedBox(height: 12), LoadingBlock(height: 120)]),
        error: (e, _) => ListView(padding: const EdgeInsets.all(20), children: [ErrorStateCard(error: e, onRetry: () => ref.invalidate(pendingClubsProvider))]),
        data: (list) => RefreshIndicator(color: AppColors.text, onRefresh: () async => ref.invalidate(pendingClubsProvider),
          child: ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 40), children: [
            if (list.isEmpty) const EmptyStateCard(icon: Icons.verified_outlined, title: 'No hay propuestas pendientes',
                text: 'Cuando alguien proponga un club nuevo aparecerá aquí.'),
            for (final p in list) SurfaceCard(margin: const EdgeInsets.only(bottom: 12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(p.name, style: PlobbyText.cardTitle),
              const SizedBox(height: 2),
              Text([p.municipality, p.type.label, if ((p.address ?? '').isNotEmpty) p.address].whereType<String>().join(' · '), style: PlobbyText.help),
              Text('Propuesto por ${p.creator ?? 'un jugador'} · ${p.players} ${p.players == 1 ? 'jugador lo usa' : 'jugadores lo usan'}', style: PlobbyText.help),
              if (p.similar.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text('Parecidos en el catálogo:', style: PlobbyText.label),
                for (final s in p.similar) Text('· ${s.title}', style: PlobbyText.help),
              ],
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 8, children: [
                PlobbyButton(label: 'Aprobar', kind: PlobbyButtonKind.small,
                    onPressed: () => act(() => ref.read(clubRepositoryProvider).review(p.id, 'approve'), '${p.name} aprobado')),
                PlobbyButton(label: 'Fusionar con…', kind: PlobbyButtonKind.smallOutline, onPressed: () async {
                  final target = await pickClub(context, title: 'Fusionar «${p.name}» con', initialQuery: p.name);
                  if (target == null || target.id == p.id || target.pending || !context.mounted) return;
                  await act(() => ref.read(clubRepositoryProvider).review(p.id, 'merge', targetId: target.id), 'Fusionado con ${target.name}');
                }),
                PlobbyButton(label: 'Rechazar', kind: PlobbyButtonKind.smallOutline,
                    onPressed: () => act(() => ref.read(clubRepositoryProvider).review(p.id, 'reject'), '${p.name} rechazado')),
              ]),
            ])),
          ]),
        ),
      )),
    ])));
  }
}
