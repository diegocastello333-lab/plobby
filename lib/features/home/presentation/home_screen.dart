import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../../core/theme/design_tokens.dart';
import '../../../core/theme/plobby_text.dart';
import '../../../core/widgets/motion_widgets.dart';
import 'banner_catalog.dart';
import 'banner_editor.dart';
import '../../../core/widgets/plobby_icon.dart';
import '../../../core/widgets/silhouette_avatar.dart';
import '../../../core/widgets/state_views.dart';
import '../../feed/application/feed_providers.dart';
import '../../feed/domain/feed_models.dart';
import '../../matches/presentation/upcoming_matches_section.dart';
import '../../profile/application/profile_providers.dart';
import '../../profile/domain/achievements.dart';
import '../../profile/domain/models.dart';
import '../../social/application/social_providers.dart';
import 'home_wiring.dart';

/// Últimas partidas confirmadas de amigos (fuente: feed, filtro «Partidos»; la RLS limita a amigos).
final friendMatchesProvider = FutureProvider.autoDispose<List<FeedPost>>((ref) async {
  final page = await ref.watch(feedRepositoryProvider).fetchPage(filter: FeedFilter.matches, limit: 20);
  return page.posts.where((p) => p.author.id != 'me' && p.payload is MatchPayload).toList();
});

String greeting(DateTime now) => now.hour < 6 ? 'Buenas noches,' : now.hour < 14 ? 'Buenos días,' : now.hour < 21 ? 'Buenas tardes,' : 'Buenas noches,';

const _months = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];

/// Antetítulo de fecha de las tarjetas «Últimos partidos jugados» (HTML: «AYER», «6 NOV»).
String playedEyebrow(DateTime d, DateTime now) {
  final day = DateTime(d.year, d.month, d.day), today = DateTime(now.year, now.month, now.day);
  final diff = today.difference(day).inDays;
  if (diff == 0) return 'HOY';
  if (diff == 1) return 'AYER';
  return '${d.day} ${_months[d.month - 1]}'.toUpperCase();
}

String _hhmm(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

/// Pantalla de Inicio — reproduce `#home` del prototipo HTML (Plobby (4).html):
/// banner 300 px con foto y degradado · logo · 3 botones de cristal · avatar + saludo · tarjetas de amigos / ELO / racha
/// que solapan el banner · Próximos partidos · Últimas partidas de amigos · Últimos partidos jugados · Logros.
/// Todos los valores vienen de providers reales (ninguna cifra fija). Medidas tomadas con getComputedStyle.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.watch(homeCountersProvider);
    final view = ref.watch(profileViewProvider('me'));
    return Scaffold(
      body: RefreshIndicator(
        color: AppColors.text,
        onRefresh: () async {
          ref.invalidate(profileProvider('me')); ref.invalidate(friendsProvider); ref.invalidate(friendMatchesProvider); ref.invalidate(notificationsProvider);
          try { await ref.read(profileProvider('me').future); } catch (_) {/* el error se muestra en la sección */}
        },
        child: ListView(padding: EdgeInsets.zero, children: [
          _Banner(counters: c, profile: view.valueOrNull?.data.profile),
          // margin-top: −34px del HTML: TODO el bloque sube 34 px (las tarjetas solapan el banner y las secciones las
          // siguen sin hueco). Padding lateral 20 y 150 abajo (espacio para la barra inferior).
          Transform.translate(offset: const Offset(0, -34), child: Padding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 150), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _Counters(counters: c),
            const SizedBox(height: 30),
            const _SecHead('Próximos partidos'),
            const SizedBox(height: 12),
            const UpcomingMatchesSection(max: 3, showTitle: false),
            const SizedBox(height: 30 - 12),
            _SecHead('Últimas partidas de amigos', action: 'Ver todas', onAction: () => HomeNav.seeAllFriendMatches(context)),
            const SizedBox(height: 12),
            const _FriendMatches(),
            const SizedBox(height: 30),
            _SecHead('Últimos partidos jugados', action: 'Ver todos', onAction: () => HomeNav.seeAllMyMatches(context)),
            const SizedBox(height: 14),
            view.when(
              loading: () => const Column(children: [LoadingBlock(height: 82, radius: 20), SizedBox(height: 10), LoadingBlock(height: 82, radius: 20)]),
              error: (_, __) => ErrorStateCard(onRetry: () => ref.invalidate(profileProvider('me'))),
              data: (v) {
                final ms = v.confirmed.take(3).toList();
                if (ms.isEmpty) {
                  return EmptyStateCard(icon: Icons.sports_tennis, title: 'Aún no has jugado partidos', text: 'Cuando se confirme tu primer resultado aparecerá aquí.',
                      primary: 'Crear partido', onPrimary: () => HomeNav.newMatch(context));
                }
                final now = DateTime.now();
                return Column(children: [
                  for (var i = 0; i < ms.length; i++) ...[
                    if (i > 0) const SizedBox(height: 10),
                    AppearOnce(animationKey: 'played:${ms[i].id}', index: i, child: _PlayedCard(match: ms[i], now: now, onTap: () => HomeNav.match(context, '${ms[i].id}/final'))),
                  ],
                ]);
              },
            ),
            const SizedBox(height: 30),
            _SecHead('Logros', action: 'Ver todos', onAction: () => HomeNav.seeAllAchievements(context)),
            const SizedBox(height: 14),
            view.when(
              loading: () => const LoadingBlock(height: 140),
              error: (_, __) => const SizedBox.shrink(),
              data: (v) => _Achievements(items: v.achievements),
            ),
          ]))),
        ]),
      ),
    );
  }
}

