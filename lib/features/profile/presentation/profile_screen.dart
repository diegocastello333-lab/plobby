import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/plobby_theme.dart';
import '../../matches/presentation/upcoming_matches_section.dart';
import '../../../core/motion/app_motion.dart';
import '../../../core/widgets/motion_widgets.dart';
import '../../../core/theme/plobby_text.dart';
import '../application/profile_providers.dart';
import '../domain/models.dart';
import 'widgets/achievement_grid.dart';
import 'widgets/activity_feed.dart';
import 'widgets/elo_card.dart';
import 'widgets/identity_card.dart';
import 'widgets/logout_button.dart';
import 'widgets/match_card.dart';
import 'widgets/profile_header.dart';
import 'widgets/stats_grid.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key, this.playerId = 'me'});
  final String playerId;
  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final _keys = List.generate(4, (_) => GlobalKey());
  int _tab = 0;
  static const _names = ['Resumen', 'Partidos', 'Estadísticas', 'Actividad'];

  void _goTo(int i) {
    setState(() => _tab = i);
    final ctx = _keys[i].currentContext;
    if (ctx != null) Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 350), curve: Curves.easeOutCubic, alignment: .0);
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(profileViewProvider(widget.playerId));
    return Scaffold(
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator(color: PlobbyColors.forest)),
        error: (e, _) => Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.wifi_off, size: 36, color: PlobbyColors.mute), const SizedBox(height: 8),
          const Text('No se pudo cargar el perfil'), const SizedBox(height: 8),
          FilledButton(onPressed: () => ref.invalidate(profileProvider(widget.playerId)), child: const Text('Reintentar')),
        ])),
        data: (v) => _content(v),
      ),
    );
  }

  Widget _section(int? i, String title, Widget child, {Widget? trailing}) => Padding(
      key: i == null ? null : _keys[i], padding: const EdgeInsets.fromLTRB(20, 26, 20, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(height: AppLayout.headerHeight, child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          Expanded(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: PlobbyText.sec)), if (trailing != null) trailing])),  // h2.sec
        const SizedBox(height: 4), child,
      ]));

  Widget _content(ProfileView v) {
    final p = v.data.profile, own = widget.playerId == 'me';
    final me = PlayerRef(p.id, p.fullName, p.avatarUrl);
    final recent = v.confirmed.take(3).toList();
    return CustomScrollView(slivers: [
      SliverToBoxAdapter(child: ProfileHeader(profile: p, isOwner: own)),
      SliverPersistentHeader(pinned: true, delegate: _TabsDelegate(_names, _tab, _goTo)),
      SliverToBoxAdapter(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SizedBox(height: 16),
        IdentityCard(profile: p, isOwner: own),
        _section(0, 'Nivel de juego', EloCard(view: v)),
        _section(null, 'Rendimiento', StatsGrid(view: v)),
        // «Próximos partidos»: MISMA fuente que el Home (upcomingMatchesProvider), antes del historial.
        // La pestaña «Partidos» salta a la PRIMERA sección de partidos. Cada GlobalKey solo puede usarse una vez:
        // repetir _keys[1] en las dos secciones dejaba el perfil propio en blanco («Duplicate keys»).
        if (own) _section(1, 'Próximos partidos', const UpcomingMatchesSection(max: null, showTitle: false)),
        _section(own ? null : 1, 'Últimos partidos', Column(children: [
          if (own) for (final m in v.pending) MatchCard(match: m, me: me, onTap: () => _matchDetail(m)),
          if (recent.isEmpty) const Text('Aún no hay partidos confirmados.', style: TextStyle(color: PlobbyColors.mute)),
          for (final m in recent) MatchCard(match: m, me: me, onTap: () => _matchDetail(m), onShare: own && m.confirmed ? () => context.push('/match/${m.id}/share') : null),
          Align(alignment: Alignment.centerRight, child: SectionLink(label: 'Ver todos los partidos', onTap: () {})),
        ])),
        _section(2, 'Estadísticas completas', StatsGrid(view: v, full: true)),
        _section(null, 'Logros', AchievementGrid(items: v.achievements)),
        _section(3, 'Actividad', ActivityFeed(view: v)),
        if (own) const LogoutButton(),   // solo en el perfil propio, al final y separado
        const SizedBox(height: 120),
      ])),
    ]);
  }

  void _matchDetail(MatchResult m) => showModalBottomSheet(context: context, showDragHandle: true, builder: (sheetCtx) => Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(m.confirmed ? (m.won ? 'VICTORIA' : 'DERROTA') : 'PENDIENTE DE CONFIRMACIÓN', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.4, color: PlobbyColors.mute)),
        Text(m.scoreLabel, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
        const SizedBox(height: 12),
        Text('${m.venue} · ${m.playedAt.day}/${m.playedAt.month}/${m.playedAt.year}'),
        Text('Compañero: ${m.partner.name} · Rivales: ${m.opponents.map((o) => o.name).join(' y ')}'),
        if (m.confirmed) Text('Cambio de ELO: ${m.eloDelta > 0 ? '+' : ''}${m.eloDelta}'),
        if (m.confirmed) Padding(padding: const EdgeInsets.only(top: 16), child: OutlinedButton.icon(onPressed: () { Navigator.pop(sheetCtx); context.push('/match/${m.id}/share'); }, icon: const Icon(Icons.ios_share, size: 18), label: const Text('COMPARTIR RESULTADO'), style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(AppLayout.buttonHeightCompact)))),
      ])));
}

class _TabsDelegate extends SliverPersistentHeaderDelegate {
  _TabsDelegate(this.names, this.sel, this.onTap);
  final List<String> names; final int sel; final ValueChanged<int> onTap;
  // `.tabs .seg` del prototipo (fijo al hacer scroll): fondo marfil, padding 20 12 20 8, pestañas de 46 px.
  @override double get minExtent => 66;
  @override double get maxExtent => 66;
  @override
  Widget build(BuildContext c, double shrink, bool overlaps) => Container(
      color: PlobbyColors.ivory, padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      child: SlidingTabs(labels: names, index: sel, onChanged: onTap));
  @override
  bool shouldRebuild(_TabsDelegate o) => o.sel != sel;
}
