import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/motion/app_motion.dart';
import '../../../core/theme/design_tokens.dart';
import '../../../core/widgets/motion_widgets.dart';
import '../application/recap_painter.dart';
import '../application/recap_providers.dart';
import '../application/recap_service.dart';
import '../domain/recap_data.dart';

/// «Share Match»: previsualización + carrusel de plantillas + formato + opciones + acciones reales.
/// La vista previa usa el MISMO `RecapPainter` que la exportación PNG.
class ShareMatchScreen extends ConsumerStatefulWidget {
  const ShareMatchScreen({super.key, required this.matchId});
  final String matchId;
  @override
  ConsumerState<ShareMatchScreen> createState() => _ShareMatchState();
}

class _ShareMatchState extends ConsumerState<ShareMatchScreen> {
  RecapTemplate tpl = RecapTemplate.result;
  RecapFormat fmt = RecapFormat.story;
  RecapOptions opts = const RecapOptions();
  RecapImages images = const {};
  bool busy = false, loadedImages = false;
  String? done;
  late final PageController _pc = PageController(viewportFraction: .78);

  @override
  void dispose() { _pc.dispose(); super.dispose(); }

  Future<void> _ensureImages(RecapData d) async {
    if (loadedImages) return;
    loadedImages = true;
    final im = await RecapImageLoader.load(d);
    if (mounted) setState(() => images = im);
  }

  Future<void> _run(RecapData d, RecapFormat f, Future<RecapAction> Function(RecapService, Uint8List, String) act) async {
    if (busy) return;
    HapticFeedback.selectionClick();
    setState(() { busy = true; done = null; });
    final svc = ref.read(recapServiceProvider);
    try {
      final png = await svc.render(d, tpl, f, opts, images);
      final r = await act(svc, png, recapFileName(d, tpl, f));
      if (!mounted) return;
      setState(() => done = switch (r) {
            RecapAction.saved => 'Imagen guardada en tu galería',
            RecapAction.copied => 'Imagen copiada',
            RecapAction.copyUnsupported => 'Tu dispositivo no permite copiar imágenes',
            RecapAction.shared => null,
          });
    } catch (_) {
      if (mounted) setState(() => done = 'No se pudo completar la acción');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(recapDataProvider(widget.matchId));
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(title: const Text('Share Match'), centerTitle: true),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _Blocked(reason: e is RecapException ? e.reason : null),
        data: (d) {
          _ensureImages(d);
          return ListView(padding: const EdgeInsets.fromLTRB(AppSpacing.screenH, AppSpacing.s2, AppSpacing.screenH, AppSpacing.s8), children: [
            _Preview(d: d, tpl: tpl, fmt: fmt, opts: opts, images: images, busy: busy),
            const SizedBox(height: AppSpacing.s4),
            SizedBox(height: 44, child: _Carousel(tpl: tpl, controller: _pc, onChanged: (t) { HapticFeedback.selectionClick(); setState(() => tpl = t); })),
            const SizedBox(height: AppSpacing.s3),
            SlidingTabs(labels: [for (final f in RecapFormat.values) f.label], index: fmt.index, onChanged: (i) => setState(() => fmt = RecapFormat.values[i])),
            const SizedBox(height: AppSpacing.s2),
            _Toggle('Mostrar estadísticas', opts.showStats && d.stats != null, d.stats == null ? null : (v) => setState(() => opts = opts.copyWith(showStats: v))),
            _Toggle('Mostrar duración', opts.showDuration && d.hasDuration, !d.hasDuration ? null : (v) => setState(() => opts = opts.copyWith(showDuration: v))),
            _Toggle('Mostrar ELO', opts.showElo && d.hasElo, !d.hasElo ? null : (v) => setState(() => opts = opts.copyWith(showElo: v))),
            _Toggle('Mostrar club', opts.showClub, (v) => setState(() => opts = opts.copyWith(showClub: v))),
            const SizedBox(height: AppSpacing.s3),
            Row(children: [
              Expanded(child: _Act(Icons.camera_alt_outlined, 'INSTAGRAM STORY', busy, () => _run(d, RecapFormat.story, (s, b, n) => s.shareNative(b, n)))),
              const SizedBox(width: AppSpacing.s2),
              Expanded(child: _Act(Icons.ios_share, 'MORE', busy, () => _run(d, fmt, (s, b, n) => s.shareNative(b, n)))),
            ]),
            const SizedBox(height: AppSpacing.s2),
            Row(children: [
              Expanded(child: _Act(Icons.download_outlined, 'SAVE IMAGE', busy, () => _run(d, fmt, (s, b, n) => s.save(b, n)))),
              const SizedBox(width: AppSpacing.s2),
              Expanded(child: _Act(Icons.copy_outlined, 'COPY IMAGE', busy, () => _run(d, fmt, (s, b, _) => s.copy(b)))),
            ]),
            AnimatedSwitcher(duration: AppAnimations.scaled(context, AppAnimations.appear), child: done == null ? const SizedBox(key: ValueKey('n'), height: 0)
                : Padding(key: ValueKey(done), padding: const EdgeInsets.only(top: AppSpacing.s3), child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(done!.startsWith('No') || done!.startsWith('Tu') ? Icons.info_outline : Icons.check_circle, size: 18, color: done!.startsWith('No') || done!.startsWith('Tu') ? AppColors.warning : AppColors.success),
                    const SizedBox(width: 8), Flexible(child: Text(done!, style: const TextStyle(fontWeight: FontWeight.w600))),
                  ]))),
          ]);
        },
      ),
    );
  }
}

