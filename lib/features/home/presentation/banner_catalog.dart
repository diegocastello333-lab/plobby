import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../profile/domain/models.dart';

/// Banners predeterminados de Inicio. «clasico» es la foto original de Plobby; el resto son ilustraciones vectoriales
/// con la paleta de la app (tinta #171C19, lima #D2F548, marfil #F6F8F1): nítidas a cualquier tamaño y sin peso de
/// descarga. Lienzo 1200×1000 (6:5, la proporción del banner).
@immutable
class BannerPreset {
  const BannerPreset(this.id, this.name, [this.svg]);
  final String id, name;
  final String? svg;   // null = foto original (asset)
}

const kBannerAspect = 6 / 5;
const _ink = '#171C19', _lime = '#D2F548', _ivory = '#F6F8F1';

String _lines(Iterable<String> paths, String stroke, double width, [double opacity = 1]) =>
    '<g fill="none" stroke="$stroke" stroke-width="$width" stroke-opacity="$opacity" stroke-linecap="round">${paths.map((d) => '<path d="$d"/>').join()}</g>';

/// Pista en perspectiva (vista desde el fondo): rectángulo exterior, red, líneas de saque y central.
String _perspectiveCourt(String stroke, double opacity) => _lines([
      'M140 980 L420 420 L780 420 L1060 980 Z',   // exterior
      'M300 660 L900 660',                          // red
      'M362 540 L838 540', 'M226 810 L974 810',     // líneas de saque
      'M600 540 L600 810',                          // central
    ], stroke, 6, opacity);

String _netMesh() {
  final b = StringBuffer();
  for (var x = -400; x < 1600; x += 34) { b.write('M$x 380 L${x + 260} 640 '); b.write('M${x + 260} 380 L$x 640 '); }
  return '<path d="$b" stroke="$_ivory" stroke-opacity=".22" stroke-width="2" fill="none"/>';
}

