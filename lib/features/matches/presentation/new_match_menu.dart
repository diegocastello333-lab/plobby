import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/plobby_theme.dart';

/// Menú del botón «+»: elige el tipo de partido y abre el formulario único (`/match/new?type=...`).
/// Las acciones previas del «+» (crear liga, descubrir ligas) se mantienen como «Más opciones».
Future<void> showNewMatchMenu(BuildContext context) => showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _Menu(),
    );

class _Menu extends StatelessWidget {
  const _Menu();
  @override
  Widget build(BuildContext context) => SafeArea(child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Nuevo partido', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          const Text('¿Qué tipo de partido quieres crear?', style: TextStyle(color: AppColors.textMuted)),
          const SizedBox(height: 16),
          _OptionCard(icon: Icons.emoji_events_outlined, title: 'Crear partido de liga', text: 'Registra un partido que forme parte de una liga', dark: false, type: 'league'),
          const SizedBox(height: 12),
          _OptionCard(icon: Icons.sports_tennis, title: 'Crear partido amistoso', text: 'Organiza un partido fuera de una competición', dark: true, type: 'friendly'),
          const SizedBox(height: 16),
          const Text('MÁS OPCIONES', style: TextStyle(fontSize: 11, letterSpacing: 1.2, fontWeight: FontWeight.w700, color: AppColors.textMuted)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, children: [
            ActionChip(avatar: const Icon(Icons.emoji_events_outlined, size: 16), label: const Text('Crear una liga'), onPressed: () { Navigator.pop(context); context.push('/leagues/new'); }),
            ActionChip(avatar: const Icon(Icons.search, size: 16), label: const Text('Descubrir ligas'), onPressed: () { Navigator.pop(context); context.push('/leagues/discover'); }),
          ]),
        ]),
      ));
}

class _OptionCard extends StatefulWidget {
  const _OptionCard({required this.icon, required this.title, required this.text, required this.dark, required this.type});
  final IconData icon; final String title, text, type; final bool dark;
  @override
  State<_OptionCard> createState() => _OptionCardState();
}

class _OptionCardState extends State<_OptionCard> {
  bool _down = false;
  @override
  Widget build(BuildContext context) {
    final bg = widget.dark ? AppColors.inverse : AppColors.brand;
    final fg = widget.dark ? AppColors.bg : AppColors.brandInk;
    final reduce = MediaQuery.of(context).disableAnimations;
    return AnimatedScale(
      scale: _down ? .97 : 1, duration: reduce ? Duration.zero : const Duration(milliseconds: 140), curve: Curves.easeOut,
      child: Material(
        color: bg, borderRadius: AppRadius.rLg,
        child: InkWell(
          borderRadius: AppRadius.rLg, onHighlightChanged: (v) => setState(() => _down = v),
          onTap: () { HapticFeedback.selectionClick(); Navigator.pop(context); context.push('/match/new?type=${widget.type}'); },
          child: Padding(padding: const EdgeInsets.all(16), child: Row(children: [
            Container(width: 52, height: 52, decoration: BoxDecoration(color: widget.dark ? AppColors.brand : const Color(0x1A171C19), borderRadius: BorderRadius.circular(16)),
                child: Icon(widget.icon, size: 26, color: AppColors.brandInk)),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(widget.title, style: TextStyle(fontFamily: 'Unbounded', fontSize: 15, fontWeight: FontWeight.w600, color: fg)),
              const SizedBox(height: 4),
              Text(widget.text, style: TextStyle(fontSize: 13.5, color: fg.withOpacity(.82))),
            ])),
            Icon(Icons.chevron_right, color: fg),
          ])),
        ),
      ),
    );
  }
}