class _Preview extends StatelessWidget {
  const _Preview({required this.d, required this.tpl, required this.fmt, required this.opts, required this.images, required this.busy});
  final RecapData d; final RecapTemplate tpl; final RecapFormat fmt; final RecapOptions opts; final RecapImages images; final bool busy;
  @override
  Widget build(BuildContext context) {
    final ar = fmt.width / fmt.height, maxH = MediaQuery.of(context).size.height * .5;
    return Center(child: AnimatedContainer(
      duration: AppAnimations.scaled(context, AppAnimations.tab), curve: AppAnimations.standard,
      constraints: BoxConstraints(maxHeight: maxH), height: maxH, width: maxH * ar,
      child: Stack(fit: StackFit.expand, children: [
        DecoratedBox(decoration: BoxDecoration(borderRadius: AppRadius.rMd, boxShadow: AppShadows.pop),
          child: ClipRRect(borderRadius: AppRadius.rMd, child: AnimatedSwitcher(duration: AppAnimations.scaled(context, AppAnimations.tab),
              child: RepaintBoundary(key: ValueKey('${tpl.name}-${fmt.name}'), child: CustomPaint(painter: RecapPainter(d, tpl, fmt, opts: opts, images: images)))))),
        if (busy) const Positioned(right: 10, top: 10, child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4))),
      ]),
    ));
  }
}

class _Carousel extends StatelessWidget {
  const _Carousel({required this.tpl, required this.controller, required this.onChanged});
  final RecapTemplate tpl; final PageController controller; final ValueChanged<RecapTemplate> onChanged;
  @override
  Widget build(BuildContext context) => ListView(scrollDirection: Axis.horizontal, children: [
        for (final t in RecapTemplate.values) Padding(padding: const EdgeInsets.only(right: AppSpacing.s2), child: Pressable(child: ChoiceChip(
            label: Text(t.label), selected: t == tpl, onSelected: (_) => onChanged(t), showCheckmark: false,
            selectedColor: AppColors.brand, labelStyle: TextStyle(fontWeight: FontWeight.w700, color: t == tpl ? AppColors.brandInk : AppColors.textMuted)))),
      ]);
}

class _Toggle extends StatelessWidget {
  const _Toggle(this.label, this.value, this.onChanged);
  final String label; final bool value; final ValueChanged<bool>? onChanged;
  @override
  Widget build(BuildContext context) => SwitchListTile(dense: true, contentPadding: EdgeInsets.zero, title: Text(label), value: value, onChanged: onChanged);
}

class _Act extends StatelessWidget {
  const _Act(this.icon, this.label, this.busy, this.onTap);
  final IconData icon; final String label; final bool busy; final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Pressable(enabled: !busy, child: OutlinedButton.icon(
      onPressed: busy ? null : onTap, icon: Icon(icon, size: 18), label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, letterSpacing: .4)),
      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(AppLayout.buttonHeight))));
}

class _Blocked extends StatelessWidget {
  const _Blocked({this.reason});
  final RecapRefusal? reason;
  @override
  Widget build(BuildContext context) => Center(child: Padding(padding: const EdgeInsets.all(32), child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.lock_outline, size: 36, color: AppColors.textMuted), const SizedBox(height: 12),
        Text(switch (reason) {
          RecapRefusal.notConfirmed => 'Solo se puede compartir un resultado confirmado por los dos capitanes.',
          RecapRefusal.notParticipant => 'Solo los jugadores del partido pueden compartirlo.',
          _ => 'Este partido todavía no tiene un resultado que compartir.',
        }, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w600)),
      ])));
}
