import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/banner_schedule.dart';

/// Reloj del dispositivo (hora LOCAL). Se sustituye en los tests para simular horas y zonas horarias.
final bannerNowProvider = Provider<DateTime Function()>((_) => DateTime.now);

/// Momento del día que debe mostrar el banner de Inicio. Solo emite cuando el momento CAMBIA, así que el banner se
/// reconstruye 4 veces al día como mucho (y nada más de la pantalla).
///
/// Se recalcula:
///  - al crearse (abrir la app / entrar en Inicio);
///  - con un temporizador de un solo disparo a la hora exacta del siguiente cambio (06:00, 09:00, 18:00, 20:00);
///  - al volver de segundo plano (los temporizadores no corren con la app en pausa);
///  - con una comprobación ligera cada minuto que detecta un cambio de zona horaria o de hora del sistema mientras la
///    app está abierta (el temporizador largo se habría quedado programado para la hora antigua).
class BannerClock extends StateNotifier<DayPhase> with WidgetsBindingObserver {
  BannerClock(this._now) : super(dayPhaseAt(_now())) {
    WidgetsBinding.instance.addObserver(this);
    _schedule();
    _watch = Timer.periodic(watchInterval, (_) => _check());
  }

  final DateTime Function() _now;
  static const watchInterval = Duration(minutes: 1);
  Timer? _next, _watch;
  late Duration _offset = _now().timeZoneOffset;
  late String _zone = _now().timeZoneName;
  DateTime? _due;

  void _schedule() {
    _next?.cancel();
    final now = _now();
    final due = _due = nextPhaseChange(now);
    // +250 ms: al dispararse ya estamos dentro del nuevo momento aunque el temporizador se adelante un poco.
    _next = Timer(due.difference(now) + const Duration(milliseconds: 250), refresh);
  }

  /// Recalcula el momento con la hora actual y reprograma el siguiente cambio.
  void refresh() {
    final now = _now();
    _offset = now.timeZoneOffset;
    _zone = now.timeZoneName;
    final p = dayPhaseAt(now);
    if (p != state) state = p;
    _schedule();
  }

  void _check() {
    final now = _now();
    final zoneChanged = now.timeZoneOffset != _offset || now.timeZoneName != _zone;
    final missed = _due != null && !now.isBefore(_due!);     // el temporizador no llegó a tiempo (o la hora saltó)
    if (zoneChanged || missed || dayPhaseAt(now) != state) refresh();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _next?.cancel();
    _watch?.cancel();
    super.dispose();
  }
}

final bannerClockProvider = StateNotifierProvider.autoDispose<BannerClock, DayPhase>((ref) => BannerClock(ref.watch(bannerNowProvider)));
