import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/errors/failure.dart';
import '../../../core/theme/design_tokens.dart';
import '../../../core/theme/plobby_text.dart';
import '../../../core/widgets/plobby_components.dart';
import '../../../core/widgets/plobby_icon.dart';
import '../../../core/widgets/state_views.dart';
import '../application/auth_providers.dart';
import '../data/auth_repository.dart';
import '../domain/legal.dart';

/// Aceptación de los documentos legales (Seguridad Fase 8). Aparece tras entrar con Google la primera vez (antes del
/// onboarding) y cada vez que cambia la versión de un documento obligatorio.
///  · Casilla obligatoria, desmarcada: «He leído y acepto los Términos y Condiciones y la Política de Privacidad».
///  · Casilla obligatoria, desmarcada: edad mínima (14 años, España).
///  · Casilla OPCIONAL e independiente: comunicaciones comerciales.
///  · «Continuar» desactivado hasta marcar las obligatorias. El servidor vuelve a comprobarlo (`accept_legal`) y no deja
///    crear el perfil sin el consentimiento registrado.
class ConsentScreen extends ConsumerStatefulWidget {
  const ConsentScreen({super.key, this.onDone});
  final VoidCallback? onDone;
  @override
  ConsumerState<ConsentScreen> createState() => _ConsentScreenState();
}

class _ConsentScreenState extends ConsumerState<ConsentScreen> {
  bool _terms = false, _age = false, _marketing = false, _busy = false;
  final _links = <TapGestureRecognizer>[];

  bool get _canContinue => _terms && _age && !_busy;

  @override
  void dispose() {
    for (final r in _links) {
      r.dispose();
    }
    super.dispose();
  }

  TapGestureRecognizer _link(LegalDoc d) {
    final r = TapGestureRecognizer()..onTap = () => context.push('/legal/${d.slug}');
    _links.add(r);
    return r;
  }

  Future<void> _accept() async {
    setState(() => _busy = true);
    try {
      await ref.read(authRepositoryProvider).acceptLegal(marketing: _marketing);
      if (!mounted) return;
      widget.onDone?.call();
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      final code = e is AuthException ? e.code : '';
      showPlobbySnack(context, switch (code) {
        'too_young' => 'Plobby solo puede usarse a partir de 14 años.',
        _ => actionErrorText(e, fallback: 'No se pudo guardar tu aceptación. Inténtalo de nuevo.'),
      }, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(legalStatusProvider).valueOrNull;
    final update = status?.isUpdate ?? false;
    for (final r in _links) {
      r.dispose();   // los reconocedores de los enlaces se crean en cada build: se liberan los anteriores
    }
    _links.clear();
    final linkStyle = PlobbyText.desc.copyWith(color: AppColors.text, fontWeight: FontWeight.w700, decoration: TextDecoration.underline);
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.fromLTRB(20, 28, 20, 24), children: [
          Container(width: 48, height: 48, alignment: Alignment.center,
              decoration: BoxDecoration(color: AppColors.brandSoft, borderRadius: BorderRadius.circular(14)),
              child: const PlobbyIcon(PlobbyIcons.shield, size: 24, color: AppColors.text)),
          const SizedBox(height: 18),
          Semantics(header: true, child: Text(update ? 'Hemos actualizado nuestras condiciones' : 'Antes de empezar', style: PlobbyText.t1)),
          const SizedBox(height: 8),
          Text(update
              ? 'Para seguir usando Plobby, revisa y acepta la nueva versión de los documentos.'
              : 'Necesitamos tu aceptación para crear tu cuenta. Puedes leer cada documento antes de aceptarlo.',
              style: PlobbyText.sub),
          const SizedBox(height: 24),
          _CheckRow(
            value: _terms, onChanged: (v) => setState(() => _terms = v), semanticsLabel: 'Acepto los Términos y Condiciones y la Política de Privacidad',
            child: Text.rich(TextSpan(style: PlobbyText.desc.copyWith(color: AppColors.text), children: [
              const TextSpan(text: 'He leído y acepto los '),
              TextSpan(text: 'Términos y Condiciones', style: linkStyle, recognizer: _link(LegalDoc.terms)),
              const TextSpan(text: ' y la '),
              TextSpan(text: 'Política de Privacidad', style: linkStyle, recognizer: _link(LegalDoc.privacy)),
              const TextSpan(text: '. (Obligatorio)'),
            ])),
          ),
          const SizedBox(height: 10),
          _CheckRow(
            value: _age, onChanged: (v) => setState(() => _age = v), semanticsLabel: 'Confirmo que tengo 14 años o más',
            child: Text('Confirmo que tengo 14 años o más. (Obligatorio)', style: PlobbyText.desc.copyWith(color: AppColors.text)),
          ),
          const SizedBox(height: 10),
          _CheckRow(
            value: _marketing, onChanged: (v) => setState(() => _marketing = v), semanticsLabel: 'Quiero recibir comunicaciones comerciales (opcional)',
            child: Text('Quiero recibir novedades y comunicaciones comerciales de Plobby. (Opcional; puedes cambiarlo cuando quieras en Ajustes)',
                style: PlobbyText.desc),
          ),
          const SizedBox(height: 14),
          Text.rich(TextSpan(style: PlobbyText.help, children: [
            const TextSpan(text: 'También puedes consultar las '),
            TextSpan(text: 'Normas de la comunidad', style: PlobbyText.help.copyWith(decoration: TextDecoration.underline, color: AppColors.text),
                recognizer: _link(LegalDoc.community)),
            const TextSpan(text: '.'),
          ])),
          const SizedBox(height: 28),
          PlobbyButton(label: 'Continuar', busy: _busy, onPressed: _canContinue ? _accept : null),
          const SizedBox(height: 12),
          Center(child: TextButton(
            onPressed: _busy ? null : () => ref.read(authRepositoryProvider).signOut(),
            child: Text('No acepto · Cerrar sesión', style: PlobbyText.link.copyWith(color: AppColors.textMuted)),
          )),
        ]),
      ),
    );
  }
}

/// Fila con casilla accesible (objetivo táctil ≥ 48 px, estado leído por el lector de pantalla).
class _CheckRow extends StatelessWidget {
  const _CheckRow({required this.value, required this.onChanged, required this.child, required this.semanticsLabel});
  final bool value;
  final ValueChanged<bool> onChanged;
  final Widget child;
  final String semanticsLabel;
  @override
  Widget build(BuildContext context) => Semantics(
        container: true, checked: value, label: semanticsLabel,
        child: Material(
          color: AppColors.surface, borderRadius: AppRadius.rMd,
          child: InkWell(
            borderRadius: AppRadius.rMd, onTap: () => onChanged(!value),
            child: Container(
              constraints: const BoxConstraints(minHeight: 56),
              padding: const EdgeInsets.fromLTRB(8, 8, 14, 8),
              decoration: BoxDecoration(borderRadius: AppRadius.rMd, border: Border.all(color: value ? AppColors.text : AppColors.border, width: value ? 1.5 : 1)),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                ExcludeSemantics(child: Checkbox(
                  value: value, onChanged: (v) => onChanged(v ?? false),
                  activeColor: AppColors.inverse, checkColor: AppColors.brand,
                  side: const BorderSide(color: AppColors.borderStrong, width: 1.5),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
                )),
                const SizedBox(width: 4),
                Expanded(child: Padding(padding: const EdgeInsets.only(top: 12), child: child)),
              ]),
            ),
          ),
        ),
      );
}
