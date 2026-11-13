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

/// Decodifica de antemano las cuatro imágenes de una colección: los cambios amanecer → día → atardecer → noche (y el
/// cambio de colección) son instantáneos, sin cargas visibles.
Future<void> precacheBanner(BuildContext context, HomeBanner b) =>
    Future.wait([for (final a in b.assets) precacheImage(AssetImage(a), context, onError: (_, __) {})]);
