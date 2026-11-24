import 'package:flutter/material.dart';
import '../../../../core/widgets/plobby_icon.dart';
import '../../../../core/widgets/silhouette_avatar.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/plobby_theme.dart';
import '../../application/profile_providers.dart';
import '../../domain/models.dart';
import '../../../../core/widgets/state_views.dart';
import '../../../../core/errors/failure.dart';
import '../../../clubs/application/club_providers.dart' show isCatalogClubId;
import '../../../clubs/presentation/club_search_sheet.dart' show pickClub, clubRemoved;
import '../../../matches/domain/match_models.dart' show PlayerOption;
import '../../../social/presentation/friends_screen.dart' show FriendPick, pickFriends;
import '../../../../core/widgets/net_image.dart';

/// Club base (opcional), pareja habitual (requiere aceptación) y lado de juego.
class IdentityCard extends ConsumerWidget {
  const IdentityCard({super.key, required this.profile, required this.isOwner});
  final PlayerProfile profile; final bool isOwner;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Perfil propio = familia 'me' (la que pinta la pantalla). Con Supabase profile.id es el UUID: usar ese id
    // refrescaba otra instancia y la pareja/club/lado guardados no aparecían hasta recargar.
    final n = ref.read(profileProvider(isOwner ? 'me' : profile.id).notifier);
    final rows = <Widget>[];
    if (profile.club != null) {
      final cid = profile.club!.id;
      rows.add(_Row(icon: PlobbyIcons.building, label: 'CLUB HABITUAL', title: profile.club!.name,
          sub: isCatalogClubId(cid) ? [if (profile.club!.city.isNotEmpty) profile.club!.city, 'Ver club'].join(' · ') : profile.club!.city,
          onTap: isCatalogClubId(cid) ? () => context.push('/club/$cid') : null,   // página del club: jugadores, ranking y ligas
          onEdit: isOwner ? () => _pickClub(context, ref, n) : null));
    } else if (isOwner) {
      rows.add(_Add('Añadir club habitual (opcional)', () => _pickClub(context, ref, n)));
    }
    final pa = profile.partner;
    // Cada jugador elige su pareja de forma independiente: se muestra siempre (antes, en perfiles ajenos solo si era mutua,
    // y parecía que la elección «no se había guardado»). Si es mutua se indica.
    if (pa != null) {
      // Propietario: tocar la fila cambia la pareja (selector de Amigos) y la «×» la quita. Resto: abre su perfil.
      rows.add(_Row(icon: PlobbyIcons.user, avatar: SilhouetteAvatar(seed: pa.userId, size: 34), avatarUrl: pa.avatarUrl, label: 'PAREJA HABITUAL', title: pa.name,
          sub: '@${pa.username}${pa.status == PartnerStatus.accepted ? ' · Pareja mutua' : ''}${isOwner ? ' · Toca para cambiarla' : ''}',
          onTap: isOwner ? () => _pickPartner(context, n, pa) : () => context.push('/player/${pa.userId}'),
          onEdit: isOwner ? () => _removePartner(context, n) : null, editIcon: PlobbyIcons.close));
    } else if (isOwner) {
      // Antes llamaba a requestPartner('lucia') (id fijo de prueba): con Supabase siempre fallaba (no es un UUID ni un amigo).
      rows.add(_Add('Añadir pareja habitual', () => _pickPartner(context, n, null)));
    }
    rows.add(_Row(icon: PlobbyIcons.swords, label: 'LADO DE JUEGO', title: profile.limited ? '—' : (profile.side == PlaySide.right ? 'Derecha' : 'Izquierda'),
        onEdit: isOwner ? () => n.setSide(profile.side == PlaySide.right ? PlaySide.left : PlaySide.right) : null));
    // Material (no DecoratedBox) como fondo blanco: los ListTile pintan su efecto de pulsación en el Material más
    // cercano y un DecoratedBox con color lo ocultaba. Mismo aspecto: blanco, radio 14.
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Material(
        color: Colors.white, borderRadius: BorderRadius.circular(14), clipBehavior: Clip.antiAlias,
        child: Column(children: [for (var i = 0; i < rows.length; i++) ...[if (i > 0) const Divider(height: 1), rows[i]]]),
      ),
    );
  }

  Future<void> _pickClub(BuildContext context, WidgetRef ref, ProfileNotifier n) async {
    final res = await pickClub(context, allowRemove: profile.club != null);
    if (res == null) return;
    try {
      await n.setClub(res == clubRemoved ? null : ClubRef(id: res.id, name: res.name, city: res.municipality ?? ''));
    } catch (e) {
      if (context.mounted) showPlobbySnack(context, actionErrorText(e, fallback: 'No se pudo guardar el club. Inténtalo de nuevo.'), error: true);
    }
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.icon, required this.label, required this.title, this.sub, this.onTap, this.onEdit, this.editIcon = PlobbyIcons.edit, this.avatar, this.avatarUrl});
  final PlobbyIcons icon; final String label, title; final String? sub; final VoidCallback? onTap, onEdit; final PlobbyIcons editIcon;
  /// Pareja habitual: foto (o avatar por defecto) de 34 px en lugar del icono, como en el prototipo.
  final Widget? avatar; final String? avatarUrl;
  @override
  Widget build(BuildContext context) => ListTile(
      onTap: onTap, minVerticalPadding: 10,
      leading: avatar != null
          ? ClipOval(child: SizedBox(width: 34, height: 34, child: avatarUrl != null && avatarUrl!.isNotEmpty
              ? NetImage(avatarUrl!, fit: BoxFit.cover, cacheWidth: 102, errorBuilder: (_, __, ___) => avatar!) : avatar))
          : Container(width: 34, height: 34, decoration: BoxDecoration(color: AppColors.surfaceSunken, borderRadius: BorderRadius.circular(9)), child: Center(child: PlobbyIcon(icon, size: 18, color: AppColors.ink900))),
      title: Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.2, color: PlobbyColors.mute)),
      subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: PlobbyColors.charcoal)),
        if (sub != null) Text(sub!, style: const TextStyle(fontSize: 12.5, color: PlobbyColors.mute)),
      ]),
      trailing: onEdit == null ? null : IconButton(onPressed: onEdit, icon: PlobbyIcon(editIcon, size: 16, color: AppColors.textMuted), tooltip: 'Editar'));
}

