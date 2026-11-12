import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/router/app_router.dart' show authGuardEnabledProvider;
import '../../../../core/theme/design_tokens.dart';
import '../../../../core/theme/plobby_text.dart';
import '../../../../core/widgets/plobby_components.dart';
import '../../../../core/widgets/plobby_icon.dart';
import '../../../../core/widgets/state_views.dart';
import '../../../auth/application/auth_providers.dart';

/// «Cerrar sesión» al final del perfil propio: separado del resto, discreto (texto rojo con borde suave) y con
/// confirmación. Solo cierra la sesión del dispositivo (`supabase.auth.signOut()` vía [AuthRepository.signOut]); la cuenta
/// y sus datos siguen en Supabase y se recuperan al volver a entrar.
class LogoutButton extends ConsumerStatefulWidget {
  const LogoutButton({super.key});
  @override
  ConsumerState<LogoutButton> createState() => _LogoutButtonState();
}

class _LogoutButtonState extends ConsumerState<LogoutButton> {
  bool _busy = false;

  Future<void> _logout() async {
    final ok = await showLogoutDialog(context);
    if (ok != true || !mounted) return;
    // El router se toma antes del `await`: al cerrar sesión con Supabase, `SupabaseSessionScope` recrea todo el
    // ProviderScope (se descarta el estado de Riverpod de la sesión) y esta pantalla deja de existir.
    final router = GoRouter.of(context);
    final guarded = ref.read(authGuardEnabledProvider);
    setState(() => _busy = true);
    try {
      await ref.read(authRepositoryProvider).signOut();
    } catch (_) {
      if (mounted) {
        setState(() => _busy = false);
        showPlobbySnack(context, 'No se pudo cerrar sesión. Revisa tu conexión e inténtalo de nuevo.', error: true);
      }
      return;
    }
    // Con Supabase la guardia del router ya lleva a /welcome al perder la sesión. `go` sustituye toda la pila, así que
    // el botón «atrás» no puede volver a pantallas privadas. En modo demo (sin guardia) se navega aquí.
    if (!guarded && mounted) router.go('/welcome');
  }

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.fromLTRB(20, 28, 20, 0),
        padding: const EdgeInsets.only(top: 20),
        decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0x1A171C19)))),
        child: Semantics(container: true, button: true, enabled: !_busy, label: 'Cerrar sesión', excludeSemantics: true, child: Material(
          color: AppColors.surface,
          shape: RoundedRectangleBorder(borderRadius: AppRadius.rMd, side: BorderSide(color: AppColors.danger.withValues(alpha: .28))),
          child: InkWell(
            borderRadius: AppRadius.rMd, onTap: _busy ? null : _logout,
            child: SizedBox(height: 48, child: Center(child: _busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.danger))
                : const Row(mainAxisSize: MainAxisSize.min, children: [
                    PlobbyIcon(PlobbyIcons.logout, size: 18, color: AppColors.danger), SizedBox(width: 8),
                    Text('Cerrar sesión', style: TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 14, fontWeight: FontWeight.w600, letterSpacing: 0, color: AppColors.danger)),
                  ]))),
          ),
        )),
      );
}

/// Diálogo de confirmación: «¿Estás seguro de que quieres cerrar sesión?» con «Cancelar» y «Cerrar sesión».
Future<bool?> showLogoutDialog(BuildContext context) => showDialog<bool>(
      context: context, useRootNavigator: true, barrierColor: const Color(0x80171C19),
      builder: (c) => Dialog(
        backgroundColor: AppColors.bg, insetPadding: const EdgeInsets.symmetric(horizontal: 24),
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.rLg),
        child: Padding(padding: const EdgeInsets.fromLTRB(20, 22, 20, 20), child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(width: 44, height: 44, alignment: Alignment.center, decoration: BoxDecoration(color: AppColors.dangerSoft, borderRadius: BorderRadius.circular(12)),
              child: const PlobbyIcon(PlobbyIcons.logout, size: 20, color: AppColors.danger)),
          const SizedBox(height: 14),
          Semantics(header: true, child: const Text('¿Estás seguro de que quieres cerrar sesión?', style: PlobbyText.t2)),
          const SizedBox(height: 6),
          const Text('Tu cuenta, tus amigos y tus partidos se mantienen. Podrás volver a entrar cuando quieras.', style: PlobbyText.sub),
          const SizedBox(height: 20),
          Row(children: [
            Expanded(child: PlobbyButton(label: 'Cancelar', kind: PlobbyButtonKind.outline, onPressed: () => Navigator.pop(c, false))),
            const SizedBox(width: 10),
            Expanded(child: PlobbyButton(label: 'Cerrar sesión', kind: PlobbyButtonKind.danger, onPressed: () => Navigator.pop(c, true))),
          ]),
        ])),
      ),
    );
