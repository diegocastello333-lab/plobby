import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/errors/failure.dart';
import '../../../core/motion/app_motion.dart';
import '../../../core/theme/design_tokens.dart';
import '../../../core/theme/plobby_text.dart';
import '../../../core/widgets/plobby_components.dart';
import '../../../core/widgets/plobby_icon.dart';
import '../../../core/widgets/state_views.dart';
import '../application/club_providers.dart';
import '../domain/club_models.dart';

/// Resultado especial: el usuario quiere quitar su club.
const clubRemoved = ClubHit(id: '_remove', name: '');

/// Abre el buscador de clubes. Devuelve el club elegido (del catálogo o una propuesta nueva, que ya se puede usar),
/// [clubRemoved] si se pide quitarlo, o null si se cierra.
Future<ClubHit?> pickClub(BuildContext context, {String title = 'Club habitual', bool allowRemove = false, String? initialQuery}) =>
    showPlobbySheet<ClubHit>(context, (_) => _ClubSearch(title: title, allowRemove: allowRemove, initialQuery: initialQuery));

class _ClubSearch extends ConsumerStatefulWidget {
  const _ClubSearch({required this.title, required this.allowRemove, this.initialQuery});
  final String title;
  final bool allowRemove;
  final String? initialQuery;
  @override
  ConsumerState<_ClubSearch> createState() => _ClubSearchState();
}

class _ClubSearchState extends ConsumerState<_ClubSearch> {
  late final _q = TextEditingController(text: widget.initialQuery ?? '');
  Timer? _debounce;
  List<ClubHit> _hits = const [];
  bool _loading = false, _proposing = false;
  Object? _error;
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    if ((widget.initialQuery ?? '').trim().length >= 2) _run();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _q.dispose();
    super.dispose();
  }

  void _onChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 200), _run);   // timing: espera a que deje de escribir
    setState(() {});
  }

  Future<void> _run() async {
    final text = _q.text.trim();
    final seq = ++_seq;
    if (text.length < 2) { setState(() { _hits = const []; _loading = false; _error = null; }); return; }
    setState(() { _loading = true; _error = null; });
    try {
      final r = await ref.read(clubRepositoryProvider).search(text);
      if (mounted && seq == _seq) setState(() { _hits = r; _loading = false; });
    } catch (e) {
      if (mounted && seq == _seq) setState(() { _error = e; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = _q.text.trim();
    final top = _hits.isNotEmpty ? _hits.first : null;
    // «¿Te refieres a…?»: solo cuando la coincidencia es clara y lo escrito no es ya el nombre oficial
    final suggest = top != null && top.confident && normalizeClubName(text) != normalizeClubName(top.name);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .85),
        child: _proposing
            ? _ProposeForm(initialName: text, onDone: (c) => Navigator.of(context).pop(c), onCancel: () => setState(() => _proposing = false))
            : Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                SheetHeader(title: widget.title, subtitle: 'Escribe el nombre como lo conozcas: también vale abreviado o sin tildes.'),
                Padding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 8), child: TextField(
                  controller: _q, autofocus: true, onChanged: _onChanged, textInputAction: TextInputAction.search,
                  style: PlobbyText.input,
                  decoration: InputDecoration(hintText: 'Buscar club', prefixIcon: const Padding(padding: EdgeInsets.all(12),
                      child: PlobbyIcon(PlobbyIcons.search, size: 20, color: AppColors.textMuted))),
                )),
                if (suggest) Padding(padding: const EdgeInsets.fromLTRB(20, 4, 20, 8), child: Material(
                  color: AppColors.brandSoft, borderRadius: AppRadius.rMd,
                  child: InkWell(borderRadius: AppRadius.rMd, onTap: () => Navigator.of(context).pop(top),
                    child: Padding(padding: const EdgeInsets.all(12), child: Row(children: [
                      const PlobbyIcon(PlobbyIcons.check, size: 18, color: AppColors.text), const SizedBox(width: 10),
                      Expanded(child: Text.rich(TextSpan(children: [
                        const TextSpan(text: '¿Te refieres a '),
                        TextSpan(text: top.name, style: const TextStyle(fontWeight: FontWeight.w800)),
                        const TextSpan(text: '?'),
                      ]), style: PlobbyText.value)),
                    ]))),
                )),
                Flexible(child: AnimatedSwitcher(duration: Motion.of(context, Motion.fast), child: _body(text))),
                if (widget.allowRemove) Padding(padding: const EdgeInsets.fromLTRB(12, 0, 12, 8), child: TextButton(
                  onPressed: () => Navigator.of(context).pop(clubRemoved),
                  child: Text('Quitar mi club', style: PlobbyText.link.copyWith(color: AppColors.danger)))),
                const SizedBox(height: 8),
              ]),
      ),
    );
  }

  Widget _body(String text) {
    if (_error != null) {
      return Padding(key: const ValueKey('err'), padding: const EdgeInsets.all(20), child: ErrorStateCard(error: _error, onRetry: _run));
    }
    if (text.length < 2) {
      return Padding(key: const ValueKey('hint'), padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          child: Text('Escribe al menos 2 letras.', style: PlobbyText.help));
    }
    if (_loading && _hits.isEmpty) {
      return const Padding(key: ValueKey('load'), padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator(color: AppColors.text)));
    }
    return ListView(key: const ValueKey('list'), shrinkWrap: true, padding: const EdgeInsets.fromLTRB(12, 0, 12, 8), children: [
      for (final h in _hits) _ClubTile(hit: h, onTap: () => Navigator.of(context).pop(h)),
      if (_hits.isEmpty) Padding(padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
          child: Text('No encontramos «$text» en el catálogo.', style: PlobbyText.sub)),
      Padding(padding: const EdgeInsets.fromLTRB(8, 8, 8, 0), child: PlobbyButton(
          label: 'Proponer nuevo club', icon: PlobbyIcons.plus, kind: _hits.isEmpty ? PlobbyButtonKind.primary : PlobbyButtonKind.outline,
          onPressed: () => setState(() => _proposing = true))),
    ]);
  }
}

