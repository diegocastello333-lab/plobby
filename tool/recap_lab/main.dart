// Laboratorio (no se incluye en la app): pinta la vista previa de Share Match con los datos del partido real para
// comprobar en un navegador que se ve. `flutter build web -t tool/recap_lab/main.dart`.
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:plobby/core/theme/design_tokens.dart';
import 'package:plobby/core/theme/plobby_theme.dart';
import 'package:plobby/features/match_recap/application/recap_providers.dart';
import 'package:plobby/features/match_recap/presentation/share_match_screen.dart';
import 'package:plobby/core/net/pixel_decode.dart';
import 'package:plobby/features/match_recap/application/recap_painter.dart';
import 'package:plobby/features/match_recap/domain/recap_data.dart';

void main() {
  // ?screen=1 monta la PANTALLA real de Share Match (vista previa incluida) con los datos del partido real.
  if (Uri.base.queryParameters['screen'] == '1') {
    AppColors.isDark = true;
    runApp(ProviderScope(overrides: [recapDataProvider.overrideWith((ref, id) => AsyncValue.data(_LabState.real))],
        child: MaterialApp(debugShowCheckedModeBanner: false, theme: buildPlobbyTheme(), home: const ShareMatchScreen(matchId: 'm'))));
    return;
  }
  runApp(const MaterialApp(debugShowCheckedModeBanner: false, home: _Lab()));
}

class _Lab extends StatefulWidget {
  const _Lab();
  @override
  State<_Lab> createState() => _LabState();
}

class _LabState extends State<_Lab> {
  RecapImages images = const {};
  var tpl = RecapTemplate.result;
  static const w = [RecapPlayer(id: '48eee197-dc9e-4f4f-bddd-b45f8b88c3a0', name: 'Diego Castello', avatarUrl: 'x'), RecapPlayer(id: 'b', name: 'Antonio Cuesta', avatarUrl: 'x')];
  static const o = [RecapPlayer(id: 'c', name: 'Lucía Martín', avatarUrl: 'x'), RecapPlayer(id: 'e', name: 'Javi Ortega', avatarUrl: 'x')];
  static final real = RecapData(matchId: 'm', winners: w, opponents: o, sets: const [(6, 3), (6, 4)], winnerIsTeam1: true, playedAt: DateTime(2026, 11, 16, 14, 6),
      club: 'Club La Moraleja', isLeague: false, durationSeconds: 10, eloDelta: 16, eloBefore: 1466, eloAfter: 1482,
      stats: const RecapUserStats(played: 1, winRate: 100, streak: 1), userWon: true, userName: 'Diego Castello');
  RecapData get d => real;

  @override
  void initState() {
    super.initState();
    if (Uri.base.queryParameters['photos'] != '0') {
      rootBundle.load('assets/images/banners/banner1/dia.webp').then((b) async {
        final img = (await decodeToPixels(b.buffer.asUint8List(), 400))!;   // misma vía que la web real
        setState(() => images = {for (final p in [...w, ...o]) p.id: img});
      });
    }
    tpl = RecapTemplate.values.firstWhere((t) => t.name == Uri.base.queryParameters['tpl'], orElse: () => RecapTemplate.result);
  }

  @override
  Widget build(BuildContext context) {
    final f = RecapFormat.story, h = MediaQuery.sizeOf(context).height * .5;
    return Scaffold(backgroundColor: const Color(0xFF0D110F), body: Center(child: SizedBox(height: h, width: h * f.width / f.height,
        child: ClipRRect(borderRadius: BorderRadius.circular(16), child: RepaintBoundary(child: CustomPaint(painter: RecapPainter(d, tpl, f, images: images)))))));
  }
}