/// Cabecera de sección del Inicio: `h2.sec` + enlace `.lnk-all` alineados por la línea base (el enlace conserva
/// 44 px de zona táctil sin empujar el layout, como el `margin:-8px 0` del CSS).
class _SecHead extends StatelessWidget {
  const _SecHead(this.title, {this.action, this.onAction});
  final String title; final String? action; final VoidCallback? onAction;
  @override
  // Mínimo 28 px; si el título ocupa dos líneas (pantallas estrechas), la fila crece como en el HTML.
  Widget build(BuildContext context) => ConstrainedBox(constraints: const BoxConstraints(minHeight: 28), child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        Expanded(child: Semantics(header: true, child: Text(title, style: PlobbyText.sec, maxLines: 2, overflow: TextOverflow.ellipsis))),
        // 28 px en el layout y 44 px de zona táctil (el CSS usa min-height 44 con margin −8px 0).
        if (action != null) SizedBox(width: 96, height: 28, child: OverflowBox(alignment: Alignment.centerRight, minHeight: 44, maxHeight: 44, maxWidth: 96,
            child: SectionLink(label: action!, onTap: onAction))),
      ]));
}

// ─────────────────────────────── Banner ───────────────────────────────
class _Banner extends StatelessWidget {
  const _Banner({required this.counters, required this.profile});
  final HomeCounters counters; final PlayerProfile? profile;
  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    final first = (profile?.fullName ?? '').trim().split(RegExp(r'\s+')).first;
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(28)),
      child: SizedBox(height: 300 + top, child: Stack(fit: StackFit.expand, children: [
        const ColoredBox(color: AppColors.ink900),
        // Banner personalizable (foto propia, predeterminado o el clásico). Mantener pulsado también abre el editor.
        GestureDetector(onLongPress: () => showBannerSheet(context), child: AnimatedSwitcher(duration: const Duration(milliseconds: 350),
            child: KeyedSubtree(key: ValueKey('${profile?.bannerUrl}|${profile?.bannerId}'), child: BannerImage(profile: profile)))),
        const DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter,
            colors: [Color(0x94171C19), Color(0x0D171C19), Color(0x1F171C19), Color(0xC7171C19)], stops: [0, .30, .52, 1]))),
        // Logo: Unbounded 700 24px −0.03em lima, sombra 0 1 8 .55
        Positioned(left: 20, top: top + 20, child: Semantics(label: 'Plobby', image: true, child: const Text('plobby', style: TextStyle(
            fontFamily: AppTypography.displayFamily, fontWeight: FontWeight.w700, fontSize: 24, height: 1, letterSpacing: -0.72, color: AppColors.lime300,
            shadows: [Shadow(color: Color(0x8C171C19), blurRadius: 8, offset: Offset(0, 1))])))),
        Positioned(right: 20, top: top + 16, child: Row(children: [
          _GlassButton(icon: PlobbyIcons.userplus, label: 'Añadir amigos', onTap: () => HomeNav.addFriends(context)),
          const SizedBox(width: 8),
          _GlassButton(icon: PlobbyIcons.bell, label: 'Notificaciones', badge: counters.unreadNotifications, onTap: () => HomeNav.notifications(context)),
          const SizedBox(width: 8),
          _GlassButton(icon: PlobbyIcons.plane, label: 'Mensajes', badge: counters.unreadMessages, onTap: () => HomeNav.messages(context)),
        ])),
        Positioned(right: 20, bottom: 46, child: _GlassButton(icon: PlobbyIcons.image, label: 'Personalizar banner', onTap: () => showBannerSheet(context))),
        Positioned(left: 20, right: 76, bottom: 46, child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Semantics(button: true, label: 'Ver mi perfil', excludeSemantics: true, child: GestureDetector(onTap: () => HomeNav.profile(context),
              child: Container(width: 68, height: 68, padding: const EdgeInsets.all(3), decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.lime300),
                  child: ClipOval(child: profile?.avatarUrl != null && profile!.avatarUrl!.isNotEmpty
                      ? Image.network(profile!.avatarUrl!, fit: BoxFit.cover, cacheWidth: 186, errorBuilder: (_, __, ___) => SilhouetteAvatar(seed: profile?.id ?? 'me', size: 62))
                      : SilhouetteAvatar(seed: profile?.id ?? 'me', size: 62))))),
          const SizedBox(height: 10),
          Text(greeting(DateTime.now()), style: PlobbyText.hello.copyWith(shadows: const [Shadow(color: Color(0x66000000), blurRadius: 14, offset: Offset(0, 2))])),
          Text(first.isEmpty ? ' ' : first, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: PlobbyText.hello.copyWith(shadows: const [Shadow(color: Color(0x66000000), blurRadius: 14, offset: Offset(0, 2))])),
        ])),
      ])),
    );
  }
}

