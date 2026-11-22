import 'dart:async';
import 'package:flutter/material.dart';
import '../motion/app_motion.dart';
import '../errors/app_errors.dart';
import '../errors/failure.dart';
import '../net/network_status.dart';
import '../motion/app_motion.dart';
import '../theme/design_tokens.dart';
import '../theme/plobby_text.dart';
import 'motion_widgets.dart';
import 'plobby_components.dart';
import 'plobby_icon.dart';

/// Estados vacío / error / carga / confirmación comunes. Mismo lenguaje que el resto de Plobby (PlobbyText,
/// PlobbyButton, iconos de línea) y las pautas de Apple: el estado vacío invita a la siguiente acción, el error dice qué
/// pasó y cómo arreglarlo sin dramatismo, y la confirmación aparece en la propia interfaz (no en una alerta).

/// Estado vacío: icono en disco, título, texto y hasta dos acciones. Entra con un fundido corto.
class EmptyStateCard extends StatelessWidget {
  const EmptyStateCard({super.key, required this.icon, required this.title, required this.text, this.primary, this.onPrimary, this.secondary, this.onSecondary});
  final IconData icon; final String title, text; final String? primary, secondary; final VoidCallback? onPrimary, onSecondary;
  @override
  Widget build(BuildContext context) => AppearOnce(child: Container(
        width: double.infinity, padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
        decoration: const BoxDecoration(color: AppColors.surface, borderRadius: AppRadius.rLg, boxShadow: AppShadows.card),
        child: Column(children: [
          // el icono entra con un pequeño rebote después de la tarjeta (una vez; quieto con «reducir movimiento»)
          TweenAnimationBuilder<double>(
            tween: Tween(begin: Motion.reduced(context) ? 1 : 0, end: 1), duration: Motion.celebration, curve: Motion.springBounce,
            builder: (_, t, c) => Transform.scale(scale: .6 + .4 * t, child: Transform.rotate(angle: -.25 * (1 - t), child: c)),
            child: Container(width: 64, height: 64, decoration: const BoxDecoration(color: AppColors.brandSoft, shape: BoxShape.circle),
                child: ExcludeSemantics(child: Icon(icon, size: 28, color: AppColors.brandText))),
          ),
          const SizedBox(height: 16),
          Semantics(header: true, child: Text(title, textAlign: TextAlign.center, style: PlobbyText.cardTitle.copyWith(fontSize: 17, height: 1.25))),
          const SizedBox(height: 6),
          Text(text, textAlign: TextAlign.center, style: PlobbyText.sub),
          if (primary != null || secondary != null) const SizedBox(height: 20),
          if (primary != null) PlobbyButton(label: primary!, onPressed: onPrimary),
          if (secondary != null) ...[const SizedBox(height: 8), PlobbyButton(label: secondary!, kind: PlobbyButtonKind.outline, onPressed: onSecondary)],
        ]),
      ));
}

/// Error con «Reintentar». Dice la causa REAL ([error] → [diagnose]): sin red, red sin Internet, servidor que no
/// responde, sesión caducada, sin permiso, error del servidor o de datos. Antes decía «Parece que no hay conexión» ante
/// CUALQUIER fallo, también cuando Supabase respondía bien y lo que fallaba era la app.
///
/// - Si la causa es de conexión, vuelve a intentarlo SOLO cuando el navegador recupera la red (una vez por error).
/// - Si es la sesión, la renueva antes de reintentar.
/// - [title]/[message] propios mandan sobre los genéricos.
class ErrorStateCard extends StatefulWidget {
  const ErrorStateCard({super.key, this.title, this.message, this.error, required this.onRetry});
  final String? title, message;
  final Object? error;
  final VoidCallback onRetry;
  @override
  State<ErrorStateCard> createState() => _ErrorStateCardState();
}

class _ErrorStateCardState extends State<ErrorStateCard> {
  FailureKind? _kind;
  StreamSubscription<void>? _restored;
  bool _autoRetried = false;

