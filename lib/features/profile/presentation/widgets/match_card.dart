import 'package:flutter/material.dart';
import '../../../../core/theme/plobby_theme.dart';
import '../../../../core/widgets/motion_widgets.dart';
import '../../domain/models.dart';

class MatchCard extends StatelessWidget {
  const MatchCard({super.key, required this.match, required this.me, required this.onTap, this.onShare});
  final MatchResult match; final PlayerRef me; final VoidCallback onTap;
  /// «Compartir resultado» (Match Recap): solo se pasa en partidos confirmados. Icono discreto, zona táctil 44 dp.
  final VoidCallback? onShare;
  @override
  Widget build(BuildContext context) {
    final m = match, pending = !m.confirmed;
    final accent = pending ? PlobbyColors.sage : (m.won ? PlobbyColors.lime : PlobbyColors.sage);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.white, borderRadius: BorderRadius.circular(14), clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            decoration: BoxDecoration(border: Border(left: BorderSide(color: accent, width: 4))),
            child: Column(children: [
              Row(children: [
                for (final p in [me, m.partner]) _Avatar(p),
                const Padding(padding: EdgeInsets.symmetric(horizontal: 6), child: Text('VS', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: PlobbyColors.mute))),
                for (final p in m.opponents) _Avatar(p),
                const Spacer(),
                _Badge(pending ? 'PENDIENTE' : (m.won ? 'VICTORIA' : 'DERROTA'), pending || !m.won),
              ]),
              const SizedBox(height: 10),
              Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(m.scoreLabel, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: m.won || pending ? PlobbyColors.charcoal : PlobbyColors.mute)),
                  Text('${m.playedAt.day}/${m.playedAt.month} · ${m.venue}', style: const TextStyle(fontSize: 12.5, color: PlobbyColors.mute)),
                ])),
                if (!pending && onShare != null)
                  Padding(padding: const EdgeInsets.only(right: 4), child: Pressable(child: IconButton(
                      tooltip: 'Compartir resultado', onPressed: onShare, icon: const Icon(Icons.ios_share, size: 20),
                      style: IconButton.styleFrom(minimumSize: const Size(44, 44), padding: EdgeInsets.zero, foregroundColor: PlobbyColors.charcoal)))),
                if (!pending)
                  Text('${m.eloDelta > 0 ? '+' : ''}${m.eloDelta} ELO',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: m.eloDelta >= 0 ? const Color(0xFF12754D) : PlobbyColors.loss)),
              ]),
            ]),
          ),
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar(this.p);
  final PlayerRef p;
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.only(right: 3),
      child: CircleAvatar(radius: 14, backgroundColor: PlobbyColors.forest,
          backgroundImage: p.avatarUrl != null ? NetworkImage(p.avatarUrl!) : null,
          child: p.avatarUrl == null ? Text(p.name.characters.first, style: const TextStyle(fontSize: 11, color: PlobbyColors.ivory, fontWeight: FontWeight.w700)) : null));
}

class _Badge extends StatelessWidget {
  const _Badge(this.t, this.muted);
  final String t; final bool muted;
  @override
  Widget build(BuildContext context) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: muted ? const Color(0x478A938D) : PlobbyColors.forest, borderRadius: BorderRadius.circular(6)),
      child: Text(t, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: .4, color: muted ? PlobbyColors.charcoal : Colors.white)));
}