/// `.hbtn`: 44 px, círculo de cristal (fondo marfil .16, borde .32, desenfoque 10) e icono marfil; contador `.cnt` lima.
class _GlassButton extends StatelessWidget {
  const _GlassButton({required this.icon, required this.label, required this.onTap, this.badge = 0});
  final PlobbyIcons icon; final String label; final VoidCallback onTap; final int badge;
  @override
  Widget build(BuildContext context) => Semantics(
        button: true, label: badge > 0 ? '$label, $badge sin leer' : label, excludeSemantics: true,
        child: Pressable(child: SizedBox(width: 44, height: 44, child: Stack(clipBehavior: Clip.none, children: [
          ClipOval(child: BackdropFilter(filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10), child: Material(
            color: const Color(0x29F6F8F1), shape: const CircleBorder(side: BorderSide(color: Color(0x52F6F8F1))),
            child: InkWell(customBorder: const CircleBorder(), onTap: onTap, child: const SizedBox(width: 44, height: 44)),
          ))),
          IgnorePointer(child: Center(child: PlobbyIcon(icon, size: 24, color: AppColors.ink50))),
          if (badge > 0) Positioned(top: -4, right: -4, child: IgnorePointer(child: Container(
            constraints: const BoxConstraints(minWidth: 18), height: 18, padding: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(color: AppColors.lime300, borderRadius: BorderRadius.circular(9)),
            alignment: Alignment.center,
            child: Text(badge > 99 ? '99+' : '$badge', style: const TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 11, height: 1, fontWeight: FontWeight.w700, letterSpacing: 0, color: AppColors.ink900)),
          ))),
        ]))),
      );
}

