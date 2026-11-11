import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import '../../../../core/theme/plobby_theme.dart';
import '../../domain/models.dart';

class ProfileHeader extends StatelessWidget {
  const ProfileHeader({super.key, required this.profile, required this.isOwner, this.onFriend});
  final PlayerProfile profile; final bool isOwner; final VoidCallback? onFriend;
  @override
  Widget build(BuildContext context) {
    final p = profile;
    return Container(
      color: PlobbyColors.forest,
      padding: EdgeInsets.fromLTRB(20, MediaQuery.of(context).padding.top + 8, 20, 22),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          isOwner ? const SizedBox(width: 48) : IconButton(onPressed: () => context.pop(), icon: const Icon(Icons.arrow_back, color: Colors.white)),
          Row(children: [
            IconButton(tooltip: 'Compartir perfil', onPressed: () => Share.share('https://plobby.app/@${p.username}'), icon: const Icon(Icons.ios_share, color: Colors.white)),
            if (isOwner) IconButton(tooltip: 'Ajustes', onPressed: () => context.push('/profile/edit'), icon: const Icon(Icons.tune, color: Colors.white)),
          ]),
        ]),
        Row(children: [
          Container(padding: const EdgeInsets.all(3), decoration: const BoxDecoration(shape: BoxShape.circle, color: PlobbyColors.lime),
              child: CircleAvatar(radius: 42, backgroundColor: PlobbyColors.sage, backgroundImage: p.avatarUrl != null ? NetworkImage(p.avatarUrl!) : null,
                  child: p.avatarUrl == null ? Text(p.fullName.characters.first, style: const TextStyle(fontSize: 30, color: PlobbyColors.forest, fontWeight: FontWeight.w800)) : null)),
          const SizedBox(width: 16),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Flexible(child: Text(p.fullName, style: const TextStyle(color: PlobbyColors.ivory, fontSize: 24, fontWeight: FontWeight.w800), overflow: TextOverflow.ellipsis)),
              if (p.verified) const Padding(padding: EdgeInsets.only(left: 6), child: Icon(Icons.verified, size: 20, color: PlobbyColors.lime, semanticLabel: 'Perfil verificado')),
            ]),
            Text('@${p.username}', style: const TextStyle(color: Color(0xB8F6F8F1))),
            const SizedBox(height: 4),
            Row(children: [const Icon(Icons.place_outlined, size: 14, color: Color(0xB8F6F8F1)), const SizedBox(width: 4), Text(p.location, style: const TextStyle(color: Color(0xB8F6F8F1), fontSize: 12.5))]),
          ])),
        ]),
        const SizedBox(height: 16),
        Text(p.bio, style: const TextStyle(color: Color(0xEBF6F8F1), height: 1.5)),
        const SizedBox(height: 12),
        Wrap(spacing: 6, runSpacing: 6, children: [
          _Chip('Nivel declarado', p.declaredLevel), _Chip('Posición', p.side == PlaySide.right ? 'Derecha' : 'Izquierda'), _Chip('Mano', p.dominantHand),
        ]),
        const SizedBox(height: 18),
        Row(children: [
          Expanded(flex: 10, child: _Btn(isOwner ? 'Editar perfil' : 'Añadir amigo', isOwner ? Icons.edit_outlined : Icons.person_add_alt, false,
              isOwner ? () => context.push('/profile/edit') : (onFriend ?? () => context.push('/friends')))),
          const SizedBox(width: 10),
          Expanded(flex: 13, child: _Btn('Compartir mis stats', Icons.ios_share, true, () => context.push('/profile/share'))),
        ]),
      ]),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.k, this.v);
  final String k, v;
  @override
  Widget build(BuildContext context) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: const Color(0x1FF6F8F1), borderRadius: BorderRadius.circular(7)),
      child: Text.rich(TextSpan(text: '$k ', style: const TextStyle(color: PlobbyColors.ivory, fontSize: 12, fontWeight: FontWeight.w600),
          children: [TextSpan(text: v, style: const TextStyle(color: PlobbyColors.lime, fontWeight: FontWeight.w800))])));
}

class _Btn extends StatelessWidget {
  const _Btn(this.t, this.i, this.hi, this.f);
  final String t; final IconData i; final bool hi; final VoidCallback f;
  @override
  Widget build(BuildContext context) => SizedBox(height: 44, child: FilledButton.icon(
      onPressed: f, icon: Icon(i, size: 16), label: Text(t, style: const TextStyle(fontWeight: FontWeight.w700)),
      style: FilledButton.styleFrom(backgroundColor: hi ? PlobbyColors.lime : const Color(0x24F6F8F1), foregroundColor: hi ? PlobbyColors.forest : PlobbyColors.ivory,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)))));
}
