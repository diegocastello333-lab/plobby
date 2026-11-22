import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/errors/failure.dart';
import '../../../core/motion/app_motion.dart';
import '../../../core/router/app_router.dart' show authGuardEnabledProvider;
import '../../../core/share/file_export.dart';
import '../../../core/theme/design_tokens.dart';
import '../../../core/theme/plobby_text.dart';
import '../../../core/widgets/plobby_components.dart';
import '../../../core/widgets/plobby_icon.dart';
import '../../../core/widgets/state_views.dart';
import '../application/auth_providers.dart';
import '../data/auth_repository.dart';
import '../domain/legal.dart';

/// Perfil → «Ajustes y privacidad» (Seguridad Fase 8, RGPD):
///  · ver los documentos legales;
///  · activar o retirar las comunicaciones comerciales;
///  · descargar mis datos (JSON con todo lo que Plobby guarda del usuario);
///  · cerrar sesión en todos los dispositivos;
///  · eliminar mi cuenta (borra lo personal y las fotos; lo compartido con otros queda como «Jugador eliminado»).
class PrivacySettingsScreen extends ConsumerStatefulWidget {
  const PrivacySettingsScreen({super.key});
  @override
  ConsumerState<PrivacySettingsScreen> createState() => _PrivacySettingsScreenState();
}

class _PrivacySettingsScreenState extends ConsumerState<PrivacySettingsScreen> {
  bool _exporting = false, _marketingBusy = false;

  AuthRepository get _repo => ref.read(authRepositoryProvider);

  Future<void> _toggleMarketing(bool v) async {
    setState(() => _marketingBusy = true);
    try {
      await _repo.setMarketing(v);
      ref.invalidate(legalStatusProvider);
      if (mounted) showPlobbySnack(context, v ? 'Recibirás novedades de Plobby.' : 'Ya no recibirás comunicaciones comerciales.');
    } catch (e) {
      if (mounted) showPlobbySnack(context, actionErrorText(e, fallback: 'No se pudo guardar. Inténtalo de nuevo.'), error: true);
    } finally {
      if (mounted) setState(() => _marketingBusy = false);
    }
  }