// ─────────────────────────── Tarjetas amigos · ELO · racha ───────────────────────────
class _Counters extends ConsumerWidget {
  const _Counters({required this.counters});
  final HomeCounters counters;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = counters;
    final friends = (ref.watch(friendsProvider).valueOrNull ?? const []).take(3).toList();
    final delta = c.delta30 ?? 0;
    return IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Expanded(flex: 135, child: _LiftedCard(
        label: 'Amigos: ${c.friends}. Ver todos', onTap: () => HomeNav.friends(context),
        child: Row(children: [
          if (friends.isNotEmpty) ...[
            SizedBox(width: 26 + 17.0 * (friends.length - 1), height: 26, child: Stack(children: [
              for (var i = friends.length - 1; i >= 0; i--)
                Positioned(left: 17.0 * i, child: Container(width: 26, height: 26, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: AppColors.surface, width: 2)),
                    child: ClipOval(child: friends[i].player.avatarUrl != null
                        ? Image.network(friends[i].player.avatarUrl!, fit: BoxFit.cover, cacheWidth: 66, errorBuilder: (_, __, ___) => SilhouetteAvatar(seed: friends[i].player.id, size: 22))
                        : SilhouetteAvatar(seed: friends[i].player.id, size: 22)))),
            ])),
            const SizedBox(width: 10),
          ],
          Flexible(child: _StatText(value: '${c.friends}', label: 'Amigos', number: c.friends, memoryKey: 'home:friends')),
        ]),
      )),
      const SizedBox(width: 10),
      Expanded(flex: 100, child: _LiftedCard(
        label: c.elo == null ? 'ELO' : 'ELO ${c.elo}${delta == 0 ? '' : ', ${delta > 0 ? '+' : '−'}${delta.abs()} puntos en 30 días'}. Ver detalle',
        onTap: () => HomeNav.elo(context),
        child: _StatText(value: c.elo == null ? '—' : '${c.elo}', number: c.elo, memoryKey: 'home:elo', label: 'ELO', trailing: delta == 0 ? null : Row(mainAxisSize: MainAxisSize.min, children: [
          Transform.rotate(angle: delta > 0 ? 0 : 1.5708, child: SvgPicture.string(
              '<svg viewBox="0 0 24 24" fill="none" stroke="${delta > 0 ? '#171C19' : '#C4282E'}" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"><path d="M7 17 17 7M8 7h9v9"/></svg>',
              width: 9, height: 9)),
          const SizedBox(width: 1),
          Text('${delta.abs()}', style: TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 12, height: 1, fontWeight: FontWeight.w700, letterSpacing: 0, color: delta > 0 ? AppColors.text : AppColors.danger)),
        ])),
      )),
      const SizedBox(width: 10),
      SizedBox(width: 68, child: _LiftedCard(
        label: 'Racha actual: ${c.streak} ${c.streak == 1 ? 'partido ganado' : 'partidos ganados'} seguidos', onTap: () => HomeNav.streak(context, c),
        padding: const EdgeInsets.all(6),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          // La llama «salta» con un destello cuando la racha cambia (victoria confirmada).
          PopOnEvent(trigger: c.streak, glow: c.streak > 0, child: SizedBox(width: 25, height: 31, child: Stack(children: [
            SvgPicture.string('<svg viewBox="0 0 32 40"><path d="M16 2C17 9 27 13 27 24a11 11 0 0 1-22 0c0-4 1.6-6.8 3.8-9.2.4 3.2 2.2 5 4.2 5.6C11.4 12 12.6 6 16 2z" fill="${c.streak > 0 ? '#D2F548' : '#EEF1EA'}"/></svg>', width: 25, height: 31),
            Positioned(left: 0, right: 0, top: 14, child: Text('${c.streak}', textAlign: TextAlign.center,
                style: const TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 12, height: 1, fontWeight: FontWeight.w800, letterSpacing: 0, color: AppColors.text))),
          ]))),
          const SizedBox(height: 3),
          const Text('Racha de victorias', textAlign: TextAlign.center, maxLines: 2,
              style: TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 9, height: 1.1, fontWeight: FontWeight.w600, letterSpacing: 0, color: AppColors.textMuted)),
        ]),
      )),
    ]));
  }
}

