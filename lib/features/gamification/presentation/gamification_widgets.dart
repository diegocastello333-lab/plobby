import 'package:flutter/material.dart';
import '../../../core/theme/design_tokens.dart';
import '../../../core/theme/plobby_text.dart';
import '../../../core/widgets/plobby_icon.dart';
import '../domain/gamification_models.dart';

/// Piezas visuales compartidas por Head to Head, Ranking, Wrapped y Logros (mismo lenguaje que el resto de Plobby:
/// tinta, lima, marfil; Unbounded para cifras, Inter para el texto).

const _palette = [(AppColors.inverse, AppColors.brand), (AppColors.inverse, AppColors.ink50), (AppColors.brand, AppColors.brandInk), (AppColors.borderStrong, AppColors.brandInk)];

/// Avatar circular: foto (decodificada al tamaño visible) o iniciales con color estable.
class GAvatar extends StatelessWidget {
  const GAvatar(this.player, {super.key, this.size = 44, this.ring, this.ringWidth = 2});
  final GPlayer player;
  final double size, ringWidth;
  final Color? ring;
  @override
  Widget build(BuildContext context) {
    final (bg, fg) = _palette[player.id.codeUnits.fold<int>(0, (a, c) => a + c) % _palette.length];
    final initials = Container(color: bg, alignment: Alignment.center, child: Text(player.initials,
        style: TextStyle(fontFamily: AppTypography.sansFamily, fontSize: size * .36, fontWeight: FontWeight.w800, letterSpacing: 0, color: fg)));
    final img = player.avatarUrl != null && player.avatarUrl!.isNotEmpty
        ? Image.network(player.avatarUrl!, fit: BoxFit.cover, cacheWidth: (size * 3).round(), errorBuilder: (_, __, ___) => initials)
        : initials;
    return Container(
      width: size, height: size,
      decoration: ring == null ? null : BoxDecoration(shape: BoxShape.circle, border: Border.all(color: ring!, width: ringWidth)),
      padding: EdgeInsets.all(ring == null ? 0 : ringWidth),
      child: ClipOval(child: SizedBox.expand(child: img)),
    );
  }
}

/// Últimos resultados como puntos (lima = victoria, aro = derrota), el más reciente a la DERECHA.
class FormDots extends StatelessWidget {
  const FormDots(this.form, {super.key, this.size = 10, this.onDark = false});
  final String form;
  final double size;
  final bool onDark;
  @override
  Widget build(BuildContext context) => Semantics(label: 'Últimos resultados: ${form.split('').reversed.map((c) => c == 'W' ? 'victoria' : 'derrota').join(', ')}',
      excludeSemantics: true, child: Row(mainAxisSize: MainAxisSize.min, children: [
        for (final c in form.split('').reversed) Container(width: size, height: size, margin: EdgeInsets.only(right: size * .4),
            decoration: BoxDecoration(shape: BoxShape.circle, color: c == 'W' ? AppColors.brand : null,
                border: c == 'W' ? null : Border.all(color: onDark ? const Color(0x80F6F8F1) : AppColors.borderStrong, width: 1.6))),
      ]));
}

/// Barra enfrentada: la parte de cada jugador es proporcional a su valor; el que lidera va en tinta/lima.
class VersusBar extends StatelessWidget {
  const VersusBar({super.key, required this.share, required this.leader, this.height = 8});
  final double share;
  final H2HLeader leader;
  final double height;
  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(begin: .5, end: share), duration: MediaQuery.of(context).disableAnimations ? Duration.zero : const Duration(milliseconds: 700),
        curve: Curves.easeOutCubic,
        builder: (_, v, __) => ClipRRect(borderRadius: BorderRadius.circular(height), child: SizedBox(height: height, child: Row(children: [
          // SizedBox.expand: un ColoredBox sin hijo mide 0 de alto si la fila no le impone altura (las barras no se veían).
          Expanded(flex: (v * 1000).round().clamp(1, 999), child: SizedBox.expand(child: ColoredBox(color: leader == H2HLeader.me ? AppColors.text : const Color(0x33171C19)))),
          const SizedBox(width: 3),
          Expanded(flex: ((1 - v) * 1000).round().clamp(1, 999), child: SizedBox.expand(child: ColoredBox(color: leader == H2HLeader.other ? AppColors.brand : const Color(0x33171C19)))),
        ]))),
      );
}

