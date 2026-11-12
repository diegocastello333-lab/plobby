import 'package:flutter/material.dart';
import '../../../core/theme/design_tokens.dart';
import '../domain/social_models.dart';

/// Colores de las iniciales (`.av` del prototipo): tinta con lima, tinta con marfil, lima con tinta o salvia con tinta.
const _palette = [(AppColors.inverse, AppColors.brand), (AppColors.inverse, AppColors.ink50), (AppColors.brand, AppColors.brandInk), (AppColors.borderStrong, AppColors.brandInk)];

/// Avatar de jugador (`.av`): foto o iniciales con color estable por usuario y punto lima «en línea» con aro marfil.
class PlayerAvatar extends StatelessWidget {
  const PlayerAvatar(this.p, {super.key, this.size = 46});
  final PlayerSummary p;
  final double size;
  @override
  Widget build(BuildContext context) {
    final (bg, fg) = _palette[p.id.codeUnits.fold<int>(0, (a, c) => a + c) % _palette.length];
    final initials = Container(color: bg, alignment: Alignment.center,
        child: Text(p.initials, style: TextStyle(fontFamily: AppTypography.sansFamily, fontSize: size * .34, fontWeight: FontWeight.w800, letterSpacing: 0, color: fg)));
    return Stack(clipBehavior: Clip.none, children: [
      ClipOval(child: SizedBox(width: size, height: size, child: p.avatarUrl == null || p.avatarUrl!.isEmpty
          ? initials
          : Image.network(p.avatarUrl!, fit: BoxFit.cover, cacheWidth: (size * 3).round(), errorBuilder: (_, __, ___) => initials))),
      if (p.online)
        Positioned(right: -1, bottom: -1, child: Semantics(label: 'En línea', child: Container(width: size * .28, height: size * .28,
            decoration: BoxDecoration(color: AppColors.brand, shape: BoxShape.circle, border: Border.all(color: AppColors.bg, width: 2))))),
    ]);
  }
}

/// Fila de persona (`.li` alta del prototipo): avatar, nombre 15/700, una o dos líneas grises y acciones a la derecha,
/// separada de la anterior por una línea .1. El contenido de la derecha nunca aplasta al nombre (este se recorta).
class PersonRow extends StatelessWidget {
  const PersonRow({super.key, required this.leading, required this.title, this.subtitle, this.trailing, this.onTap, this.titleTrailing, this.semanticsLabel});
  final Widget leading;
  final String title;
  final String? subtitle, semanticsLabel;
  final Widget? trailing, titleTrailing;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Container(
        decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0x1A171C19)))),
        child: Row(children: [
          Expanded(child: Semantics(button: onTap != null, label: semanticsLabel, child: InkWell(onTap: onTap, child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(children: [
              leading,
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Flexible(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: 0, color: AppColors.text))),
                  if (titleTrailing != null) ...[const SizedBox(width: 6), titleTrailing!],
                ]),
                if (subtitle != null) Padding(padding: const EdgeInsets.only(top: 2), child: Text(subtitle!, maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 12.5, height: 1.35, letterSpacing: 0, color: AppColors.textMuted))),
              ])),
            ]),
          )))),
          if (trailing != null) ...[const SizedBox(width: 10), trailing!],
        ]),
      );
}
