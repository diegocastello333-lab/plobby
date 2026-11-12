import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/design_tokens.dart';
import '../../../core/widgets/plobby_icon.dart';
import '../../../core/widgets/plobby_logo.dart';
import '../application/auth_providers.dart';

/// Bienvenida: logo, frase de comunidad y «Continuar con Google» (OAuth REAL de Supabase en producción).
class WelcomeScreen extends ConsumerStatefulWidget {
  const WelcomeScreen({super.key});
  @override
  ConsumerState<WelcomeScreen> createState() => _S();
}
class _S extends ConsumerState<WelcomeScreen> {
  bool _busy = false; String? _error;
  Future<void> _google() async {
    setState(() { _busy = true; _error = null; });
    try { await ref.read(authRepositoryProvider).signInWithGoogle(); }   // abre el navegador/Google; la sesión llega por authStateProvider
    catch (_) { if (mounted) setState(() => _error = 'No se pudo completar el acceso con Google. Inténtalo de nuevo.'); }
    finally { if (mounted) setState(() => _busy = false); }
  }
  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.of(context).disableAnimations;
    return Scaffold(
      backgroundColor: AppColors.inverse,
      body: Stack(children: [
        // .aw-bg: aros lima decorativos y disco lima que flota (quieto con «reducir movimiento»)
        Positioned(right: -140, top: 90 + MediaQuery.paddingOf(context).top, child: IgnorePointer(child: _ring(360, const Color(0x2ED2F548)))),
        Positioned(right: -60, top: 160 + MediaQuery.paddingOf(context).top, child: IgnorePointer(child: _ring(220, const Color(0x47D2F548)))),
        Positioned(right: 30, top: 225 + MediaQuery.paddingOf(context).top, child: IgnorePointer(child: _Float(enabled: !reduce,
            child: Container(width: 90, height: 90, decoration: const BoxDecoration(color: Color(0xF2D2F548), shape: BoxShape.circle))))),
        SafeArea(child: Padding(padding: const EdgeInsets.fromLTRB(24, 18, 24, 22), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const PlobbyLogo(markHeight: 42),
          const Spacer(),
          Semantics(header: true, child: const Text('Tu comunidad de pádel, en un solo sitio.',
              style: TextStyle(fontFamily: AppTypography.displayFamily, fontWeight: FontWeight.w600, fontSize: 28, height: 1.12, letterSpacing: -0.56, color: Colors.white))),
          const SizedBox(height: 14),
          const Text('Organiza partidos, sigue tu ELO y compite con tus amigos y tus ligas.',
              style: TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 15, height: 1.5, letterSpacing: 0, color: Color(0xB8FFFFFF))),
          const SizedBox(height: 26),
          // .gbtn: blanco 54 px, radio 14, Inter 15/600 con la «G»
          Semantics(button: true, enabled: !_busy, label: 'Continuar con Google', excludeSemantics: true, child: Material(
            color: _busy ? const Color(0x24FFFFFF) : Colors.white, borderRadius: AppRadius.rMd,
            child: InkWell(borderRadius: AppRadius.rMd, onTap: _busy ? null : _google, child: SizedBox(height: 54, width: double.infinity, child: Center(child: _busy
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Row(mainAxisSize: MainAxisSize.min, children: [
                    _GoogleG(), SizedBox(width: 12),
                    Flexible(child: Text('Continuar con Google', maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 15, fontWeight: FontWeight.w600, letterSpacing: 0, color: AppColors.ink900))),
                  ])))),
          )),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Padding(padding: EdgeInsets.only(top: 1, right: 6), child: PlobbyIcon(PlobbyIcons.alert, size: 14, color: Color(0xFFFF6B6F))),
            Expanded(child: Text(_error!, style: const TextStyle(fontFamily: AppTypography.sansFamily, color: Color(0xFFFF6B6F), fontWeight: FontWeight.w600, fontSize: 13, letterSpacing: 0))),
          ])),
          const SizedBox(height: 16),
          const Center(child: Text('Al continuar aceptas los Términos y la Política de privacidad.', textAlign: TextAlign.center,
              style: TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 11.5, letterSpacing: 0, color: Color(0x8CFFFFFF)))),
        ]))),
      ]),
    );
  }

  static Widget _ring(double d, Color c) => Container(width: d, height: d, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: c, width: 1.5)));
}

/// `@keyframes awf`: el disco sube y baja suavemente (5 s).
class _Float extends StatefulWidget {
  const _Float({required this.child, required this.enabled});
  final Widget child; final bool enabled;
  @override
  State<_Float> createState() => _FloatState();
}

class _FloatState extends State<_Float> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 5000));
  @override
  void initState() { super.initState(); if (widget.enabled) _c.repeat(reverse: true); }
  @override
  void dispose() { _c.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => AnimatedBuilder(animation: _c, builder: (_, child) =>
      Transform.translate(offset: Offset(0, -8 * Curves.easeInOut.transform(_c.value)), child: child), child: widget.child);
}

/// «G» de Google dibujada con texto de marca (sustituye por el asset oficial de Google Sign-In en producción).
class _GoogleG extends StatelessWidget {
  const _GoogleG();
  @override
  Widget build(BuildContext context) => const Text('G', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Color(0xFF4285F4)));
}