PlobbyIcons achievementIcon(String icon) => switch (icon) {
      'ball' => PlobbyIcons.racket, 'trophy' => PlobbyIcons.trophy, 'flame' => PlobbyIcons.flame, 'users' => PlobbyIcons.users, _ => PlobbyIcons.star };

/// Insignia de logro: disco lima con icono (desbloqueado) o gris con anillo de progreso (bloqueado).
class AchievementBadge extends StatelessWidget {
  const AchievementBadge(this.item, {super.key, this.size = 56});
  final AchievementItem item;
  final double size;
  @override
  Widget build(BuildContext context) => SizedBox(width: size, height: size, child: Stack(alignment: Alignment.center, children: [
        if (!item.unlocked) SizedBox.expand(child: CircularProgressIndicator(value: item.fraction, strokeWidth: 3,
            color: AppColors.text, backgroundColor: const Color(0x14171C19))),
        Container(
          width: size - (item.unlocked ? 0 : 10), height: size - (item.unlocked ? 0 : 10),
          decoration: BoxDecoration(shape: BoxShape.circle, color: item.unlocked ? AppColors.brand : AppColors.surfaceSunken,
              border: item.unlocked && item.category == 'competition' ? Border.all(color: AppColors.text, width: 2) : null),
          child: Center(child: PlobbyIcon(achievementIcon(item.icon), size: size * .42, strokeWidth: 2,
              color: item.unlocked ? AppColors.brandInk : AppColors.textMuted)),
        ),
      ]));
}

/// Tarjeta de nivel: número de nivel, barra de XP y lo que falta. Animada al aparecer.
class LevelCard extends StatelessWidget {
  const LevelCard({super.key, required this.data, this.compact = false, this.onTap});
  final AchievementsData data;
  final bool compact;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Semantics(button: onTap != null, container: true,
      label: 'Nivel ${data.level}, ${data.xp} XP. Faltan ${data.toNextLevel} XP para el nivel ${data.level + 1}', excludeSemantics: true,
      child: GestureDetector(onTap: onTap, behavior: HitTestBehavior.opaque, child: Container(
        padding: EdgeInsets.all(compact ? 14 : 18),
        decoration: BoxDecoration(color: AppColors.inverse, borderRadius: AppRadius.rLg),
        child: Row(children: [
          Container(width: compact ? 52 : 64, height: compact ? 52 : 64, decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.brand),
              alignment: Alignment.center, child: Text('${data.level}', style: TextStyle(fontFamily: AppTypography.displayFamily,
                  fontSize: compact ? 22 : 26, fontWeight: FontWeight.w700, letterSpacing: -0.5, color: AppColors.brandInk))),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text('NIVEL ${data.level}', style: PlobbyText.eb.copyWith(color: AppColors.brand)),
              const Spacer(),
              Text('${data.xp} XP', style: const TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 12.5, fontWeight: FontWeight.w700, letterSpacing: 0, color: AppColors.ink50)),
            ]),
            const SizedBox(height: 10),
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: data.levelProgress), duration: MediaQuery.of(context).disableAnimations ? Duration.zero : const Duration(milliseconds: 900),
              curve: Curves.easeOutCubic,
              builder: (_, v, __) => ClipRRect(borderRadius: BorderRadius.circular(4), child: LinearProgressIndicator(value: v, minHeight: 8,
                  color: AppColors.brand, backgroundColor: const Color(0x24F6F8F1))),
            ),
            const SizedBox(height: 8),
            Text('Faltan ${data.toNextLevel} XP para el nivel ${data.level + 1}',
                style: const TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 12, letterSpacing: 0, color: Color(0xB3F6F8F1))),
          ])),
          if (onTap != null) ...[const SizedBox(width: 8), const PlobbyIcon(PlobbyIcons.chev, size: 16, color: Color(0x99F6F8F1))],
        ]),
      )));
}

String shortDate(DateTime d) => '${d.day} ${monthName(d.month).substring(0, 3)} ${d.year}';
