import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/theme/design_tokens.dart';
import '../../../core/theme/plobby_text.dart';
import '../../../core/widgets/plobby_components.dart';
import '../../../core/widgets/plobby_icon.dart';
import '../../../core/widgets/plobby_logo.dart';
import '../application/auth_providers.dart';
import '../domain/auth_models.dart';
import 'avatar_catalog.dart';

/// Onboarding multi-paso, reanudable: solo muestra los pasos pendientes y guarda cada paso en Supabase.
class OnboardingScreen extends ConsumerWidget {
  const OnboardingScreen({super.key, required this.onDone});
  final VoidCallback onDone;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final st = ref.watch(onboardingProvider), c = ref.read(onboardingProvider.notifier);
    if (!st.loaded) return const Scaffold(body: Center(child: CircularProgressIndicator(color: AppColors.text)));
    final n = st.pending.length - 1;  // el paso 4 (bienvenida) no cuenta en el progreso
    final reduce = MediaQuery.of(context).disableAnimations;
    return Scaffold(
      body: SafeArea(child: Column(children: [
        // .ob-h: atrás · logotipo · «n / total»; debajo, barra de progreso lima de 4 px
        Padding(padding: const EdgeInsets.fromLTRB(12, 10, 20, 8), child: SizedBox(height: 40, child: Row(children: [
          SizedBox(width: 56, child: st.position > 1 ? Align(alignment: Alignment.centerLeft, child:  IconSquareButton(icon: PlobbyIcons.back, tooltip: 'Atrás', onPressed: c.back)) : null),
          const Expanded(child: Center(child: PlobbyLogo(markHeight: 26, ink: true))),
          SizedBox(width: 56, child: st.step != 4 ? Text('${st.position} / $n', textAlign: TextAlign.right, style: const TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0, color: AppColors.textMuted)) : null),
        ]))),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: Semantics(label: 'Paso ${st.position} de ${st.pending.length}', excludeSemantics: true, child: Container(
          height: 4, decoration: BoxDecoration(color: AppColors.surfaceSunken, borderRadius: BorderRadius.circular(2)), alignment: Alignment.centerLeft,
          child: TweenAnimationBuilder<double>(tween: Tween(end: st.position / st.pending.length), duration: reduce ? Duration.zero : const Duration(milliseconds: 350),
              builder: (_, v, __) => FractionallySizedBox(widthFactor: v.clamp(0, 1), child: Container(decoration: BoxDecoration(color: AppColors.brand, borderRadius: BorderRadius.circular(2)))))))),
        Expanded(child: AnimatedSwitcher(duration: reduce ? Duration.zero : const Duration(milliseconds: 250), child: KeyedSubtree(key: ValueKey(st.step), child: ListView(padding: const EdgeInsets.fromLTRB(20, 24, 20, 24), children: [
          switch (st.step) { 1 => _Step1(st: st), 2 => _Step2(st: st), 3 => _Step3(st: st), _ => _Step4(st: st) },
        ])))),
        Container(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
          decoration: const BoxDecoration(color: AppColors.bg, border: Border(top: BorderSide(color: Color(0x14171C19)))),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (st.error != null) Padding(padding: const EdgeInsets.only(bottom: 8), child: Row(children: [
              const PlobbyIcon(PlobbyIcons.alert, size: 14, color: AppColors.danger), const SizedBox(width: 6),
              Expanded(child: Text(st.error!, style: const TextStyle(fontFamily: AppTypography.sansFamily, color: AppColors.danger, fontWeight: FontWeight.w600, fontSize: 12.5, letterSpacing: 0))),
            ])),
            PlobbyButton(label: st.step == 4 ? 'Entrar en Plobby' : 'Continuar', busy: st.busy, onPressed: () async { final ok = await c.next(); if (ok && st.step == 4) onDone(); }),
          ]),
        ),
      ])),
    );
  }
}

/// `.ob-t` (Unbounded 23/600) + subtítulo.
Widget _title(String t, String s) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Semantics(header: true, child: Text(t, style: const TextStyle(fontFamily: AppTypography.displayFamily, fontWeight: FontWeight.w600, fontSize: 23, height: 1.15, letterSpacing: -0.46, color: AppColors.text))),
      const SizedBox(height: 8), Text(s, style: PlobbyText.sub.copyWith(height: 1.5)), const SizedBox(height: 22)]);

