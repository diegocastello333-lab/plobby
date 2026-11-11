import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/theme/design_tokens.dart';
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
    if (!st.loaded) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final n = st.pending.length - 1;  // el paso 4 (bienvenida) no cuenta en el progreso
    return Scaffold(
      appBar: AppBar(
        leading: st.position > 1 ? IconButton(icon: const Icon(Icons.arrow_back), tooltip: 'Atrás', onPressed: c.back) : null,
        title: const PlobbyLogo(markHeight: 26, ink: true), centerTitle: true,
        actions: [if (st.step != 4) Padding(padding: const EdgeInsets.only(right: 16), child: Center(child: Text('${st.position} / $n', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textMuted))))],
        bottom: PreferredSize(preferredSize: const Size.fromHeight(4), child: Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: ClipRRect(borderRadius: BorderRadius.circular(2),
            child: TweenAnimationBuilder<double>(tween: Tween(end: st.position / st.pending.length), duration: const Duration(milliseconds: 350), builder: (_, v, __) => LinearProgressIndicator(value: v, minHeight: 4, backgroundColor: AppColors.surfaceSunken, color: AppColors.brand))))),
      ),
      body: AnimatedSwitcher(duration: const Duration(milliseconds: 250), child: KeyedSubtree(key: ValueKey(st.step), child: ListView(padding: const EdgeInsets.fromLTRB(20, 22, 20, 24), children: [
        switch (st.step) { 1 => _Step1(st: st), 2 => _Step2(st: st), 3 => _Step3(st: st), _ => _Step4(st: st) },
      ]))),
      bottomNavigationBar: SafeArea(child: Padding(padding: const EdgeInsets.fromLTRB(20, 8, 20, 12), child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (st.error != null) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(st.error!, style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.w600, fontSize: 12))),
        SizedBox(width: double.infinity, height: 52, child: ElevatedButton(
          onPressed: st.busy ? null : () async { final ok = await c.next(); if (ok && st.step == 4) onDone(); },
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.brand, foregroundColor: AppColors.brandInk, shape: RoundedRectangleBorder(borderRadius: AppRadius.rMd)),
          child: st.busy ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : Text(st.step == 4 ? 'Entrar en Plobby' : 'Continuar', style: const TextStyle(fontWeight: FontWeight.w600)))),
      ]))),
    );
  }
}

Widget _title(String t, String s) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(t, style: const TextStyle(fontFamily: 'Unbounded', fontWeight: FontWeight.w600, fontSize: 23, height: 1.15, letterSpacing: -.4)),
      const SizedBox(height: 8), Text(s, style: const TextStyle(fontSize: 14, height: 1.5, color: AppColors.textMuted)), const SizedBox(height: 22)]);

class _Step1 extends ConsumerWidget {
  const _Step1({required this.st});
  final OnboardingState st;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.read(onboardingProvider.notifier), d = st.data, e = st.errors;
    Widget f(String label, String k, String v, ValueChanged<String> on, {String? hint}) => Padding(padding: const EdgeInsets.only(bottom: 16), child: TextFormField(
        initialValue: v, onChanged: on, decoration: InputDecoration(labelText: label, hintText: hint, errorText: e[k], border: OutlineInputBorder(borderRadius: AppRadius.rMd))));
    final u = d.username;
    final status = !isValidUsername(u) ? null : st.checkingUsername || st.usernameAvailable == null ? 'Comprobando disponibilidad…' : st.usernameAvailable! ? '@$u está disponible' : '@$u ya está en uso. Prueba con otro.';
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _title('Cuéntanos quién eres', 'Así te encontrarán tus compañeros de pista.'),
      Row(children: [Expanded(child: f('Nombre', 'firstName', d.firstName, (v) => c.update(d.copyWith(firstName: v)))), const SizedBox(width: 12), Expanded(child: f('Apellidos', 'lastName', d.lastName, (v) => c.update(d.copyWith(lastName: v))))]),
      f('Nombre de usuario', 'username', d.username, c.usernameChanged, hint: 'p. ej. diego.c'),
      if (status != null) Padding(padding: const EdgeInsets.only(bottom: 16, top: -8), child: Text(status, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: st.usernameAvailable == true ? AppColors.success : st.usernameAvailable == false ? AppColors.danger : AppColors.textMuted))),
      f('Ciudad', 'city', d.city, (v) => c.update(d.copyWith(city: v))),
      InkWell(borderRadius: AppRadius.rMd, onTap: () async {
        final now = DateTime.now();
        final p = await showDatePicker(context: context, initialDate: d.birthDate ?? DateTime(now.year - 25), firstDate: DateTime(1920), lastDate: now);
        if (p != null) c.update(d.copyWith(birthDate: p));
      }, child: InputDecorator(decoration: InputDecoration(labelText: 'Fecha de nacimiento', helperText: 'Solo para comprobar la edad mínima (14 años). No se muestra en tu perfil.', errorText: e['birthDate'], border: OutlineInputBorder(borderRadius: AppRadius.rMd), suffixIcon: const Icon(Icons.calendar_today_outlined, size: 18)),
          child: Text(d.birthDate == null ? '' : '${d.birthDate!.day.toString().padLeft(2, '0')}/${d.birthDate!.month.toString().padLeft(2, '0')}/${d.birthDate!.year}'))),
    ]);
  }
}

class _Step2 extends ConsumerWidget {
  const _Step2({required this.st});
  final OnboardingState st;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.read(onboardingProvider.notifier), d = st.data;
    Widget chips<T>(List<T> vals, T? sel, String Function(T) lab, ValueChanged<T> on) => Wrap(spacing: 8, runSpacing: 8, children: [
          for (final v in vals) ChoiceChip(label: Text(lab(v)), selected: sel == v, onSelected: (_) => on(v), selectedColor: AppColors.brand, labelStyle: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.ink900))]);
    Widget sec(String t, Widget w) => Padding(padding: const EdgeInsets.only(bottom: 20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(t, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)), const SizedBox(height: 8), w]));
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _title('Tu forma de jugar', 'Este nivel es el que tú declaras. Tu ELO se calcula solo con partidos confirmados, nunca se asigna a mano.'),
      sec('Nivel declarado', chips(SelfLevel.values, d.selfLevel, (v) => v.label, (v) => c.update(d.copyWith(selfLevel: v)))),
      sec('Posición en pista', chips(CourtSide.values, d.side, (v) => v == CourtSide.right ? 'Derecha' : 'Revés', (v) => c.update(d.copyWith(side: v)))),
      sec('Mano dominante', chips(Hand.values, d.hand, (v) => v == Hand.right ? 'Derecha' : 'Izquierda', (v) => c.update(d.copyWith(hand: v)))),
      if (st.errors['level'] != null) Text(st.errors['level']!, style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.w600, fontSize: 12)),
      sec('Club habitual (opcional)', TextFormField(initialValue: d.habitualClub, onChanged: (v) => c.update(d.copyWith(habitualClub: v)), decoration: InputDecoration(border: OutlineInputBorder(borderRadius: AppRadius.rMd)))),
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
      Text('¡Todo listo, ${d.firstName.trim().isEmpty ? 'jugador' : d.firstName.trim()}!', textAlign: TextAlign.center, style: const TextStyle(fontFamily: 'Unbounded', fontWeight: FontWeight.w600, fontSize: 23)),
      const SizedBox(height: 8),
      const Text('Tu perfil está creado. Empieza organizando un partido o buscando tu liga.', textAlign: TextAlign.center, style: TextStyle(color: AppColors.textMuted, height: 1.5)),
    ]);
  }
}