/// Tarjeta blanca de 68 px, radio 20, sombra `lifted` (#hb-fr / #hb-elo / #hb-st).
class _LiftedCard extends StatelessWidget {
  const _LiftedCard({required this.label, required this.onTap, required this.child, this.padding = const EdgeInsets.symmetric(horizontal: 14)});
  final String label; final VoidCallback onTap; final Widget child; final EdgeInsets padding;
  @override
  Widget build(BuildContext context) => Semantics(
        button: true, label: label, excludeSemantics: true,
        child: Pressable(child: Container(
          constraints: const BoxConstraints(minHeight: 68),
          decoration: const BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.all(Radius.circular(20)), boxShadow: AppShadows.lifted),
          child: Material(type: MaterialType.transparency, child: InkWell(borderRadius: const BorderRadius.all(Radius.circular(20)), onTap: onTap,
              child: Padding(padding: padding, child: Align(alignment: Alignment.centerLeft, child: child)))),
        )),
      );
}

class _StatText extends StatelessWidget {
  const _StatText({required this.value, required this.label, this.trailing, this.number, this.memoryKey});
  final String value, label; final Widget? trailing;
  /// Si hay valor numérico real, se anima su cambio (LiveNumber); si no, se muestra [value] tal cual.
  final int? number; final String? memoryKey;
  @override
  // En pantallas estrechas (320 px) la cifra y la etiqueta se reducen en vez de desbordar la tarjeta.
  Widget build(BuildContext context) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: number == null
            ? Text(value, style: PlobbyText.stat)
            : LiveNumber(value: number!, memoryKey: memoryKey ?? label, style: PlobbyText.stat)),
        const SizedBox(height: 4),
        FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(label, style: const TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 12, height: 1, fontWeight: FontWeight.w500, letterSpacing: 0, color: AppColors.textMuted)),
          if (trailing != null) ...[const SizedBox(width: 6), trailing!],
        ])),
      ]);
}

// ─────────────────────── Últimas partidas de amigos ───────────────────────
/// Fila de amigos (anillo 66 px, borde 2 tinta; seleccionado = anillo relleno) + panel del partido elegido
/// (tarjeta blanca con marcador por sets y «Ver partido»). El HTML muestra «VIVO» y un panel oscuro solo cuando el
/// partido está en juego; el feed solo trae partidos confirmados, así que aquí no se da ese caso.
class _FriendMatches extends ConsumerStatefulWidget {
  const _FriendMatches();
  @override
  ConsumerState<_FriendMatches> createState() => _FriendMatchesState();
}

