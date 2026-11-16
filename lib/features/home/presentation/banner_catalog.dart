import 'package:flutter/material.dart';
import '../domain/banner_schedule.dart';

/// Alto real del banner de Inicio: 300 dp + la barra de estado (como en el prototipo).
double homeBannerHeight(BuildContext context) => 300 + MediaQuery.paddingOf(context).top;

/// Una imagen de una colección. Ocupa SIEMPRE todo el espacio (SizedBox.expand + cover): recorta lo que sobra, nunca
/// deforma ni deja bandas, aunque el padre dé restricciones sueltas. `gaplessPlayback` evita un fotograma vacío si el
/// asset aún se está decodificando.
class BannerImage extends StatelessWidget {
  const BannerImage({super.key, required this.banner, required this.phase, this.alignment = Alignment.center});
  final HomeBanner banner;
  final DayPhase phase;
  final Alignment alignment;
  @override
  Widget build(BuildContext context) => SizedBox.expand(child: Image.asset(banner.asset(phase), fit: BoxFit.cover, alignment: alignment,
      gaplessPlayback: true, semanticLabel: 'Banner ${banner.name}',
      errorBuilder: (_, __, ___) => const SizedBox.shrink()));
}

/// Franjas que Inicio decodifica por adelantado: la actual y la siguiente (noche → amanecer al dar la vuelta).
List<DayPhase> bannerPhasesToPrecache(DayPhase now) => [now, DayPhase.values[(now.index + 1) % DayPhase.values.length]];

/// Decodifica de antemano las imágenes de una colección para que los cambios de franja sean instantáneos.
///
/// Por defecto solo la franja actual y la SIGUIENTE (la que se mostrará al cambiar de hora): antes se decodificaban las
/// cuatro (≈1 MB de descarga en la web y ≈16 MB de memoria decodificada, 1376×768×4 bytes cada una) aunque solo se ve
/// una. En Safari de iPhone esa memoria importa: si la página usa demasiada, iOS la recarga.
Future<void> precacheBanner(BuildContext context, HomeBanner b, {List<DayPhase>? phases}) {
  final list = phases ?? bannerPhasesToPrecache(dayPhaseAt(DateTime.now()));
  return Future.wait([for (final p in list) precacheImage(AssetImage(b.asset(p)), context, onError: (_, __) {})]);
}
