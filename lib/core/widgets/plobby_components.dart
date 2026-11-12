import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/design_tokens.dart';
import '../theme/plobby_text.dart';
import 'motion_widgets.dart';
import 'plobby_icon.dart';

/// Componentes del prototipo HTML. Cada uno reproduce una clase CSS de Plobby (4).html con los valores medidos
/// por `getComputedStyle` (alto, radio, borde, sombra, tipografía). Solo presentación: reciben callbacks.

// ─────────────────────────────────────────────────────────────────────────────
// Botones · `.pbtn` `.obtn` `.sbtn` (`.sbtn.o`)
// ─────────────────────────────────────────────────────────────────────────────
enum PlobbyButtonKind {
  /// `.pbtn` — lima, 48 px, radio 14, Inter 14/600.
  primary,
  /// `.obtn` — transparente con borde interior 1.5 px `#8A938D`, 48 px, radio 14.
  outline,
  /// `.sbtn` — lima pequeño, 36 px, radio 8, Inter 13/600, padding 0 14.
  small,
  /// `.sbtn.o` — pequeño con borde.
  smallOutline,
  /// Botón oscuro (tinta) con texto blanco (p. ej. «Editar perfil»).
  dark,
  /// `.dbtn` — rojo suave `#FDE7E7` con texto `#C4282E`, 48 px, radio 14 (eliminar, rechazar).
  danger,
}

class PlobbyButton extends StatelessWidget {
  const PlobbyButton({super.key, required this.label, required this.onPressed, this.kind = PlobbyButtonKind.primary, this.icon, this.busy = false, this.expand, this.height});
  final String label;
  final VoidCallback? onPressed;
  final PlobbyButtonKind kind;
  final PlobbyIcons? icon;
  final bool busy;
  /// Ancho completo (por defecto: sí en primary/outline/dark, no en small).
  final bool? expand;
  /// Alto propio (p. ej. 44 en las tarjetas de «Descubrir ligas»); por defecto 48, o 36 en los pequeños.
  final double? height;