class _FriendMatchesState extends ConsumerState<_FriendMatches> {
  int _sel = 0;
  @override
  Widget build(BuildContext context) => ref.watch(friendMatchesProvider).when(
        loading: () => const LoadingBlock(height: 210),
        error: (_, __) => ErrorStateCard(onRetry: () => ref.invalidate(friendMatchesProvider)),
        data: (posts) {
          final seen = <String>{};
          final latest = [for (final p in posts) if (seen.add(p.author.id)) p].take(10).toList();
          if (latest.isEmpty) {
            return EmptyStateCard(icon: Icons.group_outlined, title: 'Tus amigos aún no han jugado', text: 'Cuando un amigo confirme un partido lo verás aquí.',
                primary: 'Añadir amigos', onPrimary: () => HomeNav.addFriends(context));
          }
          final sel = _sel.clamp(0, latest.length - 1);
          final p = latest[sel], m = p.payload as MatchPayload;
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            // .row#stories: margin 0 −20px; padding 4px 20px 12px; gap 14
            Transform.translate(offset: Offset.zero, child: SizedBox(height: 66 + 12 + 17 + 16, child: OverflowBox(maxWidth: MediaQuery.sizeOf(context).width, child: ListView.separated(
              scrollDirection: Axis.horizontal, padding: const EdgeInsets.fromLTRB(20, 4, 20, 12), itemCount: latest.length, separatorBuilder: (_, __) => const SizedBox(width: 14),
              itemBuilder: (_, i) => _Story(user: latest[i].author, selected: i == sel, onTap: () => setState(() => _sel = i)),
            )))),
            const SizedBox(height: 2),
            _FriendMatchPanel(post: p, match: m),
          ]);
        },
      );
}

class _Story extends StatelessWidget {
  const _Story({required this.user, required this.selected, required this.onTap});
  final FeedUser user; final bool selected; final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final first = user.name.split(' ').first;
    return Semantics(button: true, selected: selected, label: 'Ver el partido de $first', excludeSemantics: true, child: GestureDetector(onTap: onTap, child: SizedBox(width: 68, child: Column(children: [
      AnimatedContainer(duration: const Duration(milliseconds: 200), width: 66, height: 66, padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: AppColors.ink900, width: 2), color: selected ? AppColors.ink900 : Colors.transparent),
          child: ClipOval(child: user.avatarUrl != null && user.avatarUrl!.isNotEmpty
              ? Image.network(user.avatarUrl!, fit: BoxFit.cover, cacheWidth: 168, errorBuilder: (_, __, ___) => SilhouetteAvatar(seed: user.id, size: 56))
              : SilhouetteAvatar(seed: user.id, size: 56))),
      const SizedBox(height: 12),
      Text(first, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 13, height: 1.3, letterSpacing: 0,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500, color: AppColors.text)),
    ]))));
  }
}

class _FriendMatchPanel extends StatelessWidget {
  const _FriendMatchPanel({required this.post, required this.match});
  final FeedPost post; final MatchPayload match;
  @override
  Widget build(BuildContext context) {
    final m = match, d = post.createdAt, now = DateTime.now();
    final day = DateTime(d.year, d.month, d.day), today = DateTime(now.year, now.month, now.day);
    final diff = today.difference(day).inDays;
    final when = diff == 0 ? 'Hoy' : diff == 1 ? 'Ayer' : '${d.day} ${_months[d.month - 1]}';
    String names(List<FeedUser> t) => t.map((u) => u.name).join(' · ');
    Widget row(List<FeedUser> team, bool won, bool teamA) => Row(children: [
          Expanded(child: Text(names(team), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 14, height: 1.3, letterSpacing: 0,
              fontWeight: won ? FontWeight.w700 : FontWeight.w400, color: won ? AppColors.text : AppColors.textMuted))),
          const SizedBox(width: 10),
          for (final s in m.sets) Padding(padding: const EdgeInsets.only(left: 4), child: SizedBox(width: 30, height: 28, child: Center(child: Text('${teamA ? s.$1 : s.$2}',
              style: TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 17, height: 1, letterSpacing: 0, fontFeatures: const [FontFeature.tabularFigures()],
                  fontWeight: (teamA ? s.$1 > s.$2 : s.$2 > s.$1) ? FontWeight.w800 : FontWeight.w500,
                  color: (teamA ? s.$1 > s.$2 : s.$2 > s.$1) ? AppColors.text : AppColors.textMuted))))),
        ]);
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      decoration: const BoxDecoration(color: AppColors.surface, borderRadius: AppRadius.rMd, boxShadow: AppShadows.card),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text([when, if (m.venue != null && m.venue!.isNotEmpty) m.venue!, if (m.leagueName != null) m.leagueName!].join(' · '),
            maxLines: 1, overflow: TextOverflow.ellipsis, style: PlobbyText.sub.copyWith(fontSize: 13, height: 1.3)),
        const SizedBox(height: 12),
        row(m.teamA, m.won, true),
        const SizedBox(height: 8),
        row(m.teamB, !m.won, false),
        const SizedBox(height: 16),
        // Botón oscuro 46 px del HTML. Acción existente: abre el feed, donde está la publicación del partido.
        Semantics(button: true, label: 'Ver partido', excludeSemantics: true, child: Pressable(child: Material(color: AppColors.ink900, borderRadius: AppRadius.rMd,
            child: InkWell(borderRadius: AppRadius.rMd, onTap: () => HomeNav.seeAllFriendMatches(context), child: const SizedBox(height: 46, child: Center(child: Text('Ver partido',
                style: TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: 0, color: AppColors.ink50)))))))),
      ]),
    );
  }
}

