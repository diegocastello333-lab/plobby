import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import '../../../core/theme/design_tokens.dart';
import '../../../core/theme/plobby_text.dart';
import '../../../core/widgets/plobby_components.dart';
import '../../../core/widgets/state_views.dart';
import '../domain/legal.dart';

/// Muestra un documento legal empaquetado en la app (`assets/legal/<slug>.md`): funciona sin conexión y sin sesión.
/// Formato mínimo: `# título`, `## sección`, `> aviso`, `- lista`, `**negrita**` y párrafos.
class LegalDocScreen extends StatelessWidget {
  const LegalDocScreen({super.key, required this.slug});
  final String slug;

  @override
  Widget build(BuildContext context) {
    final doc = LegalDoc.bySlug(slug);
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Column(children: [
        PlobbyHeaderBar(title: doc?.title ?? 'Documento'),
        Expanded(child: doc == null
            ? const Padding(padding: EdgeInsets.all(20), child: EmptyStateCard(icon: Icons.description_outlined, title: 'Documento no encontrado', text: 'Este enlace no corresponde a ningún documento.'))
            : FutureBuilder<String>(
                future: rootBundle.loadString(doc.asset),
                builder: (_, s) => s.hasData
                    ? SelectionArea(child: ListView(padding: const EdgeInsets.fromLTRB(20, 16, 20, 40), children: renderLegalMarkdown(s.data!)))
                    : s.hasError
                        ? const Padding(padding: EdgeInsets.all(20), child: EmptyStateCard(icon: Icons.description_outlined, title: 'No se pudo abrir', text: 'Inténtalo de nuevo más tarde.'))
                        : const LoadingBlock(),
              )),
      ]),
    );
  }
}

/// Convierte el Markdown mínimo de los documentos legales en widgets (función pura: se prueba sin Flutter Driver).
List<Widget> renderLegalMarkdown(String md) {
  TextSpan rich(String t, TextStyle base) {
    final parts = t.split('**');
    return TextSpan(style: base, children: [
      for (var i = 0; i < parts.length; i++) TextSpan(text: parts[i], style: i.isOdd ? const TextStyle(fontWeight: FontWeight.w700) : null),
    ]);
  }
  final out = <Widget>[];
  for (final raw in md.split('\n')) {
    final line = raw.trimRight();
    if (line.isEmpty) continue;
    if (line.startsWith('# ')) {
      out.add(Padding(padding: const EdgeInsets.only(bottom: 6), child: Semantics(header: true, child: Text(line.substring(2), style: PlobbyText.t1))));
    } else if (line.startsWith('## ')) {
      out.add(Padding(padding: const EdgeInsets.only(top: 18, bottom: 6), child: Semantics(header: true, child: Text(line.substring(3), style: PlobbyText.sec))));
    } else if (line.startsWith('> ')) {
      out.add(Container(
        margin: const EdgeInsets.symmetric(vertical: 8), padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: AppColors.warningSoft, borderRadius: AppRadius.rMd),
        child: Text.rich(rich(line.substring(2), PlobbyText.desc.copyWith(color: AppColors.text))),
      ));
    } else if (line.startsWith('- ')) {
      out.add(Padding(padding: const EdgeInsets.only(left: 4, bottom: 6), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('•  ', style: PlobbyText.desc),
        Expanded(child: Text.rich(rich(line.substring(2), PlobbyText.desc))),
      ])));
    } else {
      out.add(Padding(padding: const EdgeInsets.only(bottom: 10), child: Text.rich(rich(line, PlobbyText.desc))));
    }
  }
  return out;
}