  bool get _small => kind == PlobbyButtonKind.small || kind == PlobbyButtonKind.smallOutline;
  bool get _outline => kind == PlobbyButtonKind.outline || kind == PlobbyButtonKind.smallOutline;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !busy;
    final bg = switch (kind) {
      PlobbyButtonKind.primary || PlobbyButtonKind.small => AppColors.brand,
      PlobbyButtonKind.dark => AppColors.inverse,
      PlobbyButtonKind.danger => AppColors.dangerSoft,
      _ => Colors.transparent,
    };
    final fg = switch (kind) { PlobbyButtonKind.dark => AppColors.surface, PlobbyButtonKind.danger => AppColors.danger, _ => AppColors.text };
    final radius = _small ? AppRadius.rSm : AppRadius.rMd;
    final h = height ?? (_small ? 36.0 : 48.0);
    final style = (_small ? PlobbyText.buttonSmall : PlobbyText.button).copyWith(color: fg);
    final content = busy
        ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: fg))
        : Row(mainAxisSize: MainAxisSize.min, children: [
            if (icon != null) ...[PlobbyIcon(icon!, size: _small ? 16 : 18, strokeWidth: 2.2, color: fg), const SizedBox(width: 8)],
            Flexible(child: Text(label, style: style, maxLines: 1, overflow: TextOverflow.ellipsis)),
          ]);
    final btn = Opacity(
      opacity: enabled ? 1 : .45,
      child: Material(
        color: bg,
        shape: RoundedRectangleBorder(borderRadius: radius, side: _outline ? const BorderSide(color: AppColors.borderStrong, width: 1.5) : BorderSide.none),
        child: InkWell(
          borderRadius: radius,
          onTap: enabled ? () { HapticFeedback.selectionClick(); onPressed!(); } : null,
          child: SizedBox(height: h, child: Padding(padding: EdgeInsets.symmetric(horizontal: _small ? 14 : 12), child: Center(widthFactor: 1, child: content))),
        ),
      ),
    );
    final full = expand ?? !_small;
    return Semantics(container: true, button: true, enabled: enabled, label: label, excludeSemantics: true,
        child: Pressable(enabled: enabled, child: full ? SizedBox(width: double.infinity, child: btn) : btn));
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Botón de icono · `.ibtn` (40×40, radio 14, blanco con sombra) y su variante «glass» sobre portadas
// ─────────────────────────────────────────────────────────────────────────────
class IconSquareButton extends StatelessWidget {
  const IconSquareButton({super.key, required this.icon, required this.tooltip, required this.onPressed, this.glass = false, this.size = 40});
  final PlobbyIcons icon;
  final String tooltip;
  final VoidCallback? onPressed;
  /// Sobre imagen/portada: fondo `rgba(23,28,25,.45)` e icono blanco.
  final bool glass;
  final double size;
  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: Semantics(button: true, label: tooltip, excludeSemantics: true, child: Pressable(child: Container(
          width: size, height: size,
          decoration: BoxDecoration(color: glass ? const Color(0x73171C19) : AppColors.surface, borderRadius: AppRadius.rMd, boxShadow: glass ? null : AppShadows.card),
          child: Material(type: MaterialType.transparency, child: InkWell(borderRadius: AppRadius.rMd, onTap: onPressed,
              child: Center(child: PlobbyIcon(icon, color: glass ? AppColors.surface : AppColors.text)))),
        ))),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Campo de formulario · `.fld` = `.lab` (etiqueta ENCIMA) + `.inp` (48 px, radio 14, borde 1 px #8A938D, 16 px)
// ─────────────────────────────────────────────────────────────────────────────
InputDecoration plobbyInputDecoration({String? hint, String? error, bool sunken = false, Widget? prefix, double radius = AppRadius.md, EdgeInsets? padding}) {
  OutlineInputBorder b(Color c, [double w = 1]) => OutlineInputBorder(borderRadius: BorderRadius.circular(radius), borderSide: sunken && c == AppColors.borderStrong ? BorderSide.none : BorderSide(color: c, width: w));
  return InputDecoration(
    hintText: hint, hintStyle: PlobbyText.input.copyWith(color: AppColors.textMuted),
    errorText: error == null || error.isEmpty ? null : error, errorStyle: PlobbyText.help.copyWith(color: AppColors.danger),
    filled: true, fillColor: sunken ? AppColors.surfaceSunken : AppColors.surface, isDense: true,
    contentPadding: padding ?? const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
    prefixIcon: prefix, prefixIconConstraints: const BoxConstraints(minWidth: 42, minHeight: 20),
    counterText: '', // el prototipo no muestra contador; el límite (maxLength) se sigue aplicando
    border: b(AppColors.borderStrong), enabledBorder: b(AppColors.borderStrong), disabledBorder: b(AppColors.border),
    focusedBorder: b(AppColors.focus, 2), errorBorder: b(AppColors.danger), focusedErrorBorder: b(AppColors.danger, 2),
  );
}

class LabeledField extends StatelessWidget {
  const LabeledField({super.key, required this.label, this.controller, this.initialValue, this.hint, this.error, this.onChanged, this.onSubmitted,
      this.maxLength, this.maxLines = 1, this.minLines, this.keyboardType, this.textInputAction, this.textCapitalization = TextCapitalization.none,
      this.autofocus = false, this.enabled = true, this.helper});
  final String label;
  final TextEditingController? controller;
  final String? initialValue, hint, error, helper;
  final ValueChanged<String>? onChanged, onSubmitted;
  final int? maxLength, minLines;
  final int maxLines;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final TextCapitalization textCapitalization;
  final bool autofocus, enabled;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: PlobbyText.label),
          const SizedBox(height: 8),
          TextFormField(
            controller: controller, initialValue: controller == null ? initialValue : null, onChanged: onChanged, onFieldSubmitted: onSubmitted,
            maxLength: maxLength, maxLines: maxLines, minLines: minLines ?? (maxLines > 1 ? 3 : null), keyboardType: keyboardType,
            textInputAction: textInputAction, textCapitalization: textCapitalization, autofocus: autofocus, enabled: enabled,
            style: PlobbyText.input, cursorColor: AppColors.text,
            decoration: plobbyInputDecoration(hint: hint, error: error,
                padding: maxLines > 1 ? const EdgeInsets.symmetric(horizontal: 14, vertical: 12) : null),
          ),
          if (helper != null && (error == null || error!.isEmpty)) Padding(padding: const EdgeInsets.only(top: 6), child: Text(helper!, style: PlobbyText.help)),
        ]),
      );
}

