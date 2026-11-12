import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Iconos del prototipo HTML (objeto `IC` + función `ic()` de Plobby (4).html), trazo a trazo.
///
/// Igual que en el HTML: viewBox 24×24, sin relleno, trazo del color actual, grosor 1.8 por defecto y extremos
/// redondeados. Tamaño por defecto 20. NO redibujar a mano: este archivo se generó desde el HTML.
enum PlobbyIcons {
  alert, archive, arrdn, arrup, back, ball, bell, building, cal, check, chev, clock, close, copy, dash, down, edit, feed, flag, flame, globe, home, image, info, link, lock, logout, more, pin, plane, play, plus, racket, refresh, search, share, shield, sliders, star, stopi, swords, thumb, timer, trash, trophy, user, userplus, users, whistle, wifi;

  /// Contenido SVG (solo los trazos; el contenedor `<svg>` lo pone [PlobbyIcon]).
  String get paths => _paths[this]!;
}

const _paths = <PlobbyIcons, String>{
  PlobbyIcons.alert: '<path d="M12 4l9 16H3z"/><path d="M12 10v4M12 17h.01"/>',
  PlobbyIcons.archive: '<rect x="3" y="4" width="18" height="4" rx="1"/><path d="M5 8v11a1 1 0 0 0 1 1h12a1 1 0 0 0 1-1V8M10 12h4"/>',
  PlobbyIcons.arrdn: '<path d="M12 5v13M6 13l6 6 6-6"/>',
  PlobbyIcons.arrup: '<path d="M12 19V6M6 11l6-6 6 6"/>',
  PlobbyIcons.back: '<path d="M15 5l-7 7 7 7"/>',
  PlobbyIcons.ball: '<circle cx="12" cy="12" r="9"/><path d="M4 8c4 1 7 4 8 8M20 16c-4-1-7-4-8-8"/>',
  PlobbyIcons.bell: '<path d="M6 16v-5a6 6 0 0 1 12 0v5l1.500 2h-15z"/><path d="M10 21a2 2 0 0 0 4 0"/>',
  PlobbyIcons.building: '<path d="M4 21V5a1 1 0 0 1 1-1h8a1 1 0 0 1 1 1v16M14 10h5a1 1 0 0 1 1 1v10M2 21h20M8 8h2M8 12h2M8 16h2"/>',
  PlobbyIcons.cal: '<rect x="4" y="5" width="16" height="15" rx="2"/><path d="M4 10h16M9 3v4M15 3v4"/>',
  PlobbyIcons.check: '<path d="M5 12.5l4.5 4.5L19 7"/>',
  PlobbyIcons.chev: '<path d="M9 5l7 7-7 7"/>',
  PlobbyIcons.clock: '<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/>',
  PlobbyIcons.close: '<path d="M6 6l12 12M18 6L6 18"/>',
  PlobbyIcons.copy: '<rect x="8" y="8" width="12" height="12" rx="2"/><path d="M16 8V6a2 2 0 0 0-2-2H6a2 2 0 0 0-2 2v8a2 2 0 0 0 2 2h2"/>',
  PlobbyIcons.dash: '<path d="M6 12h12"/>',
  PlobbyIcons.down: '<path d="M5 9l7 7 7-7"/>',
  PlobbyIcons.edit: '<path d="M4 20h4L19 9l-4-4L4 16v4z"/><path d="M13.500 6.500l4 4"/>',
  PlobbyIcons.feed: '<rect x="3.500" y="4" width="17" height="16" rx="2.500"/><path d="M3.500 9h17M7.500 13h6M7.500 16.500h9"/>',
  PlobbyIcons.flag: '<path d="M5 21V4M5 4h11l-2 4 2 4H5"/>',
  PlobbyIcons.flame: '<path d="M12 3c1 4 6 6 6 11a6 6 0 0 1-12 0c0-2 .8-3.4 2-4.6.2 1.6 1.1 2.5 2.2 2.8C9.700 8 10.400 5 12 3z"/>',
  PlobbyIcons.globe: '<circle cx="12" cy="12" r="9"/><path d="M3 12h18M12 3c2.500 2.500 3.500 5.500 3.500 9s-1 6.500-3.500 9c-2.500-2.500-3.500-5.500-3.500-9s1-6.500 3.500-9z"/>',
  PlobbyIcons.home: '<path d="M3 10.5 12 3l9 7.500"/><path d="M5 9.500V20a1 1 0 0 0 1 1h4v-6h4v6h4a1 1 0 0 0 1-1V9.500"/>',
  PlobbyIcons.image: '<rect x="3" y="4" width="18" height="16" rx="2"/><circle cx="9" cy="10" r="1.6"/><path d="M21 16l-5-5-8 8"/>',
  PlobbyIcons.info: '<circle cx="12" cy="12" r="9"/><path d="M12 11v5M12 8h.01"/>',
  PlobbyIcons.link: '<path d="M10 14a4 4 0 0 0 5.700 0l3-3a4 4 0 0 0-5.700-5.700l-1 1M14 10a4 4 0 0 0-5.700 0l-3 3a4 4 0 0 0 5.700 5.700l1-1"/>',
  PlobbyIcons.lock: '<rect x="5" y="11" width="14" height="9" rx="2"/><path d="M8 11V8a4 4 0 0 1 8 0v3"/>',
  PlobbyIcons.logout: '<path d="M9 4H5v16h4M16 8l4 4-4 4M20 12H9"/>',
  PlobbyIcons.more: '<circle cx="5" cy="12" r="1.4"/><circle cx="12" cy="12" r="1.4"/><circle cx="19" cy="12" r="1.4"/>',
  PlobbyIcons.pin: '<path d="M12 21s7-6.2 7-11.5a7 7 0 0 0-14 0C5 14.8 12 21 12 21z"/><circle cx="12" cy="9.5" r="2.5"/>',
  PlobbyIcons.plane: '<path d="M21 3 3 10.500l7 2.500 2.500 7z"/><path d="M10 13 21 3"/>',
  PlobbyIcons.play: '<path d="M7 4.5v15l12-7.5z"/>',
  PlobbyIcons.plus: '<path d="M12 5v14M5 12h14"/>',
  PlobbyIcons.racket: '<circle cx="9.5" cy="9.5" r="6.5"/><path d="M14.2 14.2L20 20M7 7.5h5M7 10h5M7 12.5h5"/>',
  PlobbyIcons.refresh: '<path d="M20 11a8 8 0 0 0-14-4L4 9M4 13a8 8 0 0 0 14 4l2-2M4 4v5h5M20 20v-5h-5"/>',
  PlobbyIcons.search: '<circle cx="11" cy="11" r="6.5"/><path d="M20 20l-4-4"/>',
  PlobbyIcons.share: '<path d="M12 16V4M7 9l5-5 5 5M5 14v5a1 1 0 0 0 1 1h12a1 1 0 0 0 1-1v-5"/>',
  PlobbyIcons.shield: '<path d="M12 3l8 3v6c0 4.500-3.200 8-8 9-4.800-1-8-4.500-8-9V6z"/>',
  PlobbyIcons.sliders: '<path d="M4 7h10M18 7h2M4 17h2M10 17h10"/><circle cx="16" cy="7" r="2"/><circle cx="8" cy="17" r="2"/>',
  PlobbyIcons.star: '<path d="M12 3l2.700 5.600 6.100.9-4.400 4.300 1 6.100L12 17l-5.400 2.900 1-6.100L3.200 9.500l6.100-.9z"/>',
  PlobbyIcons.stopi: '<rect x="6" y="6" width="12" height="12" rx="2"/>',
  PlobbyIcons.swords: '<path d="M5 19L19 5M14 5h5v5M5 5l14 14"/>',
  PlobbyIcons.thumb: '<path d="M7 11v9H4v-9h3z"/><path d="M7 11l4-7c1.500 0 2.500 1.200 2.200 2.700L12.700 10H19a2 2 0 0 1 2 2.300l-1 6a2 2 0 0 1-2 1.700H7"/>',
  PlobbyIcons.timer: '<circle cx="12" cy="13.5" r="7.5"/><path d="M12 9.5v4l2.5 1.5M9.5 2.5h5"/>',
  PlobbyIcons.trash: '<path d="M4 7h16M9 7V4h6v3M6 7l1 13h10l1-13"/>',
  PlobbyIcons.trophy: '<path d="M8 21h8M12 17v4"/><path d="M7 4h10v5a5 5 0 0 1-10 0V4z"/><path d="M17 5h3v2a3 3 0 0 1-3 3M7 5H4v2a3 3 0 0 0 3 3"/>',
  PlobbyIcons.user: '<circle cx="12" cy="8" r="4"/><path d="M4 21c0-4.4 3.6-7 8-7s8 2.6 8 7"/>',
  PlobbyIcons.userplus: '<circle cx="9.5" cy="8" r="3.5"/><path d="M3 20c0-3.6 2.9-6 6.5-6s6.5 2.4 6.5 6"/><path d="M19 8v6M16 11h6"/>',
  PlobbyIcons.users: '<circle cx="9" cy="8" r="3.5"/><path d="M2.5 20c0-3.6 2.9-6 6.5-6s6.5 2.4 6.5 6"/><path d="M16 4.6a3.5 3.5 0 0 1 0 6.8M18 14.3c2.2.7 3.5 2.7 3.5 5.7"/>',
  PlobbyIcons.whistle: '<circle cx="8.5" cy="14.5" r="5.5"/><path d="M13.5 12h7.5v-3h-9M8.5 14.5v.01"/>',
  PlobbyIcons.wifi: '<path d="M2 9a15 15 0 0 1 20 0M5 12.500a10 10 0 0 1 14 0M8.500 16a5 5 0 0 1 7 0"/><path d="M12 19.500h.01"/>',
};

/// Dibuja un icono de [PlobbyIcons]. El color sale de [color] o, si no se da, del `IconTheme` actual (como
/// `currentColor` en el HTML). [strokeWidth] equivale al tercer parámetro de `ic(n, s, w)`.
class PlobbyIcon extends StatelessWidget {
  const PlobbyIcon(this.icon, {super.key, this.size = 20, this.strokeWidth = 1.8, this.color, this.semanticLabel});
  final PlobbyIcons icon;
  final double size, strokeWidth;
  final Color? color;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final c = color ?? IconTheme.of(context).color ?? const Color(0xFF171C19);
    final svg = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" '
        'stroke-width="$strokeWidth" stroke-linecap="round" stroke-linejoin="round">${icon.paths}</svg>';
    final pic = SvgPicture.string(svg, width: size, height: size, theme: SvgTheme(currentColor: c), excludeFromSemantics: semanticLabel == null);
    return semanticLabel == null ? pic : Semantics(label: semanticLabel, image: true, child: pic);
  }
}
