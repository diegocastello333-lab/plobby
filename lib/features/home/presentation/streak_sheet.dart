import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/theme/plobby_theme.dart';
import '../../profile/presentation/widgets/win_streak_badge.dart';

/// Hoja inferior de la racha. Solo cuentan partidos CONFIRMADOS (el valor llega ya calculado de
/// `profileViewProvider('me').streak`). Háptico ligero al abrir (más intenso con rachas altas) y
/// celebración (chispas) para rachas >= 5, respetando "reducir movimiento".
Future<void> showStreakSheet(BuildContext context, {required int current, required int best}) {
  if (current >= 5) { HapticFeedback.mediumImpact(); } else if (current > 0) { HapticFeedback.lightImpact(); }
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: PlobbyColors.ivory,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    builder: (_) => _StreakSheet(current: current, best: best),
  );
}

class _StreakSheet extends StatelessWidget {
  const _StreakSheet({required this.current, required this.best});
  final int current, best;
  @override
  Widget build(BuildContext context) {
    final on = current > 0;
    return SafeArea(child: Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Align(alignment: Alignment.centerRight, child: IconButton(tooltip: 'Cerrar', icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context))),
        WinStreakBadge(streak: current, size: 96, showNumber: false),
        const SizedBox(height: 12),
        Text(on ? '¡ESTÁS EN LLAMAS!' : 'SIN RACHA', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: on ? PlobbyColors.forest : PlobbyColors.mute)),
        if (on) Text('$current', style: const TextStyle(fontSize: 64, fontWeight: FontWeight.w800, color: PlobbyColors.forest, height: 1.1)),
        const SizedBox(height: 6),
        Text(on ? 'Llevas $current ${current == 1 ? 'victoria' : 'victorias'} seguidas. ¡Sigue así!' : 'Cada racha empieza con una victoria.', textAlign: TextAlign.center),
        const SizedBox(height: 14),
        Chip(avatar: const Icon(Icons.emoji_events_outlined, size: 16), label: Text('Mejor racha: $best')),
        const SizedBox(height: 8),
        const Text('Solo cuentan partidos confirmados. Una derrota confirmada reinicia la racha.', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: PlobbyColors.mute)),
      ]),
    ));
  }
}