/// `.srch` — buscador: fondo hundido `#EEF1EA`, sin borde, lupa a la izquierda, 48 px, radio 14.
class SearchField extends StatelessWidget {
  const SearchField({super.key, required this.hint, this.controller, this.onChanged, this.onSubmitted, this.autofocus = false});
  final String hint;
  final TextEditingController? controller;
  final ValueChanged<String>? onChanged, onSubmitted;
  final bool autofocus;
  @override
  Widget build(BuildContext context) => TextField(
        controller: controller, onChanged: onChanged, onSubmitted: onSubmitted, autofocus: autofocus, textInputAction: TextInputAction.search,
        style: PlobbyText.input, cursorColor: AppColors.text,
        decoration: plobbyInputDecoration(hint: hint, sunken: true,
            prefix: const Padding(padding: EdgeInsets.only(left: 14, right: 10), child: PlobbyIcon(PlobbyIcons.search, size: 18, color: AppColors.textMuted))),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Filtro · `.fc` (34 px, radio 8, Inter 13/600; activo lima, inactivo blanco con borde interior 1 px)
// ─────────────────────────────────────────────────────────────────────────────
class PlobbyFilterChip extends StatelessWidget {
  const PlobbyFilterChip({super.key, required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Semantics(
        button: true, selected: selected, label: label, excludeSemantics: true,
        child: Pressable(child: Material(
          color: selected ? AppColors.brand : AppColors.surface,
          shape: RoundedRectangleBorder(borderRadius: AppRadius.rSm, side: selected ? BorderSide.none : const BorderSide(color: Color(0x1F171C19))),
          child: InkWell(borderRadius: AppRadius.rSm, onTap: () { HapticFeedback.selectionClick(); onTap(); },
              child: SizedBox(height: 34, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Center(widthFactor: 1, child: Text(label, style: PlobbyText.buttonSmall.copyWith(color: AppColors.text)))))),
        )),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Píldora · `.chip` (24 px, radio 999, Inter 12/600)
// ─────────────────────────────────────────────────────────────────────────────
enum PillTone {
  /// Verde lima suave `#EEFBC0` con texto tinta (por defecto en el CSS).
  soft,
  /// Sobre portada: `rgba(23,28,25,.55)` con texto blanco.
  glass,
  lime,
  dark,
  neutral,
}

class Pill extends StatelessWidget {
  const Pill(this.text, {super.key, this.tone = PillTone.soft, this.icon});
  final String text;
  final PillTone tone;
  final PlobbyIcons? icon;
  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (tone) {
      PillTone.soft => (AppColors.brandSoft, AppColors.text),
      PillTone.glass => (const Color(0x8C171C19), AppColors.surface),
      PillTone.lime => (AppColors.brand, AppColors.brandInk),
      PillTone.dark => (AppColors.inverse, AppColors.onInverse),
      PillTone.neutral => (AppColors.surfaceSunken, AppColors.text),
    };
    return Container(
      height: 24, padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(color: bg, borderRadius: AppRadius.rPill),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[PlobbyIcon(icon!, size: 13, strokeWidth: 2.2, color: fg), const SizedBox(width: 5)],
        Text(text, style: PlobbyText.chip.copyWith(color: fg)),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tarjeta · `.card2` (blanca, radio 14, sombra de tarjeta)
// ─────────────────────────────────────────────────────────────────────────────
class SurfaceCard extends StatelessWidget {
  const SurfaceCard({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.onTap, this.radius = AppRadius.rMd, this.margin});
  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final VoidCallback? onTap;
  final BorderRadius radius;
  @override
  Widget build(BuildContext context) {
    final card = Container(
      margin: margin,
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: radius, boxShadow: AppShadows.card),
      child: Material(type: MaterialType.transparency, borderRadius: radius, clipBehavior: Clip.antiAlias,
          child: onTap == null ? Padding(padding: padding, child: child) : InkWell(onTap: onTap, child: Padding(padding: padding, child: child))),
    );
    return onTap == null ? card : Pressable(child: card);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Opción seleccionable · `.opt` (blanca, radio 12, borde interior 1 px .12; seleccionada 2 px tinta)
// ─────────────────────────────────────────────────────────────────────────────
class OptionCard extends StatelessWidget {
  const OptionCard({super.key, required this.icon, required this.title, required this.description, required this.selected, required this.onTap});
  final PlobbyIcons icon;
  final String title, description;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Semantics(button: true, selected: selected, label: '$title. $description', excludeSemantics: true, child: Pressable(child: Material(
          color: AppColors.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: selected ? AppColors.text : const Color(0x1F171C19), width: selected ? 2 : 1)),
          child: InkWell(
            borderRadius: BorderRadius.circular(12), onTap: () { HapticFeedback.selectionClick(); onTap(); },
            child: Padding(padding: const EdgeInsets.all(14), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(width: 38, height: 38, decoration: BoxDecoration(color: selected ? AppColors.inverse : AppColors.surfaceSunken, borderRadius: BorderRadius.circular(10)),
                  child: Center(child: PlobbyIcon(icon, color: selected ? AppColors.brand : AppColors.text))),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: const TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.text)),
                const SizedBox(height: 2),
                Text(description, style: PlobbyText.help.copyWith(fontSize: 13)),
              ])),
              const SizedBox(width: 8),
              Container(width: 22, height: 22, decoration: BoxDecoration(shape: BoxShape.circle, color: selected ? AppColors.inverse : null,
                  border: selected ? null : Border.all(color: AppColors.borderStrong, width: 1.5)),
                  child: selected ? const Center(child: PlobbyIcon(PlobbyIcons.check, size: 12, strokeWidth: 3, color: AppColors.surface)) : null),
            ])),
          ),
        ))),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Barra de pasos · `.stp` (segmentos de 4 px, radio 2, separación 5; activo tinta, resto .14)
