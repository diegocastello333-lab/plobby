import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/design_tokens.dart';
import '../../matches/application/lifecycle_providers.dart';
import '../../matches/domain/match_lifecycle.dart';
import '../../matches/domain/match_models.dart';
import '../../match_recap/domain/recap_data.dart';
import '../application/messaging_providers.dart';

/// Ventana «Compartir resultado»: historial de partidos FINALIZADOS Y CONFIRMADOS del usuario, con buscador.
/// Devuelve el id del partido elegido. Solo se listan los que `RecapData.canShare` acepta.
Future<String?> showMatchPicker(BuildContext context) => showModalBottomSheet<String>(
    context: context, isScrollControlled: true, showDragHandle: true, useSafeArea: true, backgroundColor: AppColors.bg,
    builder: (_) => const _Picker());

class _Picker extends ConsumerStatefulWidget {
  const _Picker();
  @override
  ConsumerState<_Picker> createState() => _PickerState();
}

class _PickerState extends ConsumerState<_Picker> {
  String q = '';
  @override
  Widget build(BuildContext context) {
    final async = ref.watch(shareableMatchesProvider), uid = ref.watch(currentUserIdProvider);
    return DraggableScrollableSheet(expand: false, initialChildSize: .8, minChildSize: .5, maxChildSize: .95, builder: (_, ctl) => Column(children: [
      Padding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 8), child: Row(children: [const Expanded(child: Text('Compartir resultado', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800))),
        IconButton(tooltip: 'Cerrar', icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context))])),
      Padding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 8), child: SearchBar(hintText: 'Buscar por rival, club, liga o fecha', leading: const Icon(Icons.search), onChanged: (v) => setState(() => q = v.trim().toLowerCase()))),
      Expanded(child: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => Center(child: TextButton(onPressed: () => ref.invalidate(shareableMatchesProvider), child: const Text('No se pudo cargar. Reintentar'))),
        data: (all) {
          final l = all.where((m) => q.isEmpty || _hay(m, uid).contains(q)).toList();
          if (all.isEmpty) return const _Empty('Aún no tienes partidos confirmados', 'Cuando los dos capitanes confirmen un resultado podrás compartirlo aquí.');
          if (l.isEmpty) return const _Empty('Sin resultados', 'Prueba con otro nombre, club o liga.');
          return ListView.builder(controller: ctl, padding: const EdgeInsets.fromLTRB(20, 4, 20, 24), itemCount: l.length, itemBuilder: (_, i) => _Row(m: l[i], uid: uid, onTap: () => Navigator.pop(context, l[i].id)));
        },
      )),
    ]));
  }

  static String _hay(LifecycleMatch m, String uid) => [m.club, m.court ?? '', m.leagueName ?? '', m.type == MatchType.league ? 'liga' : 'amistoso', recapDate(m.endedAt ?? m.scheduledAt), ...m.players.map((p) => p.name)].join(' ').toLowerCase();
}

class _Row extends StatelessWidget {
  const _Row({required this.m, required this.uid, required this.onTap});
  final LifecycleMatch m; final String uid; final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final me = m.player(uid)!, won = m.winnerTeam == me.team;
    final rivals = m.players.where((p) => p.team != me.team).map((p) => p.name.split(' ').first).join(' y ');
    final mate = m.players.where((p) => p.team == me.team && p.id != uid).map((p) => p.name.split(' ').first).join();
    return Padding(padding: const EdgeInsets.only(bottom: 10), child: Material(color: AppColors.surface, borderRadius: AppRadius.rMd, clipBehavior: Clip.antiAlias,
        child: InkWell(onTap: onTap, child: Padding(padding: const EdgeInsets.all(14), child: Row(children: [
          Container(width: 4, height: 44, decoration: BoxDecoration(color: won ? AppColors.brand : AppColors.ink400, borderRadius: BorderRadius.circular(2))),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(m.sets.map((s) => '${s.a}-${s.b}').join('  '), style: const TextStyle(fontFamily: 'Unbounded', fontWeight: FontWeight.w600, fontSize: 16)),
            const SizedBox(height: 2),
            Text('${won ? 'Victoria' : 'Derrota'} · con $mate vs $rivals', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            Text('${recapDate(m.endedAt ?? m.scheduledAt)} · ${m.club}${m.type == MatchType.league && m.leagueName != null ? ' · ${m.leagueName}' : ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
          ])),
          const Icon(Icons.chevron_right, color: AppColors.textMuted),
        ])))));
  }
}

class _Empty extends StatelessWidget {
  const _Empty(this.t, this.s);
  final String t, s;
  @override
  Widget build(BuildContext context) => Center(child: Padding(padding: const EdgeInsets.all(32), child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.emoji_events_outlined, size: 36, color: AppColors.textMuted), const SizedBox(height: 10),
        Text(t, style: const TextStyle(fontWeight: FontWeight.w800)), const SizedBox(height: 4), Text(s, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textMuted)),
      ])));
}