final bannerPresets = <BannerPreset>[
  const BannerPreset('clasico', 'Clásico'),
  BannerPreset('noche', 'Pista de noche', '''<svg viewBox="0 0 1200 1000" xmlns="http://www.w3.org/2000/svg">
<defs><linearGradient id="g" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#0E1311"/><stop offset="1" stop-color="#25362C"/></linearGradient>
<radialGradient id="l1" cx=".12" cy=".08" r=".45"><stop offset="0" stop-color="#FFFFFF" stop-opacity=".55"/><stop offset="1" stop-color="#FFFFFF" stop-opacity="0"/></radialGradient>
<radialGradient id="l2" cx=".88" cy=".08" r=".45"><stop offset="0" stop-color="#FFFFFF" stop-opacity=".55"/><stop offset="1" stop-color="#FFFFFF" stop-opacity="0"/></radialGradient></defs>
<rect width="1200" height="1000" fill="url(#g)"/><path d="M140 980 L420 420 L780 420 L1060 980 Z" fill="#1F5A3A" fill-opacity=".55"/>
${_perspectiveCourt(_lime, .9)}<rect width="1200" height="1000" fill="url(#l1)"/><rect width="1200" height="1000" fill="url(#l2)"/>
<circle cx="760" cy="720" r="16" fill="$_lime"/></svg>'''),
  BannerPreset('lima', 'Línea lima', '''<svg viewBox="0 0 1200 1000" xmlns="http://www.w3.org/2000/svg">
<defs><linearGradient id="g" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#E2FA7A"/><stop offset="1" stop-color="#A9CF2A"/></linearGradient></defs>
<rect width="1200" height="1000" fill="url(#g)"/>
${_lines(List.generate(9, (i) => 'M${-200 + i * 190} 1000 L${300 + i * 190} 0'), _ink, 3, .12)}
${_lines(['M640 240 H1120 V760 H640 Z', 'M880 240 V760', 'M640 500 H1120'], _ink, 8, .85)}
<circle cx="560" cy="620" r="54" fill="$_ink"/><path d="M520 590 Q560 620 520 660 M600 590 Q560 620 600 660" stroke="$_lime" stroke-width="7" fill="none"/></svg>'''),
  BannerPreset('azul', 'Pista azul', '''<svg viewBox="0 0 1200 1000" xmlns="http://www.w3.org/2000/svg">
<defs><linearGradient id="g" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#2F6FDE"/><stop offset="1" stop-color="#1C3F8A"/></linearGradient></defs>
<rect width="1200" height="1000" fill="#14306B"/><rect x="120" y="60" width="960" height="880" rx="8" fill="url(#g)"/>
${_lines(['M120 500 H1080', 'M120 270 H1080', 'M120 730 H1080', 'M600 270 V730'], _ivory, 7, .95)}
<rect x="120" y="60" width="960" height="880" rx="8" fill="none" stroke="$_ivory" stroke-width="10"/>
<path d="M120 490 H1080 V510 H120 Z" fill="$_ink" fill-opacity=".55"/><circle cx="830" cy="380" r="20" fill="$_lime"/></svg>'''),
  BannerPreset('arcilla', 'Tierra batida', '''<svg viewBox="0 0 1200 1000" xmlns="http://www.w3.org/2000/svg">
<defs><linearGradient id="g" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#D9774E"/><stop offset="1" stop-color="#9E4527"/></linearGradient></defs>
<rect width="1200" height="1000" fill="url(#g)"/>${_perspectiveCourt(_ivory, .9)}
<path d="M300 660 L900 660 L900 600 L300 600 Z" fill="$_ink" fill-opacity=".25"/><circle cx="430" cy="760" r="18" fill="$_lime"/></svg>'''),
  BannerPreset('red', 'La red', '''<svg viewBox="0 0 1200 1000" xmlns="http://www.w3.org/2000/svg">
<defs><linearGradient id="g" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#2A3530"/><stop offset="1" stop-color="$_ink"/></linearGradient></defs>
<rect width="1200" height="1000" fill="url(#g)"/>${_netMesh()}
<rect x="0" y="360" width="1200" height="26" fill="$_ivory"/><rect x="0" y="640" width="1200" height="6" fill="$_ivory" fill-opacity=".4"/>
<circle cx="900" cy="250" r="44" fill="$_lime"/><path d="M870 222 Q900 250 870 280 M930 222 Q900 250 930 280" stroke="$_ink" stroke-width="5" fill="none"/></svg>'''),
  BannerPreset('bola', 'Bola', '''<svg viewBox="0 0 1200 1000" xmlns="http://www.w3.org/2000/svg">
<defs><radialGradient id="b" cx=".38" cy=".35" r=".7"><stop offset="0" stop-color="#ECFF9C"/><stop offset=".6" stop-color="$_lime"/><stop offset="1" stop-color="#9DBB24"/></radialGradient></defs>
<rect width="1200" height="1000" fill="$_ink"/>
${_lines(['M80 470 H520', 'M140 520 H560', 'M60 570 H500', 'M180 620 H540'], _lime, 6, .28)}
<circle cx="820" cy="520" r="300" fill="url(#b)"/>
<path d="M600 330 Q820 520 600 710 M1040 330 Q820 520 1040 710" stroke="$_ivory" stroke-width="18" fill="none" stroke-linecap="round"/></svg>'''),
  BannerPreset('atardecer', 'Atardecer', '''<svg viewBox="0 0 1200 1000" xmlns="http://www.w3.org/2000/svg">
<defs><linearGradient id="g" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#F97316"/><stop offset=".55" stop-color="#C2410C"/><stop offset="1" stop-color="$_ink"/></linearGradient></defs>
<rect width="1200" height="1000" fill="url(#g)"/><circle cx="840" cy="380" r="150" fill="#FDBA74" fill-opacity=".9"/>
<path d="M0 560 L1200 560 L1200 1000 L0 1000 Z" fill="$_ink" fill-opacity=".55"/>${_perspectiveCourt(_ivory, .55)}</svg>'''),
  BannerPreset('marfil', 'Minimal', '''<svg viewBox="0 0 1200 1000" xmlns="http://www.w3.org/2000/svg">
<rect width="1200" height="1000" fill="$_ivory"/>
${_lines(['M560 140 H1140 V860 H560 Z', 'M560 500 H1140', 'M560 320 H1140', 'M560 680 H1140', 'M850 320 V680'], _ink, 5, .8)}
<circle cx="440" cy="560" r="36" fill="$_lime" stroke="$_ink" stroke-width="5"/></svg>'''),
];

BannerPreset? bannerPresetById(String? id) => id == null ? null : bannerPresets.where((p) => p.id == id).firstOrNull;

/// Imagen del banner de un perfil: foto propia → predeterminado → foto clásica. Siempre recortada (cover), nunca
/// deformada. Las fotos propias se piden al tamaño de pantalla (cacheWidth) para no gastar memoria.
class BannerImage extends StatelessWidget {
  const BannerImage({super.key, this.profile, this.presetId, this.url});
  final PlayerProfile? profile;
  final String? presetId, url;
  @override
  Widget build(BuildContext context) {
    final u = url ?? profile?.bannerUrl;
    final width = (MediaQuery.sizeOf(context).width * MediaQuery.devicePixelRatioOf(context)).round();
    final classic = Image.asset('assets/images/home_banner.jpg', fit: BoxFit.cover, alignment: const Alignment(0, .16), cacheWidth: width,
        semanticLabel: 'Pistas de pádel al atardecer', errorBuilder: (_, __, ___) => const SizedBox.shrink());
    if (u != null && u.isNotEmpty) {
      return Image.network(u, fit: BoxFit.cover, cacheWidth: width, semanticLabel: 'Banner personalizado',
          frameBuilder: (_, child, frame, sync) => sync ? child : AnimatedOpacity(opacity: frame == null ? 0 : 1, duration: const Duration(milliseconds: 250), child: child),
          errorBuilder: (_, __, ___) => classic);
    }
    final p = bannerPresetById(presetId ?? profile?.bannerId);
    if (p?.svg != null) return SvgPicture.string(p!.svg!, fit: BoxFit.cover, semanticsLabel: 'Banner ${p.name}');
    return classic;
  }
}