// ─────────────────────────────────────────────────────────────────────────────
class StepBar extends StatelessWidget {
  const StepBar({super.key, required this.step, required this.total});
  final int step, total;
  @override
  Widget build(BuildContext context) => Semantics(
        label: 'Paso $step de $total',
        child: Row(children: [
          for (var i = 1; i <= total; i++) ...[
            if (i > 1) const SizedBox(width: 5),
            Expanded(child: AnimatedContainer(duration: const Duration(milliseconds: 220), height: 4,
                decoration: BoxDecoration(color: i <= step ? AppColors.text : const Color(0x24171C19), borderRadius: BorderRadius.circular(2)))),
          ],
        ]),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Acción mini · `.mini` (38×38, radio 10): aprobar (tinta + check lima) / rechazar (borde rojo 1.5)
// ─────────────────────────────────────────────────────────────────────────────
class MiniAction extends StatelessWidget {
  const MiniAction({super.key, required this.approve, required this.tooltip, required this.onPressed});
  final bool approve;
  final String tooltip;
  final VoidCallback? onPressed;
  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: Semantics(button: true, label: tooltip, excludeSemantics: true, child: Pressable(child: Material(
          color: approve ? AppColors.inverse : Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10),
              side: approve ? BorderSide.none : const BorderSide(color: AppColors.danger, width: 1.5)),
          child: InkWell(borderRadius: BorderRadius.circular(10), onTap: onPressed, child: SizedBox(width: 38, height: 38,
              child: Center(child: PlobbyIcon(approve ? PlobbyIcons.check : PlobbyIcons.close, size: 18, strokeWidth: approve ? 2.6 : 2.4,
                  color: approve ? AppColors.brand : AppColors.danger)))),
        ))),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Cabecera de pantalla secundaria · `.hdr2` (padding 16 20 0; ibtn 40 · título Unbounded 18/600 · ibtn o hueco 40)
// ─────────────────────────────────────────────────────────────────────────────
class PlobbyHeaderBar extends StatelessWidget {
  const PlobbyHeaderBar({super.key, required this.title, this.onBack, this.trailing});
  final String title;
  /// Por defecto `Navigator.maybePop`.
  final VoidCallback? onBack;
  /// Botón de la derecha (p. ej. «Más opciones»); si es null se deja un hueco de 40 px para centrar el título.
  final Widget? trailing;
  static const titleStyle = TextStyle(fontFamily: AppTypography.displayFamily, fontSize: 18, height: 22 / 18, fontWeight: FontWeight.w600, letterSpacing: -0.36, color: AppColors.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(20, MediaQuery.paddingOf(context).top + 16, 20, 0),
        child: Row(children: [
          IconSquareButton(icon: PlobbyIcons.back, tooltip: 'Volver', onPressed: onBack ?? () => Navigator.of(context).maybePop()),
          const SizedBox(width: 12),
          Expanded(child: Semantics(header: true, child: Text(title, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis, style: titleStyle))),
          const SizedBox(width: 12),
          trailing ?? const SizedBox(width: 40),
        ]),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Cabecera de hoja inferior · `.hr` (título `.t2` + subtítulo opcional + botón cerrar)
// ─────────────────────────────────────────────────────────────────────────────
class SheetHeader extends StatelessWidget {
  const SheetHeader({super.key, required this.title, this.subtitle});
  final String title;
  final String? subtitle;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Semantics(header: true, child: Text(title, style: PlobbyText.t2)),
            if (subtitle != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(subtitle!, style: PlobbyText.sub)),
          ])),
          const SizedBox(width: 12),
          IconSquareButton(icon: PlobbyIcons.close, tooltip: 'Cerrar', onPressed: () => Navigator.of(context).pop()),
        ]),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Fila de lista en hojas · `.li` (54 px, borde superior .1, icono 34 radio 9 sobre tinte; `.red` en rojo)
