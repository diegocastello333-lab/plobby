import 'dart:async';
import 'package:flutter/material.dart';
import '../motion/app_motion.dart';
import '../net/net_activity.dart';
import '../theme/design_tokens.dart';

/// Barra de carga global (2,5 px, lima) arriba del todo. Aparece solo si algo lleva cargando más de [delay]
/// (lo rápido no parpadea) y se va al terminar. No intercepta toques. La usa `PlobbyApp` encima de toda la app.
class LoadingBar extends StatefulWidget {
  const LoadingBar({super.key, required this.child});
  final Widget child;
  static const delay = Duration(milliseconds: 400);   // timing
  @override
  State<LoadingBar> createState() => _LoadingBarState();
}

class _LoadingBarState extends State<LoadingBar> {
  Timer? _t;
  bool _show = false;

  @override
  void initState() { super.initState(); NetActivity.inFlight.addListener(_onChange); }
  @override
  void dispose() { NetActivity.inFlight.removeListener(_onChange); _t?.cancel(); super.dispose(); }

  void _onChange() {
    final busy = NetActivity.inFlight.value > 0;
    if (busy && !_show && _t == null) {
      _t = Timer(LoadingBar.delay, () { _t = null; if (mounted && NetActivity.inFlight.value > 0) setState(() => _show = true); });
    } else if (!busy) {
      _t?.cancel(); _t = null;
      if (_show && mounted) setState(() => _show = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return Stack(children: [
      widget.child,
      Positioned(left: 0, right: 0, top: top, child: IgnorePointer(child: AnimatedOpacity(
        opacity: _show ? 1 : 0, duration: Motion.fast,
        child: _show ? Semantics(label: 'Cargando', liveRegion: true, child: RepaintBoundary(child: SizedBox(height: 2.5,
            // Con «reducir movimiento» la barra no se desliza: queda fija a medias.
            child: LinearProgressIndicator(value: Motion.reduced(context) ? .6 : null, minHeight: 2.5,
                backgroundColor: const Color(0x00000000), color: AppColors.brand))))
            : const SizedBox(height: 2.5),
      ))),
    ]);
  }
}