  Future<void> _export() async {
    setState(() => _exporting = true);
    try {
      final json = await _repo.exportMyData();
      final now = DateTime.now();
      final d = '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
      await FileExport.saveText(json, 'plobby-mis-datos-$d.json');
    } catch (e) {
      if (mounted) {
        final code = e is AuthException ? e.code : '';
        showPlobbySnack(context, code == 'rate_limited'
            ? 'Ya has descargado tus datos hace poco. Espera unos minutos.'
            : actionErrorText(e, fallback: 'No se pudieron descargar tus datos. Inténtalo de nuevo.'), error: true);
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _signOutEverywhere() async {
    final ok = await _confirm(
      icon: PlobbyIcons.logout,
      title: '¿Cerrar sesión en todos tus dispositivos?',
      text: 'Se cerrará la sesión en este móvil y en cualquier otro dispositivo o navegador donde hayas entrado. Tu cuenta y tus datos no cambian.',
      action: 'Cerrar en todos',
    );
    if (ok != true || !mounted) return;
    final router = GoRouter.maybeOf(context);
    final guarded = ref.read(authGuardEnabledProvider);
    try {
      await _repo.signOutEverywhere();
      if (!guarded) router?.go('/welcome');
    } catch (e) {
      if (mounted) showPlobbySnack(context, actionErrorText(e, fallback: 'No se pudo cerrar la sesión. Inténtalo de nuevo.'), error: true);
    }
  }

  Future<void> _deleteAccount() async {
    final ok = await showDialog<bool>(context: context, useRootNavigator: true, barrierColor: const Color(0x80171C19),
        builder: (_) => const _DeleteAccountDialog());
    if (ok != true || !mounted) return;
    final router = GoRouter.maybeOf(context);
    final guarded = ref.read(authGuardEnabledProvider);
    showDialog<void>(context: context, useRootNavigator: true, barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator(color: AppColors.brand)));
    try {
      await _repo.deleteAccount();
      if (!guarded) router?.go('/welcome');   // con Supabase, la guardia lleva a /welcome al perder la sesión
    } catch (e) {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        showPlobbySnack(context, actionErrorText(e, fallback: 'No se pudo eliminar la cuenta. Inténtalo de nuevo.'), error: true);
      }
    }
  }

  Future<bool?> _confirm({required PlobbyIcons icon, required String title, required String text, required String action}) => showDialog<bool>(
        context: context, useRootNavigator: true, barrierColor: const Color(0x80171C19),
        builder: (c) => _PlobbyDialog(icon: icon, title: title, text: text, actions: [
          Expanded(child: PlobbyButton(label: 'Cancelar', kind: PlobbyButtonKind.outline, onPressed: () => Navigator.pop(c, false))),
          const SizedBox(width: 10),
          Expanded(child: PlobbyButton(label: action, kind: PlobbyButtonKind.danger, onPressed: () => Navigator.pop(c, true))),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(legalStatusProvider);
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Column(children: [
        const PlobbyHeaderBar(title: 'Ajustes y privacidad'),
        Expanded(child: ListView(padding: const EdgeInsets.fromLTRB(20, 20, 20, 40), children: [
          const _SectionTitle('Experiencia'),
          _Group(children: [
            Semantics(container: true, toggled: AppHaptics.enabled, label: 'Vibración', child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
              child: Row(children: [
                const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Vibración', style: PlobbyText.value),
                  SizedBox(height: 2),
                  Text('Una vibración suave al confirmar acciones y celebrar logros.', style: PlobbyText.help),
                ])),
                ExcludeSemantics(child: Switch.adaptive(
                  value: AppHaptics.enabled,
                  activeTrackColor: AppColors.inverse, activeThumbColor: AppColors.brand,
                  onChanged: (v) {
                    setState(() => AppHaptics.enabled = v);   // efecto inmediato…
                    unawaited(AppHaptics.setEnabled(v));      // …y se guarda en el dispositivo
                    if (v) AppHaptics.light();                // confirma que vuelve a vibrar
                  },
                )),
              ]),
            )),
          ]),
          const SizedBox(height: 24),
          const _SectionTitle('Documentos'),
          _Group(children: [
            for (final d in LegalDoc.values)
              _Row(icon: PlobbyIcons.info, title: d.title, onTap: () => context.push('/legal/${d.slug}')),
          ]),
          const SizedBox(height: 24),
          const _SectionTitle('Comunicaciones'),
          _Group(children: [
            Semantics(container: true, toggled: status.valueOrNull?.marketing ?? false, label: 'Comunicaciones comerciales', child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
              child: Row(children: [
                const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Comunicaciones comerciales', style: PlobbyText.value),
                  SizedBox(height: 2),
                  Text('Novedades y ofertas de Plobby. Puedes retirarlo cuando quieras.', style: PlobbyText.help),
                ])),
                ExcludeSemantics(child: Switch.adaptive(
                  value: status.valueOrNull?.marketing ?? false,
                  activeTrackColor: AppColors.inverse, activeThumbColor: AppColors.brand,
                  onChanged: status.hasValue && !_marketingBusy ? _toggleMarketing : null,
                )),
              ]),
            )),
          ]),
          const SizedBox(height: 24),
          const _SectionTitle('Tus datos'),
          _Group(children: [
            _Row(icon: PlobbyIcons.arrdn, title: 'Descargar mis datos', subtitle: 'Un archivo JSON con todo lo que Plobby guarda de ti.',
                busy: _exporting, onTap: _exporting ? null : _export),
            _Row(icon: PlobbyIcons.logout, title: 'Cerrar sesión en todos los dispositivos', onTap: _signOutEverywhere),
          ]),
          const SizedBox(height: 28),
          PlobbyButton(label: 'Eliminar mi cuenta', kind: PlobbyButtonKind.danger, icon: PlobbyIcons.trash, onPressed: _deleteAccount),
          const SizedBox(height: 10),
          const Text('Se borra tu perfil, tus fotos, mensajes, amistades, ELO y logros. En los partidos y torneos que jugaste con otras '
              'personas aparecerás como «Jugador eliminado», sin ningún dato tuyo. No se puede deshacer.', style: PlobbyText.help),
        ])),
      ]),
    );
  }
}