/// `.ob-c`: opción en píldora de 42 px con borde 1.5; seleccionada en lima.
Widget _chips<T>(List<T> vals, T? sel, String Function(T) lab, ValueChanged<T> on) => Wrap(spacing: 8, runSpacing: 8, children: [
      for (final v in vals) Semantics(button: true, selected: sel == v, label: lab(v), excludeSemantics: true, child: Material(
        color: sel == v ? AppColors.brand : AppColors.surface,
        shape: StadiumBorder(side: BorderSide(color: sel == v ? AppColors.brand : AppColors.borderStrong, width: 1.5)),
        child: InkWell(customBorder: const StadiumBorder(), onTap: () => on(v), child: Container(height: 42, padding: const EdgeInsets.symmetric(horizontal: 16), alignment: Alignment.center,
            child: Text(lab(v), style: const TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 14, fontWeight: FontWeight.w600, letterSpacing: 0, color: AppColors.ink900)))),
      )),
    ]);

class _Step1 extends ConsumerWidget {
  const _Step1({required this.st});
  final OnboardingState st;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.read(onboardingProvider.notifier), d = st.data, e = st.errors;
    Widget f(String label, String k, String v, ValueChanged<String> on, {String? hint}) => LabeledField(label: label, initialValue: v, onChanged: on, hint: hint, error: e[k]);
    final u = d.username;
    final status = !isValidUsername(u) ? null : st.checkingUsername || st.usernameAvailable == null ? 'Comprobando disponibilidad…' : st.usernameAvailable! ? '@$u está disponible' : '@$u ya está en uso. Prueba con otro.';
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _title('Cuéntanos quién eres', 'Así te encontrarán tus compañeros de pista.'),
      Row(children: [Expanded(child: f('Nombre', 'firstName', d.firstName, (v) => c.update(d.copyWith(firstName: v)))), const SizedBox(width: 12), Expanded(child: f('Apellidos', 'lastName', d.lastName, (v) => c.update(d.copyWith(lastName: v))))]),
      f('Nombre de usuario', 'username', d.username, c.usernameChanged, hint: 'p. ej. diego.c'),
      if (status != null) Transform.translate(offset: const Offset(0, -10), child: Padding(padding: const EdgeInsets.only(bottom: 8), child: Row(children: [
        if (st.usernameAvailable == true) const Padding(padding: EdgeInsets.only(right: 6), child: PlobbyIcon(PlobbyIcons.check, size: 13, strokeWidth: 2.6, color: AppColors.success)),
        Expanded(child: Text(status, style: TextStyle(fontFamily: AppTypography.sansFamily, fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0, color: st.usernameAvailable == true ? AppColors.success : st.usernameAvailable == false ? AppColors.danger : AppColors.textMuted))),
      ]))),
      f('Ciudad', 'city', d.city, (v) => c.update(d.copyWith(city: v))),
      const Text('Fecha de nacimiento', style: PlobbyText.label),
      const SizedBox(height: 8),
      Semantics(button: true, label: 'Fecha de nacimiento', value: d.birthDate == null ? 'sin elegir' : null, child: Material(
        color: AppColors.surface, shape: RoundedRectangleBorder(borderRadius: AppRadius.rMd, side: BorderSide(color: e['birthDate'] != null ? AppColors.danger : AppColors.borderStrong)),
        child: InkWell(borderRadius: AppRadius.rMd, onTap: () async {
          final now = DateTime.now();
          final p = await showDatePicker(context: context, initialDate: d.birthDate ?? DateTime(now.year - 25), firstDate: DateTime(1920), lastDate: now);
          if (p != null) c.update(d.copyWith(birthDate: p));
        }, child: SizedBox(height: 48, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 14), child: Row(children: [
          Expanded(child: Text(d.birthDate == null ? 'dd/mm/aaaa' : '${d.birthDate!.day.toString().padLeft(2, '0')}/${d.birthDate!.month.toString().padLeft(2, '0')}/${d.birthDate!.year}',
              style: PlobbyText.input.copyWith(color: d.birthDate == null ? AppColors.textMuted : AppColors.text))),
          const PlobbyIcon(PlobbyIcons.cal, size: 18, color: AppColors.textMuted),
        ])))),
      )),
      const SizedBox(height: 6),
      Text('Solo para comprobar la edad mínima (14 años). No se muestra en tu perfil.', style: PlobbyText.help.copyWith(fontSize: 12)),
      if (e['birthDate'] != null) Padding(padding: const EdgeInsets.only(top: 6), child: Row(children: [
        const PlobbyIcon(PlobbyIcons.alert, size: 13, color: AppColors.danger), const SizedBox(width: 6),
        Expanded(child: Text(e['birthDate']!, style: PlobbyText.help.copyWith(fontSize: 12, color: AppColors.danger, fontWeight: FontWeight.w600))),
      ])),
    ]);
  }
}