class _ClubTile extends StatelessWidget {
  const _ClubTile({required this.hit, required this.onTap});
  final ClubHit hit;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Semantics(button: true, label: '${hit.title}. ${hit.type.label}'
      '${hit.matchedAlias != null ? '. También conocido como ${hit.matchedAlias}' : ''}${hit.pending ? '. Pendiente de revisión' : ''}',
      excludeSemantics: true,
      child: InkWell(borderRadius: AppRadius.rMd, onTap: onTap, child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(width: 36, height: 36, alignment: Alignment.center,
              decoration: BoxDecoration(color: AppColors.surfaceSunken, borderRadius: BorderRadius.circular(10)),
              child: const PlobbyIcon(PlobbyIcons.building, size: 18, color: AppColors.text)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(hit.title, style: PlobbyText.value.copyWith(fontWeight: FontWeight.w700)),
            if (hit.matchedAlias != null) Padding(padding: const EdgeInsets.only(top: 2),
                child: Text('También conocido como ${hit.matchedAlias}', style: PlobbyText.help)),
            const SizedBox(height: 4),
            Wrap(spacing: 6, children: [
              ClubTypeTag(hit.type),
              if (hit.pending) const ClubTag('Pendiente de revisión'),
            ]),
          ])),
        ]),
      )));
}

class ClubTypeTag extends StatelessWidget {
  const ClubTypeTag(this.type, {super.key});
  final ClubType type;
  @override
  Widget build(BuildContext context) => ClubTag(type.label);
}

class ClubTag extends StatelessWidget {
  const ClubTag(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: AppColors.surfaceSunken, borderRadius: BorderRadius.circular(999)),
      child: Text(text, style: PlobbyText.help.copyWith(fontSize: 11.5, fontWeight: FontWeight.w700, color: AppColors.text)));
}

