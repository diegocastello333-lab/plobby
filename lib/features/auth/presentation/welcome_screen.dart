import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/design_tokens.dart';
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
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: AppColors.inverse,
        body: SafeArea(child: Padding(padding: const EdgeInsets.fromLTRB(24, 28, 24, 26), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const PlobbyLogo(markHeight: 42),
          const Spacer(),
          const Text('Tu comunidad de pádel, en un solo sitio.', style: TextStyle(fontFamily: 'Unbounded', fontWeight: FontWeight.w600, fontSize: 28, height: 1.12, letterSpacing: -.5, color: Colors.white)),
          const SizedBox(height: 14),
          const Text('Organiza partidos, sigue tu ELO y compite con tus amigos y tus ligas.', style: TextStyle(fontSize: 15, height: 1.5, color: Color(0xB8FFFFFF))),
          const SizedBox(height: 26),
          Semantics(button: true, label: 'Continuar con Google', child: SizedBox(width: double.infinity, height: 54, child: ElevatedButton(
              onPressed: _busy ? null : _google,
              style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: AppColors.ink900, shape: RoundedRectangleBorder(borderRadius: AppRadius.rMd)),
              child: _busy ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : Row(mainAxisAlignment: MainAxisAlignment.center, children: const [
                _GoogleG(), SizedBox(width: 12), Text('Continuar con Google', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600))])))),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: const TextStyle(color: Color(0xFFFF6B6F), fontWeight: FontWeight.w600, fontSize: 13))),
          const SizedBox(height: 14),
          const Center(child: Text('Al continuar aceptas los Términos y la Política de privacidad.', textAlign: TextAlign.center, style: TextStyle(fontSize: 11.5, color: Color(0x8CFFFFFF)))),
        ]))),
      );
}

/// «G» de Google dibujada con texto de marca (sustituye por el asset oficial de Google Sign-In en producción).
class _GoogleG extends StatelessWidget {
  const _GoogleG();
  @override
  Widget build(BuildContext context) => const Text('G', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Color(0xFF4285F4)));
}
