import 'package:flutter/material.dart';
import '../net/net_activity.dart';
import '../theme/design_tokens.dart';
import '../widgets/state_views.dart';

/// Pantalla en carga diferida (`import '…' deferred as x`). En la web, el código de las pantallas secundarias (torneos,
/// compartir, Wrapped, ajustes, editar perfil, detalle del ELO, crear liga…) se descarga solo la primera vez que se abren,
/// así la primera carga de Plobby pesa menos. En Android/iOS la carga es inmediata (no hay descarga).
///
/// Mientras llega, se ve un esqueleto con la forma de una pantalla (cabecera + bloques); si falla la descarga (sin red),
/// una tarjeta de error con «Reintentar».
class DeferredScreen extends StatefulWidget {
  const DeferredScreen({super.key, required this.load, required this.builder});

  /// `x.loadLibrary` del import diferido.
  final Future<void> Function() load;

  /// Construye la pantalla una vez cargada (aquí ya se puede usar `x.Pantalla(...)`).
  final WidgetBuilder builder;

  /// Bibliotecas ya cargadas en esta sesión: la segunda vez se construye en el mismo fotograma, sin esqueleto.
  static final _loaded = <Function>{};

  /// Carga (o registra como cargadas) las bibliotecas indicadas. En Android/iOS no hay descarga: se hace al arrancar y
  /// las pantallas se construyen en el primer fotograma. En la web se llama unos segundos después de abrir la app, en
  /// segundo plano, para que abrir una pantalla secundaria sea instantáneo sin retrasar la primera carga.
  static Future<void> preload(Iterable<Future<void> Function()> loads) async {
    for (final l in loads) {
      if (_loaded.contains(l)) continue;
      try { await l(); _loaded.add(l); } catch (_) {/* sin red: se cargará al abrirla */}
    }
  }

  @override
  State<DeferredScreen> createState() => _DeferredScreenState();
}

class _DeferredScreenState extends State<DeferredScreen> {
  late Future<void> _future = _start();

  Future<void> _start() async {
    await NetActivity.track(widget.load());   // barra de carga si la descarga tarda
    DeferredScreen._loaded.add(widget.load);
  }

  @override
  Widget build(BuildContext context) {
    if (DeferredScreen._loaded.contains(widget.load)) return widget.builder(context);
    return FutureBuilder<void>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.done && !snap.hasError) return widget.builder(context);
        return Scaffold(body: SafeArea(child: ListView(padding: const EdgeInsets.all(20), children: [
          if (snap.hasError)
            ErrorStateCard(error: snap.error!, onRetry: () => setState(() => _future = _start()))
          else ...const [
            LoadingBlock(height: 44, radius: AppRadius.md),
            SizedBox(height: 20),
            LoadingBlock(height: 160),
            SizedBox(height: 14),
            LoadingBlock(height: 120),
          ],
        ])));
      },
    );
  }
}