  void _classify() {
    final e = widget.error;
    _kind = null;
    _autoRetried = false;
    if (e == null) return;
    _kind = classifyError(e);
    AppErrors.record(e, StackTrace.current, origin: 'pantalla:${_kind!.name}');
    diagnose(e).then((k) { if (mounted && identical(e, widget.error) && k != _kind) setState(() => _kind = k); });
  }

  @override
  void didUpdateWidget(ErrorStateCard old) {
    super.didUpdateWidget(old);
    if (!identical(old.error, widget.error)) _classify();   // un reintento que falla por OTRA causa → texto nuevo
  }

  @override
  void initState() {
    super.initState();
    _classify();
    _restored = NetworkStatus.restored.listen((_) {
      if (!mounted || _autoRetried || !(_kind?.autoRetry ?? false)) return;
      _autoRetried = true;   // una sola vez: si vuelve a fallar, la nueva tarjeta decide
      widget.onRetry();
    });
  }

  @override
  void dispose() { _restored?.cancel(); super.dispose(); }

  Future<void> _retry() async {
    if (_kind == FailureKind.auth) await refreshSessionIfPossible();
    if (mounted) widget.onRetry();
  }

  @override
  Widget build(BuildContext context) {
    final k = _kind;
    final title = widget.title ?? k?.title ?? 'No se pudo cargar';
    final message = widget.message ?? k?.message ?? 'Vuelve a intentarlo.';
    final connectivity = k?.isConnectivity ?? false;
    return AppearOnce(child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: AppColors.surface, borderRadius: AppRadius.rLg, border: Border.all(color: const Color(0x33C4282E))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(width: 36, height: 36, decoration: const BoxDecoration(color: AppColors.dangerSoft, shape: BoxShape.circle),
                child: ExcludeSemantics(child: Icon(connectivity ? Icons.wifi_off_rounded : Icons.error_outline_rounded, size: 18, color: AppColors.danger))),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: PlobbyText.value.copyWith(color: AppColors.danger, fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(message, style: PlobbyText.sub.copyWith(fontSize: 13.5)),
            ])),
          ]),
          const SizedBox(height: 14),
          PlobbyButton(label: 'Reintentar', icon: PlobbyIcons.refresh, kind: PlobbyButtonKind.outline, height: 44, onPressed: _retry),
        ]),
      ));
  }
}

/// Bloque de carga con la altura final (evita saltos de layout) y un brillo discreto.
class LoadingBlock extends StatelessWidget {
  const LoadingBlock({super.key, this.height = 96, this.radius = AppRadius.lg});
  final double height, radius;
  @override
  Widget build(BuildContext context) => Semantics(label: 'Cargando', child: SkeletonBox(height: height, radius: BorderRadius.circular(radius)));
}

/// Confirmación o error en la propia interfaz: cápsula flotante tinta con icono, texto y háptico con significado
/// (éxito / error). Se va sola a los 3 s o al tocarla, y no tapa la barra inferior.
void showPlobbySnack(BuildContext context, String text, {bool error = false}) {
  if (error) { AppHaptics.error(); } else { AppHaptics.success(); }
  final m = ScaffoldMessenger.of(context);
  m
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating, elevation: 0, backgroundColor: Colors.transparent, padding: EdgeInsets.zero,
      duration: Duration(milliseconds: error ? 4000 : 3000),  // timing
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      content: GestureDetector(onTap: m.hideCurrentSnackBar, child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 16, 12),
        decoration: BoxDecoration(color: AppColors.inverse, borderRadius: AppRadius.rMd, boxShadow: AppShadows.pop),
        child: Row(children: [
          Container(width: 26, height: 26, decoration: BoxDecoration(color: error ? AppColors.danger : AppColors.brand, shape: BoxShape.circle),
              child: Icon(error ? Icons.priority_high_rounded : Icons.check_rounded, size: 16, color: error ? Colors.white : AppColors.brandInk)),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: PlobbyText.value.copyWith(color: AppColors.ink50, fontWeight: FontWeight.w500, fontSize: 14))),
        ]),
      )),
    ));
}
