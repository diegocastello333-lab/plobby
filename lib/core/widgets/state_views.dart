import 'package:flutter/material.dart';
import '../theme/design_tokens.dart';

/// Estados vacío / error / carga comunes (mismos textos y jerarquía que el prototipo: icono, título, texto y acciones).
class EmptyStateCard extends StatelessWidget {
  const EmptyStateCard({super.key, required this.icon, required this.title, required this.text, this.primary, this.onPrimary, this.secondary, this.onSecondary});
  final IconData icon; final String title, text; final String? primary, secondary; final VoidCallback? onPrimary, onSecondary;
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity, padding: const EdgeInsets.fromLTRB(20, 28, 20, 22),
        decoration: const BoxDecoration(color: AppColors.surface, borderRadius: AppRadius.rLg, boxShadow: AppShadows.card),
        child: Column(children: [
          Container(width: 72, height: 72, decoration: const BoxDecoration(color: AppColors.surfaceSunken, shape: BoxShape.circle), child: Icon(icon, size: 34, color: AppColors.ink400)),
          const SizedBox(height: 14),
          Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(text, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textMuted, height: 1.4)),
          if (primary != null || secondary != null) const SizedBox(height: 18),
          if (primary != null) SizedBox(width: double.infinity, child: FilledButton(onPressed: onPrimary, child: Text(primary!))),
          if (secondary != null) ...[const SizedBox(height: 8), SizedBox(width: double.infinity, child: OutlinedButton(onPressed: onSecondary, child: Text(secondary!)))],
        ]),
      );
}

/// Error de red con «Reintentar» (prototipo: «No se pudo cargar · Parece que no hay conexión…»).
class ErrorStateCard extends StatelessWidget {
  const ErrorStateCard({super.key, this.title = 'No se pudo cargar', this.message = 'Parece que no hay conexión. Revisa tu red e inténtalo de nuevo.', required this.onRetry});
  final String title, message; final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Column(children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: const BoxDecoration(color: AppColors.dangerSoft, borderRadius: AppRadius.rMd),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.wifi_off_rounded, color: AppColors.danger),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.danger)),
              const SizedBox(height: 2),
              Text(message, style: const TextStyle(color: AppColors.danger)),
            ])),
          ]),
        ),
        const SizedBox(height: 10),
        SizedBox(width: double.infinity, child: OutlinedButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('Reintentar'))),
      ]);
}

/// Bloque gris de carga con la altura final (evita saltos de layout).
class LoadingBlock extends StatelessWidget {
  const LoadingBlock({super.key, this.height = 96, this.radius = AppRadius.lg});
  final double height, radius;
  @override
  Widget build(BuildContext context) => Semantics(label: 'Cargando', child: Container(height: height, decoration: BoxDecoration(color: AppColors.surfaceSunken, borderRadius: BorderRadius.circular(radius))));
}

void showPlobbySnack(BuildContext context, String text, {bool error = false}) => ScaffoldMessenger.of(context)
  ..hideCurrentSnackBar()
  ..showSnackBar(SnackBar(content: Text(text), backgroundColor: error ? AppColors.danger : AppColors.inverse, behavior: SnackBarBehavior.floating));