// ─────────────────────── Últimos partidos jugados ───────────────────────
/// `article.card` del HTML: radio 20, padding 14 16 14 20, barra lateral de 4 px (tinta si ganó, gris si perdió),
/// foto de la pareja 44 px (desaturada si perdió), antetítulo de fecha, «Con …», sede · hora, píldora y marcador.
class _PlayedCard extends StatelessWidget {
  const _PlayedCard({required this.match, required this.now, required this.onTap});
  final MatchResult match; final DateTime now; final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final m = match, win = m.won;
    final fg = win ? AppColors.text : AppColors.textMuted;
    Widget avatar = m.partner.avatarUrl != null && m.partner.avatarUrl!.isNotEmpty
        ? Image.network(m.partner.avatarUrl!, fit: BoxFit.cover, cacheWidth: 132, errorBuilder: (_, __, ___) => SilhouetteAvatar(seed: m.partner.id, size: 44))
        : SilhouetteAvatar(seed: m.partner.id, size: 44);
    if (!win) avatar = Opacity(opacity: .7, child: ColorFiltered(colorFilter: const ColorFilter.matrix(_grayscale), child: avatar));
    return Semantics(button: true, label: '${win ? 'Victoria' : 'Derrota'} con ${m.partner.name}, ${m.sets.map((s) => '${s.$1}-${s.$2}').join(' ')}', excludeSemantics: true,
        child: Pressable(child: Container(
          decoration: const BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.all(Radius.circular(20)), boxShadow: AppShadows.card),
          child: Material(type: MaterialType.transparency, borderRadius: const BorderRadius.all(Radius.circular(20)), clipBehavior: Clip.antiAlias, child: InkWell(onTap: onTap,
            child: Stack(children: [
              Positioned(left: 0, top: 16, bottom: 16, child: Container(width: 4, decoration: BoxDecoration(color: win ? AppColors.ink900 : const Color(0x665C6660),
                  borderRadius: const BorderRadius.horizontal(right: Radius.circular(4))))),
              Padding(padding: const EdgeInsets.fromLTRB(20, 14, 16, 14), child: Row(children: [
                SizedBox(width: 44, height: 44, child: ClipOval(child: avatar)),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(playedEyebrow(m.playedAt, now), style: const TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 11, height: 1.2, fontWeight: FontWeight.w700, letterSpacing: 1.1, color: AppColors.textMuted)),
                  const SizedBox(height: 3),
                  Text('Con ${m.partner.name}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 16, height: 1.25, fontWeight: FontWeight.w700, letterSpacing: 0, color: fg)),
                  const SizedBox(height: 2),
                  Text([if (m.venue.isNotEmpty) m.venue, _hhmm(m.playedAt)].join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 13, height: 1.3, letterSpacing: 0, color: AppColors.textMuted)),
                ])),
                const SizedBox(width: 12),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Container(padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4), decoration: BoxDecoration(color: win ? AppColors.ink900 : const Color(0x245C6660), borderRadius: AppRadius.rPill),
                      child: Text(win ? 'Victoria' : 'Derrota', style: TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 11, height: 1.2, fontWeight: FontWeight.w700, letterSpacing: .44, color: win ? AppColors.ink50 : AppColors.textMuted))),
                  const SizedBox(height: 8),
                  Text(m.sets.map((s) => '${s.$1}-${s.$2}').join(' '), style: TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 16, height: 1, fontWeight: FontWeight.w700, letterSpacing: 0, color: fg)),
                ]),
              ])),
            ]),
          )),
        )));
  }
}

