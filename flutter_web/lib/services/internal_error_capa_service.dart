import '../models/capa_report.dart';
import '../models/internal_error_model.dart';

String _formatDate(DateTime date) {
  final iso = date.toIso8601String();
  return iso.split('T').first;
}

String buildInternalErrorReference(InternalError error) {
  final lines = <String>[
    'Quelle: Interner Fehler',
    if (error.errorCode.isNotEmpty) 'Fehlercode: ${error.errorCode}',
    if (error.id.isNotEmpty) 'Interne ID: ${error.id}',
    'Erfasst am: ${_formatDate(error.createdAt)}',
    if (error.createdBy.isNotEmpty) 'Erfasst von: ${error.createdBy}',
    if (error.processArea.isNotEmpty) 'Bereich/Prozess: ${error.processArea}',
    if (error.errorType.isNotEmpty) 'Fehlerart: ${error.errorType}',
    if (error.articleOrProduct.isNotEmpty) 'Artikel/Produkt/Gruppe: ${error.articleOrProduct}',
    if (error.description.isNotEmpty) 'Kurzbeschreibung: ${error.description}',
    if (error.detectedBy.isNotEmpty) 'Entdeckt von: ${error.detectedBy}',
    if (error.customerRelated) 'Kundenbezug: ja',
    if (error.supplierRelated) 'Lieferantenbezug: ja',
    if (error.severity > 0 || error.occurrence > 0)
      'Bewertung: Severity ${error.severity}, Auftreten ${error.occurrence}, '
          'Punkte ${error.points}, Eskalation ${error.escalation}',
    if (error.correctionAction.isNotEmpty) 'Sofortmaßnahme/Containment: ${error.correctionAction}',
    if (error.rootCause.isNotEmpty) 'Ursache (Root Cause): ${error.rootCause}',
    if (error.notes.isNotEmpty) 'Notizen: ${error.notes}',
  ];
  return lines.join('\n');
}

String buildInternalErrorProblem(InternalError error) {
  final lines = <String>[
    'Interner Fehler ${error.errorCode.isNotEmpty ? error.errorCode : error.id}'.trim(),
    if (error.description.isNotEmpty) error.description,
    if (error.severity > 0 || error.occurrence > 0)
      'Bewertung: Severity ${error.severity}, Auftreten ${error.occurrence}, '
          'Punkte ${error.points}, Eskalation ${error.escalation}',
  ];
  return lines.join('\n');
}

String buildInternalErrorCauseSummary(InternalError error) {
  final parts = <String>[];
  if (error.errorType.isNotEmpty) parts.add('Fehlerart: ${error.errorType}');
  if (error.rootCause.isNotEmpty) parts.add('Ursache: ${error.rootCause}');
  if (parts.isEmpty) return '';
  return 'Quelle Interne Fehlererfassung: ${parts.join(' • ')}';
}

CapaReport buildCapaFromInternalError(InternalError error) {
  final resolved = error.recalcDerived();
  final reference = buildInternalErrorReference(resolved);
  return CapaReport(
    title: resolved.description.isNotEmpty
        ? resolved.description
        : (resolved.errorCode.isNotEmpty ? 'Interner Fehler ${resolved.errorCode}' : 'Interner Fehler'),
    responsibleUserId: resolved.createdBy,
    internalErrorId: resolved.id,
    internalErrorCode: resolved.errorCode,
    internalErrorReference: reference,
    sections: CapaSections(
      area: resolved.processArea,
      date: resolved.createdAt,
      product: resolved.articleOrProduct,
      problem: buildInternalErrorProblem(resolved),
      immediateDetails: resolved.correctionAction,
      causeSummary: buildInternalErrorCauseSummary(resolved),
    ),
  );
}