// ─────────────────────────────────────────────────────────────────────────────
class SheetListItem extends StatelessWidget {
  const SheetListItem({super.key, required this.icon, required this.label, required this.onTap, this.danger = false});
  final PlobbyIcons icon;
  final String label;
  final VoidCallback onTap;
  final bool danger;
  @override
  Widget build(BuildContext context) {
    final fg = danger ? AppColors.danger : AppColors.text;
    return Semantics(button: true, label: label, excludeSemantics: true, child: InkWell(onTap: onTap, child: Container(
      height: 54,
      decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0x1A171C19)))),
      child: Row(children: [
        Container(width: 34, height: 34, decoration: BoxDecoration(color: danger ? AppColors.dangerSoft : AppColors.surfaceSunken, borderRadius: BorderRadius.circular(9)),
            child: Center(child: PlobbyIcon(icon, size: 18, color: fg))),
        const SizedBox(width: 14),
        Expanded(child: Text(label, style: TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 15, fontWeight: FontWeight.w600, letterSpacing: 0, color: fg))),
      ]),
    )));
  }
}

/// Hoja inferior con el aspecto del prototipo (`.sheet`: radio 22 arriba, asa 40×4, padding 20) y el contenido dado.
Future<T?> showPlobbySheet<T>(BuildContext context, WidgetBuilder builder) => showModalBottomSheet<T>(
      context: context, isScrollControlled: true, showDragHandle: false, backgroundColor: AppColors.bg,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
        child: SafeArea(child: SingleChildScrollView(padding: const EdgeInsets.fromLTRB(20, 10, 20, 20), child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Center(child: Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 14), decoration: BoxDecoration(color: const Color(0x33171C19), borderRadius: BorderRadius.circular(2)))),
          builder(ctx),
        ]))),
      ),
    );
