import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/theme/design_tokens.dart';
import '../../../core/theme/plobby_text.dart';
import '../../../core/widgets/motion_widgets.dart';
import '../../../core/widgets/plobby_components.dart';
import '../../../core/widgets/plobby_icon.dart';
import '../../../core/widgets/silhouette_avatar.dart';
import '../../../core/widgets/state_views.dart';
import '../../auth/application/auth_providers.dart';
import '../../auth/data/auth_repository.dart';
import '../../auth/domain/auth_models.dart';
import '../application/profile_providers.dart';
import '../domain/models.dart';

/// Validación pura de «Editar perfil» (mismas reglas que el servidor en save_onboarding_step). Campo → mensaje.
Map<String, String> validateProfileEdit({required String first, required String last, required String username, required String bio}) => {
      if (first.trim().length < 2) 'first': 'Escribe tu nombre.',
      if (last.trim().length < 2) 'last': 'Escribe tus apellidos.',
      if (!isValidUsername(username.trim().toLowerCase())) 'username': 'Usa 3–24 letras minúsculas, números, punto o guion bajo.',
      if (bio.trim().length > 160) 'bio': 'La bio no puede superar 160 caracteres.',
    };

/// «Editar perfil» — `scEdit` del prototipo HTML. Antes el botón llevaba a una ruta inexistente (/profile/edit).
///
/// Guarda con métodos que ya existían y que valida el servidor: `AuthRepository.saveStep(1)` (nombre, apellidos, usuario,
/// ciudad), `saveStep(2)` (nivel, posición, mano, club y pareja, que se reenvían sin cambios), `saveStep(3)` (foto) y
/// `ProfileRepository.setBio`. Diferencia deliberada con el HTML: «Nombre» y «Apellidos» van separados porque el servidor
/// exige ambos.
class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({super.key});
  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  final _first = TextEditingController(), _last = TextEditingController(), _user = TextEditingController(), _city = TextEditingController(), _bio = TextEditingController();
  OnboardingData? _data;
  PlayerProfile? _profile;
  SelfLevel _level = SelfLevel.intermediate;
  Hand _hand = Hand.right;
  Map<String, String> _errors = const {};
  bool _busy = false, _uploading = false;
  String? _loadError, _avatarUrl;

  @override
  void initState() { super.initState(); _load(); }

  @override
  void dispose() { for (final c in [_first, _last, _user, _city, _bio]) { c.dispose(); } super.dispose(); }

  Future<void> _load() async {
    setState(() => _loadError = null);
    try {
      final d = await ref.read(authRepositoryProvider).loadOnboarding();
      final p = (await ref.read(profileProvider('me').future)).profile;
      if (!mounted) return;
      // Datos del servidor; si faltan (modo demo), se rellenan a partir del perfil visible.
      final parts = p.fullName.trim().split(RegExp(r'\s+'));
      _first.text = d.firstName.isNotEmpty ? d.firstName : parts.first;
      _last.text = d.lastName.isNotEmpty ? d.lastName : parts.skip(1).join(' ');
      _user.text = d.username.isNotEmpty ? d.username : p.username;
      _city.text = d.city.isNotEmpty ? d.city : p.location;
      _bio.text = p.bio;
      _level = d.selfLevel ?? SelfLevel.values.firstWhere((l) => l.label == p.declaredLevel, orElse: () => SelfLevel.intermediate);
      _hand = d.hand ?? (p.dominantHand == 'Izquierda' ? Hand.left : Hand.right);
      _avatarUrl = d.avatarUrl ?? p.avatarUrl;
      setState(() { _data = d; _profile = p; });
    } catch (_) {
      if (mounted) setState(() => _loadError = 'No se pudo cargar tu perfil.');
    }
  }

  Future<void> _pickPhoto() async {
    final x = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 768, imageQuality: 85);
    if (x == null || !mounted) return;
    final mime = x.mimeType ?? (x.name.toLowerCase().endsWith('.png') ? 'image/png' : 'image/jpeg');
    setState(() => _uploading = true);
    try {
      final repo = ref.read(authRepositoryProvider);
      final url = await repo.uploadAvatar(await x.readAsBytes(), mime);
      await repo.saveStep(3, (_data ?? const OnboardingData()).copyWith(avatarUrl: url, clearAvatarId: true));
      ref.invalidate(profileProvider('me'));
      if (mounted) setState(() { _avatarUrl = url; _uploading = false; });
    } catch (_) {
      if (mounted) { setState(() => _uploading = false); showPlobbySnack(context, 'No se pudo subir la foto. Inténtalo de nuevo.', error: true); }
    }
  }

  Future<void> _save() async {
    final e = validateProfileEdit(first: _first.text, last: _last.text, username: _user.text, bio: _bio.text);
    setState(() => _errors = e);
    if (e.isNotEmpty || _data == null || _profile == null) return;
    setState(() => _busy = true);
    final p = _profile!;
    final d = _data!.copyWith(
      firstName: _first.text.trim(), lastName: _last.text.trim(), username: _user.text.trim().toLowerCase(), city: _city.text.trim(),
      selfLevel: _level, hand: _hand, side: _data!.side ?? (p.side == PlaySide.left ? CourtSide.left : CourtSide.right),
    );
    try {
      final auth = ref.read(authRepositoryProvider);
      await auth.saveStep(1, d);
      await auth.saveStep(2, d);
      await ref.read(profileRepositoryProvider).setBio(_bio.text.trim());
      ref.invalidate(profileProvider('me'));
      if (!mounted) return;
      showPlobbySnack(context, 'Perfil actualizado');
      context.pop();
    } on AuthException catch (x) {
      if (!mounted) return;
      setState(() { _busy = false; if (x.code == 'username_taken') _errors = {'username': 'Ese usuario ya está en uso.'}; });
      if (x.code != 'username_taken') showPlobbySnack(context, 'No se pudo guardar. Revisa tu conexión y reinténtalo.', error: true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      showPlobbySnack(context, 'No se pudo guardar. Revisa tu conexión y reinténtalo.', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _profile;
    return Scaffold(
      body: SafeArea(child: Column(children: [
        // .crh: cerrar · «EDITAR PERFIL» · hueco simétrico
        Padding(padding: const EdgeInsets.fromLTRB(20, 14, 20, 0), child: Row(children: [
          IconSquareButton(icon: PlobbyIcons.close, tooltip: 'Cerrar', onPressed: () => context.pop()),
          const Expanded(child: Center(child: Text('EDITAR PERFIL', style: PlobbyText.eb))),
          const SizedBox(width: 40),
        ])),
        Expanded(child: _loadError != null
            ? Padding(padding: const EdgeInsets.all(20), child: ErrorStateCard(message: _loadError!, onRetry: _load))
            : p == null
                ? const Center(child: CircularProgressIndicator(color: AppColors.text))
                : ListView(padding: const EdgeInsets.fromLTRB(20, 16, 20, 24), children: [
                    Center(child: SizedBox(width: 98, height: 96, child: Stack(clipBehavior: Clip.none, children: [
                      ClipOval(child: SizedBox(width: 92, height: 92, child: _avatarUrl != null && _avatarUrl!.isNotEmpty
                          ? Image.network(_avatarUrl!, fit: BoxFit.cover, cacheWidth: 276, errorBuilder: (_, __, ___) => SilhouetteAvatar(seed: p.id, size: 92))
                          : SilhouetteAvatar(seed: p.id, size: 92))),
                      if (_uploading) const Positioned.fill(right: 6, bottom: 4, child: Center(child: CircularProgressIndicator(color: AppColors.lime300))),
                      Positioned(right: 0, bottom: 0, child: IconSquareButton(icon: PlobbyIcons.edit, tooltip: 'Cambiar foto', size: 34, onPressed: _uploading ? null : _pickPhoto)),
                    ]))),
                    const SizedBox(height: 18),
                    LabeledField(label: 'Nombre', controller: _first, maxLength: 40, error: _errors['first'], textCapitalization: TextCapitalization.words),
                    LabeledField(label: 'Apellidos', controller: _last, maxLength: 60, error: _errors['last'], textCapitalization: TextCapitalization.words),
                    LabeledField(label: 'Nombre de usuario', controller: _user, maxLength: 24, error: _errors['username']),
                    LabeledField(label: 'Ubicación', controller: _city, maxLength: 60),
                    ValueListenableBuilder(valueListenable: _bio, builder: (_, v, __) => LabeledField(label: 'Bio', controller: _bio, maxLength: 160, maxLines: 4,
                        error: _errors['bio'], helper: '${v.text.length}/160')),
                    const Text('Nivel declarado', style: PlobbyText.label),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<SelfLevel>(
                      value: _level, isExpanded: true, style: PlobbyText.input, decoration: plobbyInputDecoration(),
                      icon: const PlobbyIcon(PlobbyIcons.down, size: 18, color: AppColors.textMuted),
                      items: [for (final l in SelfLevel.values) DropdownMenuItem(value: l, child: Text(l.label))],
                      onChanged: (v) => setState(() => _level = v ?? _level),
                    ),
                    const SizedBox(height: 18),
                    const Text('Mano preferida', style: PlobbyText.label),
                    const SizedBox(height: 8),
                    SlidingTabs(labels: const ['Derecha', 'Izquierda'], index: _hand == Hand.right ? 0 : 1, onChanged: (i) => setState(() => _hand = i == 0 ? Hand.right : Hand.left)),
                  ])),
        // .crf: Cancelar · Guardar
        Container(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
          decoration: const BoxDecoration(color: AppColors.bg, border: Border(top: BorderSide(color: AppColors.border))),
          child: Row(children: [
            Expanded(flex: 10, child: PlobbyButton(label: 'Cancelar', kind: PlobbyButtonKind.outline, onPressed: _busy ? null : () => context.pop())),
            const SizedBox(width: 10),
            Expanded(flex: 23, child: PlobbyButton(label: 'Guardar', busy: _busy, onPressed: p == null ? null : _save)),
          ]),
        ),
      ])),
    );
  }
}