/// Proponer un club que no está: nombre, municipio, tipo y dirección (opcional). Antes de crearlo se comprueba si es
/// un duplicado probable y se avisa. La propuesta se puede usar al momento; la revisa un administrador.
class _ProposeForm extends ConsumerStatefulWidget {
  const _ProposeForm({required this.initialName, required this.onDone, required this.onCancel});
  final String initialName;
  final ValueChanged<ClubHit> onDone;
  final VoidCallback onCancel;
  @override
  ConsumerState<_ProposeForm> createState() => _ProposeFormState();
}

class _ProposeFormState extends ConsumerState<_ProposeForm> {
  late final _name = TextEditingController(text: widget.initialName);
  final _muni = TextEditingController(), _addr = TextEditingController();
  ClubType _type = ClubType.privateClub;
  bool _busy = false;
  List<ClubHit>? _dupes;
  String? _error;

  @override
  void dispose() { _name.dispose(); _muni.dispose(); _addr.dispose(); super.dispose(); }

  Future<void> _send({bool force = false}) async {
    if (_name.text.trim().length < 3 || _muni.text.trim().length < 2) {
      setState(() => _error = 'Escribe el nombre del club y el municipio.');
      return;
    }
    setState(() { _busy = true; _error = null; });
    try {
      final r = await ref.read(clubRepositoryProvider).propose(name: _name.text, municipality: _muni.text, type: _type, address: _addr.text, force: force);
      if (!mounted) return;
      switch (r) {
        case ProposeCreated(:final id):
          AppHaptics.success();
          widget.onDone(ClubHit(id: id, name: _name.text.trim(), municipality: _muni.text.trim(), type: _type, pending: true));
        case ProposeDuplicates(:final candidates):
          setState(() { _dupes = candidates; _busy = false; });
      }
    } catch (e) {
      if (mounted) setState(() { _busy = false; _error = actionErrorText(e, fallback: 'No se pudo enviar la propuesta. Inténtalo de nuevo.'); });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_dupes != null) {
      return ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(20, 0, 20, 16), children: [
        const SheetHeader(title: '¿Es alguno de estos?', subtitle: 'Hay clubes muy parecidos en el catálogo. Elige el tuyo para no duplicarlo.'),
        for (final h in _dupes!) _ClubTile(hit: h, onTap: () => widget.onDone(h)),
        const SizedBox(height: 12),
        PlobbyButton(label: 'No, es otro club', kind: PlobbyButtonKind.outline, busy: _busy, onPressed: () => _send(force: true)),
      ]);
    }
    return ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(20, 0, 20, 16), children: [
      const SheetHeader(title: 'Proponer nuevo club', subtitle: 'Lo revisaremos. Mientras tanto ya puedes usarlo como tu club.'),
      LabeledField(label: 'Nombre del club', controller: _name, maxLength: 120, textCapitalization: TextCapitalization.words),
      const SizedBox(height: 10),
      LabeledField(label: 'Municipio', controller: _muni, maxLength: 80, hint: 'p. ej. Alcobendas', textCapitalization: TextCapitalization.words),
      const SizedBox(height: 10),
      Text('Tipo', style: PlobbyText.label),
      const SizedBox(height: 6),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final t in ClubType.values) PlobbyFilterChip(label: t.label, selected: _type == t, onTap: () => setState(() => _type = t)),
      ]),
      const SizedBox(height: 10),
      LabeledField(label: 'Dirección (opcional)', controller: _addr, maxLength: 200),
      if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: PlobbyText.help.copyWith(color: AppColors.danger))),
      const SizedBox(height: 14),
      PlobbyButton(label: 'Enviar propuesta', busy: _busy, onPressed: _send),
      const SizedBox(height: 6),
      TextButton(onPressed: widget.onCancel, child: Text('Volver a buscar', style: PlobbyText.link)),
    ]);
  }
}