class _Step2 extends ConsumerWidget {
  const _Step2({required this.st});
  final OnboardingState st;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.read(onboardingProvider.notifier), d = st.data;
    Widget chips<T>(List<T> vals, T? sel, String Function(T) lab, ValueChanged<T> on) => _chips(vals, sel, lab, on);
    Widget sec(String t, Widget w) => Padding(padding: const EdgeInsets.only(bottom: 20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(t, style: PlobbyText.label), const SizedBox(height: 8), w]));
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _title('Tu forma de jugar', 'Este nivel es el que tú declaras. Tu ELO se calcula solo con partidos confirmados, nunca se asigna a mano.'),
      sec('Nivel declarado', chips(SelfLevel.values, d.selfLevel, (v) => v.label, (v) => c.update(d.copyWith(selfLevel: v)))),
      sec('Posición en pista', chips(CourtSide.values, d.side, (v) => v == CourtSide.right ? 'Derecha' : 'Revés', (v) => c.update(d.copyWith(side: v)))),
      sec('Mano dominante', chips(Hand.values, d.hand, (v) => v == Hand.right ? 'Derecha' : 'Izquierda', (v) => c.update(d.copyWith(hand: v)))),
      if (st.errors['level'] != null) Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(st.errors['level']!, style: PlobbyText.help.copyWith(color: AppColors.danger, fontWeight: FontWeight.w600, fontSize: 12))),
      LabeledField(label: 'Club habitual (opcional)', initialValue: d.habitualClub, onChanged: (v) => c.update(d.copyWith(habitualClub: v))),
      // Pareja habitual (opcional): selector de amigos reales (friendOptionsProvider); se guarda como habitual_partner_id.
    ]);
  }
}

class _Step3 extends ConsumerWidget {
  const _Step3({required this.st});
  final OnboardingState st;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.read(onboardingProvider.notifier);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _title('Ponle cara a tu perfil', 'Sube una foto o elige un avatar. Podrás cambiarlo cuando quieras desde Editar perfil.'),
      AvatarPicker(data: st.data, busy: st.busy, error: st.errors['avatar'], onAvatar: c.pickAvatar, onPickPhoto: () async {
        final x = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 768, imageQuality: 85);
        if (x == null) return;
        final bytes = await x.readAsBytes();
        await c.pickPhoto(bytes, x.mimeType ?? 'image/jpeg');
      }),
    ]);
  }
}

class _Step4 extends StatelessWidget {
  const _Step4({required this.st});
  final OnboardingState st;
  @override
  Widget build(BuildContext context) {
    final d = st.data;
    return Column(children: [
      const SizedBox(height: 24),
      Container(padding: const EdgeInsets.all(6), decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.brand),
          child: d.avatarUrl != null && d.avatarUrl!.isNotEmpty ? ClipOval(child: Image.network(d.avatarUrl!, width: 112, height: 112, fit: BoxFit.cover)) : PlobbyAvatar(id: d.avatarId ?? 'a1', size: 112)),
      const SizedBox(height: 22),
      Text('¡Todo listo, ${d.firstName.trim().isEmpty ? 'jugador' : d.firstName.trim()}!', textAlign: TextAlign.center, style: const TextStyle(fontFamily: AppTypography.displayFamily, fontWeight: FontWeight.w600, fontSize: 23, letterSpacing: -0.46, color: AppColors.text)),
      const SizedBox(height: 8),
      Text('Tu perfil está creado. Empieza organizando un partido o buscando tu liga.', textAlign: TextAlign.center, style: PlobbyText.sub.copyWith(height: 1.5)),
    ]);
  }
}
