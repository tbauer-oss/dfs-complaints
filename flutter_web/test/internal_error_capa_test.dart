import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dfs_customer_complaint/models/internal_error_model.dart';
import 'package:dfs_customer_complaint/pages/internal_error_form.dart';
import 'package:dfs_customer_complaint/services/internal_error_capa_service.dart';

void main() {
  testWidgets('shows CAPA button when escalation requires CAPA', (tester) async {
    final entry = InternalError(
      id: 'ie-1',
      errorCode: 'F24-0001',
      createdBy: 'qa@example.com',
      processArea: 'Produktion',
      description: 'Testfehler',
      detectedBy: 'QA',
      responsiblePerson: 'Lead',
      severity: 5,
      occurrence: 4,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: InternalErrorForm(
            initial: entry,
            canOverrideCapa: true,
            onChanged: (_) {},
          ),
        ),
      ),
    );

    expect(find.text('CAPA erstellen'), findsOneWidget);
  });

  testWidgets('hides CAPA button when not required and no override', (tester) async {
    final entry = InternalError(
      id: 'ie-2',
      errorCode: 'F24-0002',
      createdBy: 'qa@example.com',
      processArea: 'Produktion',
      description: 'Kleinere Abweichung',
      detectedBy: 'QA',
      responsiblePerson: 'Lead',
      severity: 1,
      occurrence: 1,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: InternalErrorForm(
            initial: entry,
            canOverrideCapa: true,
            onChanged: (_) {},
          ),
        ),
      ),
    );

    expect(find.text('CAPA erstellen'), findsNothing);
    expect(find.text('Zur CAPA'), findsNothing);
  });

  testWidgets('shows Zur CAPA when already linked', (tester) async {
    final entry = InternalError(
      id: 'ie-3',
      errorCode: 'F24-0003',
      createdBy: 'qa@example.com',
      processArea: 'Produktion',
      description: 'Fehler mit CAPA',
      detectedBy: 'QA',
      responsiblePerson: 'Lead',
      severity: 1,
      occurrence: 1,
      capaNumber: 'DFS-CAPA-24_0001',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: InternalErrorForm(
            initial: entry,
            canOverrideCapa: true,
            onChanged: (_) {},
          ),
        ),
      ),
    );

    expect(find.text('Zur CAPA'), findsOneWidget);
  });

  test('builds CAPA prefill with internal error metadata', () {
    final entry = InternalError(
      id: 'ie-4',
      errorCode: 'F24-0004',
      createdBy: 'qa@example.com',
      processArea: 'Reinigung',
      errorType: 'Materialfehler',
      articleOrProduct: 'Testartikel',
      description: 'Beschreibung',
      rootCause: 'Ursache',
      detectedBy: 'QA',
      correctionAction: 'Containment',
      severity: 3,
      occurrence: 2,
    );

    final capa = buildCapaFromInternalError(entry);

    expect(capa.internalErrorId, entry.id);
    expect(capa.internalErrorCode, entry.errorCode);
    expect(capa.sections.area, entry.processArea);
    expect(capa.sections.product, entry.articleOrProduct);
    expect(capa.internalErrorReference, contains('Fehlercode: ${entry.errorCode}'));
    expect(capa.internalErrorReference, contains('Ursache (Root Cause): ${entry.rootCause}'));
  });
}
