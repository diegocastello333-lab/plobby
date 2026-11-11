import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/router/app_router.dart';
import 'core/theme/plobby_theme.dart';

void main() => runApp(const ProviderScope(child: PlobbyApp()));

class PlobbyApp extends StatelessWidget {
  const PlobbyApp({super.key});
  @override
  Widget build(BuildContext context) =>
      MaterialApp.router(title: 'Plobby', theme: buildPlobbyTheme(), routerConfig: appRouter, debugShowCheckedModeBanner: false);
}
