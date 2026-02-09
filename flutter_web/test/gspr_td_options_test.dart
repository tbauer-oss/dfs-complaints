import 'package:flutter_test/flutter_test.dart';
import 'package:dfs_customer_complaint/models/gspr.dart';

void main() {
  group('GSPR TD helpers', () {
    test('normalizes TD labels and deduplicates', () {
      final raw = [
        'MDR-TD4 - PreciCut',
        'MDR-TD4 – PreciCut',
        '  MDR-TD4-PreciCut  ',
        'MDR-TD2 - Knochenfräser',
        'OTHER',
      ];
      final result = dedupeAndSortGsprTdLabels(raw);
      expect(result, [
        'MDR-TD2 – Knochenfräser',
        'MDR-TD4 – PreciCut',
      ]);
    });

    test('sorts by numeric TD index', () {
      final raw = [
        'MDR-TD10 - Ten',
        'MDR-TD2 - Two',
        'MDR-TD1 - One',
      ];
      final result = dedupeAndSortGsprTdLabels(raw);
      expect(result, [
        'MDR-TD1 – One',
        'MDR-TD2 – Two',
        'MDR-TD10 – Ten',
      ]);
    });
  });
}