class _Add extends StatelessWidget {
  const _Add(this.t, this.onTap);
  final String t; final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => ListTile(onTap: onTap, leading: const PlobbyIcon(PlobbyIcons.plus, color: AppColors.textMuted), title: Text(t, style: const TextStyle(color: PlobbyColors.mute, fontWeight: FontWeight.w600, fontSize: 13.5)));
}

/// Elige la pareja habitual SOLO entre los amigos (pantalla de Amigos en modo elección única) y la guarda en Supabase
/// (RPC `set_habitual_partner`, que también exige que sea amigo).
Future<void> _pickPartner(BuildContext context, ProfileNotifier n, PartnerLink? current) async {
  final r = await pickFriends(context, FriendPick(title: 'Pareja habitual', confirmLabel: 'Elegir pareja',
      selected: [if (current != null) PlayerOption(current.userId, current.name)]));
  if (r == null || r.isEmpty || !context.mounted) return;
  if (r.first.id == current?.userId) return;
  try {
    await n.requestPartner(r.first.id);
    if (context.mounted) showPlobbySnack(context, '${r.first.name} es tu pareja habitual');
  } catch (_) {
    if (context.mounted) showPlobbySnack(context, 'No se pudo guardar la pareja habitual. Inténtalo de nuevo.', error: true);
  }
}

Future<void> _removePartner(BuildContext context, ProfileNotifier n) async {
  try {
    await n.removePartner();
    if (context.mounted) showPlobbySnack(context, 'Pareja habitual quitada');
  } catch (_) {
    if (context.mounted) showPlobbySnack(context, 'No se pudo quitar la pareja habitual. Inténtalo de nuevo.', error: true);
  }
}
