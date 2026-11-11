import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/plobby_theme.dart';
import '../../application/profile_providers.dart';
import '../../data/profile_repository.dart';
import '../../domain/models.dart';

/// Club base (opcional), pareja habitual (requiere aceptación) y lado de juego.
class IdentityCard extends ConsumerWidget {
  const IdentityCard({super.key, required this.profile, required this.isOwner});
  final PlayerProfile profile; final bool isOwner;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final n = ref.read(profileProvider(profile.id).notifier);
    final rows = <Widget>[];
    if (profile.club != null) {
      rows.add(_Row(icon: Icons.apartment, label: 'CLUB BASE', title: profile.club!.name, sub: profile.club!.city,
          onEdit: isOwner ? () => _pickClub(context, ref, n) : null));
    } else if (isOwner) {
      rows.add(_Add('Añadir club base (opcional)', () => _pickClub(context, ref, n)));
    }
    final pa = profile.partner;
    if (pa != null && (pa.status == PartnerStatus.accepted || isOwner)) {
      rows.add(_Row(icon: Icons.person_outline, label: 'PAREJA HABITUAL', title: pa.name,
          sub: '@${pa.username}${pa.status == PartnerStatus.pending ? ' · Pendiente de aceptación' : ''}',
          onTap: () => context.push('/player/${pa.userId}'),
          onEdit: isOwner ? () => n.removePartner() : null, editIcon: Icons.close));
    } else if (isOwner) {
      rows.add(_Add('Elegir pareja habitual', () => n.requestPartner('lucia')));
    }
    rows.add(_Row(icon: Icons.sports_tennis, label: 'LADO DE JUEGO', title: profile.side == PlaySide.right ? 'Derecha' : 'Izquierda',
        onEdit: isOwner ? () => n.setSide(profile.side == PlaySide.right ? PlaySide.left : PlaySide.right) : null));
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
      child: Column(children: [for (var i = 0; i < rows.length; i++) ...[if (i > 0) const Divider(height: 1), rows[i]]]),
    );
  }

  Future<void> _pickClub(BuildContext context, WidgetRef ref, ProfileNotifier n) async {
    final repo = ref.read(profileRepositoryProvider);
    final res = await showModalBottomSheet<ClubRef?>(context: context, isScrollControlled: true, showDragHandle: true,
        builder: (_) => _ClubSearch(repo: repo, hasClub: profile.club != null));
    if (res != null) await n.setClub(res.id == '_remove' ? null : res);
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.icon, required this.label, required this.title, this.sub, this.onTap, this.onEdit, this.editIcon = Icons.edit_outlined});
  final IconData icon; final String label, title; final String? sub; final VoidCallback? onTap, onEdit; final IconData editIcon;
  @override
  Widget build(BuildContext context) => ListTile(
      onTap: onTap, minVerticalPadding: 10,
      leading: Container(width: 34, height: 34, decoration: BoxDecoration(color: const Color(0xFFEEF1EA), borderRadius: BorderRadius.circular(9)), child: Icon(icon, size: 18, color: PlobbyColors.forest)),
      title: Text(label, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 1.2, color: PlobbyColors.mute)),
      subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: PlobbyColors.charcoal)),
        if (sub != null) Text(sub!, style: const TextStyle(fontSize: 12.5, color: PlobbyColors.mute)),
      ]),
      trailing: onEdit == null ? null : IconButton(onPressed: onEdit, icon: Icon(editIcon, size: 18), tooltip: 'Editar'));
}

class _Add extends StatelessWidget {
  const _Add(this.t, this.onTap);
  final String t; final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => ListTile(onTap: onTap, leading: const Icon(Icons.add, color: PlobbyColors.mute), title: Text(t, style: const TextStyle(color: PlobbyColors.mute, fontWeight: FontWeight.w600, fontSize: 13.5)));
}

class _ClubSearch extends StatefulWidget {
  const _ClubSearch({required this.repo, required this.hasClub});
  final ProfileRepository repo; final bool hasClub;
  @override
  State<_ClubSearch> createState() => _ClubSearchState();
}

class _ClubSearchState extends State<_ClubSearch> {
  List<ClubRef> items = [];
  @override
  void initState() { super.initState(); _q(''); }
  Future<void> _q(String s) async { final r = await widget.repo.searchClubs(s); if (mounted) setState(() => items = r); }
  @override
  Widget build(BuildContext context) => Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(onChanged: _q, decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Buscar club')),
        for (final c in items) ListTile(title: Text(c.name), subtitle: Text(c.city), onTap: () => Navigator.pop(context, c)),
        if (items.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('No encontramos ningún club con ese nombre.')),
        if (widget.hasClub) ListTile(leading: const Icon(Icons.delete_outline, color: PlobbyColors.loss), title: const Text('Quitar club'),
            onTap: () => Navigator.pop(context, const ClubRef(id: '_remove', name: '', city: ''))),
      ]));
}
