/// Documentos legales y consentimientos (Seguridad Fase 8). Los textos viven en `assets/legal/<archivo>.md` (dentro de la
/// app, funcionan sin conexión) y en `web/legal/<archivo>.html` (URL pública). La VERSIÓN vigente la decide el servidor
/// (`legal_documents`); cuando sube, la app pide aceptar de nuevo antes de continuar.
enum LegalDoc {
  terms('terms', 'Términos y Condiciones', 'terminos'),
  privacy('privacy', 'Política de Privacidad', 'privacidad'),
  community('community', 'Normas de la comunidad', 'normas-comunidad'),
  cookies('cookies', 'Política de Cookies', 'cookies'),
  legalNotice('legal_notice', 'Aviso Legal', 'aviso-legal'),
  deletion('deletion', 'Eliminación de cuenta y datos', 'eliminar-cuenta');

  const LegalDoc(this.db, this.title, this.slug);
  final String db, title, slug;
  String get asset => 'assets/legal/$slug.md';

  static LegalDoc? bySlug(String s) {
    for (final d in values) {
      if (d.slug == s) return d;
    }
    return null;
  }
}

class PendingLegalDoc {
  const PendingLegalDoc({required this.docType, required this.version, required this.title, this.previouslyAccepted = false});
  final String docType, title;
  final int version;
  /// Ya había aceptado una versión anterior: se le explica que el documento ha cambiado.
  final bool previouslyAccepted;
}

class LegalStatus {
  const LegalStatus({required this.requiredOk, this.pending = const [], this.marketing = false});
  final bool requiredOk;
  final List<PendingLegalDoc> pending;
  final bool marketing;
  bool get isUpdate => pending.isNotEmpty && pending.every((p) => p.previouslyAccepted);

  static LegalStatus fromJson(Map<String, dynamic> j) => LegalStatus(
        requiredOk: j['required_ok'] == true,
        marketing: j['marketing'] == true,
        pending: [
          for (final p in (j['pending'] as List? ?? const []).cast<Map>())
            PendingLegalDoc(docType: p['doc_type'] as String, version: (p['version'] as num).toInt(), title: (p['title'] ?? '') as String,
                previouslyAccepted: p['previously_accepted'] == true),
        ],
      );
}