const _grayscale = <double>[.2126, .7152, .0722, 0, 0, .2126, .7152, .0722, 0, 0, .2126, .7152, .0722, 0, 0, 0, 0, 0, 1, 0];

// ─────────────────────────────── Logros ───────────────────────────────
/// `.badge` del HTML: 84 px de ancho; conseguido = disco lima 76 px con aro interior 62 px (borde 1.5 tinta .3) y
/// trofeo 30 px; bloqueado = círculo discontinuo gris con candado y «n de m». Primero los conseguidos.
class _Achievements extends StatelessWidget {
  const _Achievements({required this.items});
  final List<Achievement> items;
  @override
  Widget build(BuildContext context) {
    final list = [...items]..sort((a, b) => (b.unlocked ? 1 : 0) - (a.unlocked ? 1 : 0));
    return SizedBox(height: 76 + 10 + 33 + 18 + 4, child: OverflowBox(maxWidth: MediaQuery.sizeOf(context).width, child: ListView.separated(
      scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 20), itemCount: list.length, separatorBuilder: (_, __) => const SizedBox(width: 12),
      itemBuilder: (_, i) {
        final a = list[i];
        return Semantics(label: '${a.title}: ${a.unlocked ? 'conseguido' : '${a.current} de ${a.goal}'}', excludeSemantics: true, child: SizedBox(width: 84, child: Column(children: [
          if (a.unlocked)
            Container(width: 76, height: 76, decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.lime300), alignment: Alignment.center,
                child: Container(width: 62, height: 62, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: const Color(0x4D171C19), width: 1.5)),
                    child: const Center(child: PlobbyIcon(PlobbyIcons.trophy, size: 30, color: AppColors.ink900))))
          else
            SizedBox(width: 76, height: 76, child: CustomPaint(painter: _DashedCircle(), child: const Center(child: PlobbyIcon(PlobbyIcons.lock, size: 28, color: AppColors.textMuted)))),
          const SizedBox(height: 10),
          Text(a.title, maxLines: 2, textAlign: TextAlign.center, overflow: TextOverflow.ellipsis,
              style: TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 13, height: 1.25, fontWeight: FontWeight.w700, letterSpacing: 0, color: a.unlocked ? AppColors.text : AppColors.textMuted)),
          const SizedBox(height: 3),
          Text(a.unlocked ? 'Conseguido' : '${a.current} de ${a.goal}', style: const TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 12, height: 1.25, letterSpacing: 0, color: AppColors.textMuted)),
        ])));
      },
    )));
  }
}

/// Borde de 1.5 px discontinuo `rgba(92,102,96,.7)` (logro bloqueado).
class _DashedCircle extends CustomPainter {
  @override
  void paint(Canvas c, Size s) {
    final p = Paint()..color = const Color(0xB35C6660)..style = PaintingStyle.stroke..strokeWidth = 1.5;
    final r = s.width / 2 - .75, center = s.center(Offset.zero);
    const dashes = 36;
    for (var i = 0; i < dashes; i++) {
      final a0 = i * 2 * 3.14159265 / dashes;
      c.drawArc(Rect.fromCircle(center: center, radius: r), a0, 3.14159265 / dashes, false, p);
    }
  }
  @override
  bool shouldRepaint(_DashedCircle o) => false;
}