class _DeleteAccountDialog extends StatefulWidget {
  const _DeleteAccountDialog();
  @override
  State<_DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends State<_DeleteAccountDialog> {
  final _ctl = TextEditingController();
  @override
  void dispose() { _ctl.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    final ok = _ctl.text.trim().toUpperCase() == 'ELIMINAR';
    return _PlobbyDialog(
      icon: PlobbyIcons.trash,
      title: '¿Eliminar tu cuenta para siempre?',
      text: 'Se borrarán tu perfil, fotos, mensajes, amistades, ELO, logros y preferencias. En los partidos y torneos de otras '
          'personas aparecerás como «Jugador eliminado». Esta acción no se puede deshacer.\n\nEscribe ELIMINAR para confirmar.',
      extra: TextField(
        controller: _ctl, autofocus: true, textCapitalization: TextCapitalization.characters, onChanged: (_) => setState(() {}),
        style: PlobbyText.input,
        decoration: InputDecoration(hintText: 'ELIMINAR', filled: true, fillColor: AppColors.surface,
            border: OutlineInputBorder(borderRadius: AppRadius.rMd, borderSide: const BorderSide(color: AppColors.border))),
      ),
      actions: [
        Expanded(child: PlobbyButton(label: 'Cancelar', kind: PlobbyButtonKind.outline, onPressed: () => Navigator.pop(context, false))),
        const SizedBox(width: 10),
        Expanded(child: PlobbyButton(label: 'Eliminar', kind: PlobbyButtonKind.danger, onPressed: ok ? () => Navigator.pop(context, true) : null)),
      ],
    );
  }
}

class _PlobbyDialog extends StatelessWidget {
  const _PlobbyDialog({required this.icon, required this.title, required this.text, required this.actions, this.extra});
  final PlobbyIcons icon;
  final String title, text;
  final List<Widget> actions;
  final Widget? extra;
  @override
  Widget build(BuildContext context) => Dialog(
        backgroundColor: AppColors.bg, insetPadding: const EdgeInsets.symmetric(horizontal: 24),
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.rLg),
        child: SingleChildScrollView(padding: const EdgeInsets.fromLTRB(20, 22, 20, 20), child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(width: 44, height: 44, alignment: Alignment.center, decoration: BoxDecoration(color: AppColors.dangerSoft, borderRadius: BorderRadius.circular(12)),
              child: PlobbyIcon(icon, size: 20, color: AppColors.danger)),
          const SizedBox(height: 14),
          Semantics(header: true, child: Text(title, style: PlobbyText.t2)),
          const SizedBox(height: 6),
          Text(text, style: PlobbyText.sub),
          if (extra != null) ...[const SizedBox(height: 14), extra!],
          const SizedBox(height: 20),
          Row(children: actions),
        ])),
      );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Semantics(header: true, child: Text(text.toUpperCase(), style: PlobbyText.eb)));
}

class _Group extends StatelessWidget {
  const _Group({required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Material(
        color: AppColors.surface, borderRadius: AppRadius.rMd, clipBehavior: Clip.antiAlias,
        child: Column(children: [for (var i = 0; i < children.length; i++) ...[if (i > 0) const Divider(height: 1, color: AppColors.border), children[i]]]),
      );
}

class _Row extends StatelessWidget {
  const _Row({required this.icon, required this.title, this.subtitle, this.onTap, this.busy = false});
  final PlobbyIcons icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final bool busy;
  @override
  Widget build(BuildContext context) => Semantics(container: true, button: true, label: title, excludeSemantics: true, child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(constraints: const BoxConstraints(minHeight: 52), child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(children: [
            PlobbyIcon(icon, size: 18, color: AppColors.text),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: PlobbyText.value),
              if (subtitle != null) ...[const SizedBox(height: 2), Text(subtitle!, style: PlobbyText.help)],
            ])),
            busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.text))
                : const PlobbyIcon(PlobbyIcons.chev, size: 16, color: AppColors.textMuted),
          ]),
        )),
      ));
}
