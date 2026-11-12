import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/design_tokens.dart';
import '../../../core/theme/plobby_text.dart';
import '../../../core/widgets/plobby_components.dart';
import '../../../core/widgets/plobby_icon.dart';

/// Menú del botón «+» (`ACT.plus` del prototipo): elige el tipo de partido y abre el formulario único
/// (`/match/new?type=...`). Las acciones previas del «+» (crear liga, descubrir ligas) siguen en «Más opciones».
Future<void> showNewMatchMenu(BuildContext context) => showPlobbySheet(context, (_) => const _Menu());

class _Menu extends StatelessWidget {
  const _Menu();
  @override
  Widget build(BuildContext context) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const SheetHeader(title: 'Nuevo partido', subtitle: '¿Qué tipo de partido quieres crear?'),
        const _OptionCard(icon: PlobbyIcons.trophy, title: 'Crear partido de liga', text: 'Registra un partido que forme parte de una liga', dark: false, type: 'league'),
        const SizedBox(height: 12),
        const _OptionCard(icon: PlobbyIcons.racket, title: 'Crear partido amistoso', text: 'Organiza un partido fuera de una competición', dark: true, type: 'friendly'),
        // .mmore: borde superior, «MÁS OPCIONES» y botones-pastilla de 36 px
        Container(
          margin: const EdgeInsets.only(top: 18), padding: const EdgeInsets.only(top: 14),
          decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.border))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('MÁS OPCIONES', style: PlobbyText.eb),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: [
              _MoreButton(icon: PlobbyIcons.trophy, label: 'Crear una liga', onTap: () => _go(context, '/leagues/new')),
              _MoreButton(icon: PlobbyIcons.search, label: 'Descubrir ligas', onTap: () => _go(context, '/leagues/discover')),
            ]),
          ]),
        ),
      ]);
}

/// Cierra la hoja y abre [path]. El router se toma ANTES de cerrar: la hoja vive en el navegador raíz y su contexto
/// deja de ser válido al desmontarse, así que no se usa después del `pop`.
void _go(BuildContext context, String path) {
  final router = GoRouter.of(context);
  Navigator.of(context).pop();
  router.push(path);
}

/// `.mmore button`: 36 px, pastilla, borde interior 1.5 px, Inter 13/600, icono 15.
class _MoreButton extends StatelessWidget {
  const _MoreButton({required this.icon, required this.label, required this.onTap});
  final PlobbyIcons icon; final String label; final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Semantics(button: true, label: label, excludeSemantics: true, child: Material(
        color: Colors.transparent,
        shape: const StadiumBorder(side: BorderSide(color: AppColors.border, width: 1.5)),
        child: InkWell(customBorder: const StadiumBorder(), onTap: onTap, child: SizedBox(height: 36, child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            PlobbyIcon(icon, size: 15, color: AppColors.text), const SizedBox(width: 6),
            Text(label, style: PlobbyText.buttonSmall.copyWith(color: AppColors.text)),
          ]),
        ))),
      ));
}

/// `.mcard` (lima) / `.mcard.alt` (tinta): radio 22, padding 18 16, alto mínimo 96, icono en caja de 52 radio 16,
/// título Unbounded 15/600, texto 13.5 al 82 %, chevron. Al pulsar se reduce a .97 (`:active`).
class _OptionCard extends StatefulWidget {
  const _OptionCard({required this.icon, required this.title, required this.text, required this.dark, required this.type});
  final PlobbyIcons icon; final String title, text, type; final bool dark;
  @override
  State<_OptionCard> createState() => _OptionCardState();
}

class _OptionCardState extends State<_OptionCard> {
  bool _down = false, _done = false;   // _done: un segundo toque rápido no abre dos formularios
  @override
  Widget build(BuildContext context) {
    final bg = widget.dark ? AppColors.inverse : AppColors.brand;
    final fg = widget.dark ? AppColors.bg : AppColors.brandInk;
    final reduce = MediaQuery.of(context).disableAnimations;
    return Semantics(button: true, label: '${widget.title}. ${widget.text}', excludeSemantics: true, child: AnimatedScale(
      scale: _down ? .97 : 1, duration: reduce ? Duration.zero : const Duration(milliseconds: 180), curve: const Cubic(.2, .8, .2, 1),
      child: DecoratedBox(
        decoration: const BoxDecoration(borderRadius: AppRadius.rLg, boxShadow: AppShadows.card),
        child: Material(
          color: bg, borderRadius: AppRadius.rLg,
          child: InkWell(
            borderRadius: AppRadius.rLg, onHighlightChanged: (v) => setState(() => _down = v),
            onTap: () {
              if (_done) return;
              _done = true;
              HapticFeedback.selectionClick();
              _go(context, '/match/new?type=${widget.type}');
            },
            child: ConstrainedBox(constraints: const BoxConstraints(minHeight: 96), child: Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18), child: Row(children: [
              Container(width: 52, height: 52, decoration: BoxDecoration(color: widget.dark ? AppColors.brand : const Color(0x1A171C19), borderRadius: BorderRadius.circular(16)),
                  child: Center(child: PlobbyIcon(widget.icon, size: 26, color: AppColors.brandInk))),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(widget.title, style: TextStyle(fontFamily: AppTypography.displayFamily, fontSize: 15, height: 1.25, fontWeight: FontWeight.w600, letterSpacing: -0.15, color: fg)),
                const SizedBox(height: 4),
                Text(widget.text, style: TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 13.5, height: 1.35, letterSpacing: 0, color: fg.withValues(alpha: .82))),
              ])),
              const SizedBox(width: 14),
              PlobbyIcon(PlobbyIcons.chev, size: 18, strokeWidth: 2.2, color: fg),
            ]))),
          ),
        ),
      ),
    ));
  }
}
