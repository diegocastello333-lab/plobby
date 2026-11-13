import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/theme/design_tokens.dart';
import '../../../core/widgets/motion_widgets.dart';
import '../../../core/widgets/plobby_components.dart';
import '../../../core/widgets/plobby_icon.dart';
import '../../../core/widgets/state_views.dart';
import '../../share_stats/application/share_service.dart';
import '../application/gamification_share.dart';
import '../domain/gamification_models.dart';

/// Qué se comparte. La vista previa y el PNG usan el MISMO pintor a tamaño real (lo que ves es lo que se guarda).
sealed class ShareTarget {
  const ShareTarget();
  const factory ShareTarget.h2h(H2HData d) = _H2H;
  const factory ShareTarget.wrapped(WrappedData w) = _Wrapped;
  const factory ShareTarget.ranking(RankingData r, RankMetric m) = _Ranking;
  CustomPainter painter(ShareImages images);
  Future<Uint8List> png(ShareSize f, ShareImages images);
  Iterable<GPlayer> get players;
  String get fileName;
}

class _H2H extends ShareTarget {
  const _H2H(this.d);
  final H2HData d;
  @override CustomPainter painter(ShareImages i) => H2HSharePainter(d, images: i);
  @override Future<Uint8List> png(ShareSize f, ShareImages i) => H2HSharePainter.toPng(d, f, images: i);
  @override Iterable<GPlayer> get players => [d.me.player, d.other.player];
  @override String get fileName => 'plobby_h2h_${d.other.player.first.toLowerCase()}';
}

class _Wrapped extends ShareTarget {
  const _Wrapped(this.w);
  final WrappedData w;
  @override CustomPainter painter(ShareImages i) => WrappedSharePainter(w, images: i);
  @override Future<Uint8List> png(ShareSize f, ShareImages i) => WrappedSharePainter.toPng(w, f);
  @override Iterable<GPlayer> get players => const [];
  @override String get fileName => 'plobby_wrapped_${w.start.year}${w.kind == WrappedKind.month ? '_${w.start.month}' : ''}';
}

class _Ranking extends ShareTarget {
  const _Ranking(this.r, this.m);
  final RankingData r;
  final RankMetric m;
  @override CustomPainter painter(ShareImages i) => RankingSharePainter(r, m, images: i);
  @override Future<Uint8List> png(ShareSize f, ShareImages i) => RankingSharePainter.toPng(r, m, f, images: i);
  @override Iterable<GPlayer> get players => r.ranked(m).take(3).map((x) => x.player);
  @override String get fileName => 'plobby_ranking_${r.period.name}';
}

Future<void> showShareImageSheet(BuildContext context, ShareTarget target) => showPlobbySheet<void>(context, (_) => _ShareSheet(target: target));

class _ShareSheet extends StatefulWidget {
  const _ShareSheet({required this.target});
  final ShareTarget target;
  @override
  State<_ShareSheet> createState() => _ShareSheetState();
}

class _ShareSheetState extends State<_ShareSheet> {
  var _fmt = ShareSize.story;
  ShareImages _images = const {};
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    loadShareImages(widget.target.players).then((i) { if (mounted && i.isNotEmpty) setState(() => _images = i); });
  }

  Future<void> _run(Future<void> Function(Uint8List) job, String ok) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final png = await widget.target.png(_fmt, _images);
      await job(png);
      HapticFeedback.lightImpact();
      if (mounted) showPlobbySnack(context, ok);
    } catch (_) {
      if (mounted) showPlobbySnack(context, 'No se pudo generar la imagen. Inténtalo de nuevo.', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = _fmt.size, svc = ShareService(), name = '${widget.target.fileName}_${_fmt.name}';
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SheetHeader(title: 'Compartir'),
      SlidingTabs(labels: const ['Story 9:16', 'Publicación 4:5'], index: _fmt.index, onChanged: (i) => setState(() => _fmt = ShareSize.values[i])),
      const SizedBox(height: 14),
      Center(child: ConstrainedBox(constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .45),
          child: AspectRatio(aspectRatio: size.width / size.height, child: ClipRRect(borderRadius: AppRadius.rMd,
              child: FittedBox(child: SizedBox.fromSize(size: size, child: RepaintBoundary(child: CustomPaint(painter: widget.target.painter(_images))))))))),
      const SizedBox(height: 16),
      Row(children: [
        Expanded(child: PlobbyButton(label: 'Guardar', kind: PlobbyButtonKind.outline, icon: PlobbyIcons.archive,
            onPressed: _busy ? null : () => _run((p) => svc.saveToGallery(p, name), 'Imagen guardada en tu galería'))),
        const SizedBox(width: 10),
        Expanded(child: PlobbyButton(label: 'Compartir', icon: PlobbyIcons.share, busy: _busy,
            onPressed: _busy ? null : () => _run((p) => svc.share(p, name), 'Listo para compartir'))),
      ]),
    ]);
  }
}
