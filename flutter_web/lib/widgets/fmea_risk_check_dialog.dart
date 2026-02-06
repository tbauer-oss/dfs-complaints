import 'package:collection/collection.dart';
import 'package:flutter/material.dart';

import '../api/client.dart';
import '../models/dfs_product.dart';
import '../models/fmea.dart';
import '../pages/admin_fmea_page.dart';
import '../services/product_lookup.dart';
import 'skeletons.dart';

class FmeaRiskMatch {
  final FmeaRiskEntry entry;
  final bool hazardMatch;
  final bool situationMatch;
  final bool causeMatch;

  const FmeaRiskMatch({
    required this.entry,
    this.hazardMatch = false,
    this.situationMatch = false,
    this.causeMatch = false,
  });

  bool get anyMatch => hazardMatch || situationMatch || causeMatch;
}

class _FmeaLookupResult {
  final DfsProduct? product;
  final String? mdrTd;
  final FmeaRecord? fmea;
  final List<FmeaRiskMatch> matches;
  final String? error;

  const _FmeaLookupResult({
    this.product,
    this.mdrTd,
    this.fmea,
    this.matches = const [],
    this.error,
  });
}

String _normalize(String? value) {
  if (value == null) return '';
  final cleaned = value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9äöüß ]', caseSensitive: false), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  return cleaned;
}

bool _matchesText(String source, String query) {
  final a = _normalize(source);
  final b = _normalize(query);
  if (a.isEmpty || b.isEmpty) return false;
  return a == b || a.contains(b) || b.contains(a);
}

List<FmeaRiskMatch> _buildMatches(FmeaRecord fmea, List<String> clues) {
  final usefulClues = clues.map(_normalize).where((e) => e.isNotEmpty).toList();
  bool check(String field) => usefulClues.any((c) => _matchesText(field, c));

  return fmea.risks.map((r) {
    final hazard = check(r.hazard);
    final situation = check(r.hazardSituation);
    final cause = check(r.causes);
    return FmeaRiskMatch(entry: r, hazardMatch: hazard, situationMatch: situation, causeMatch: cause);
  }).where((m) => m.anyMatch).toList();
}

Future<_FmeaLookupResult> _resolveFmea({
  required ApiClient api,
  required ProductLookup productLookup,
  required String articleNumber,
  required List<String> clues,
}) async {
  if (!productLookup.hasProducts) {
    await productLookup.loadProducts();
  }
  final product = productLookup.byArticle(articleNumber.trim());
  if (product == null) {
    return const _FmeaLookupResult(error: 'Kein Artikel in der Artikelliste gefunden.');
  }
  final mdrTd = product.tdNumberAndName.trim();
  if (mdrTd.isEmpty || !mdrTd.toLowerCase().startsWith('mdr-td')) {
    return _FmeaLookupResult(
      product: product,
      error: 'Für diesen Artikel ist keine MDR-TD hinterlegt.',
    );
  }

  final fmeas = await api.adminFmeas();
  final fmea = fmeas.firstWhereOrNull((f) => _normalize(f.mdrTd) == _normalize(mdrTd));
  if (fmea == null) {
    return _FmeaLookupResult(
      product: product,
      mdrTd: mdrTd,
      error: 'Keine FMEA für $mdrTd gefunden.',
    );
  }

  final matches = _buildMatches(fmea, clues);
  return _FmeaLookupResult(
    product: product,
    mdrTd: mdrTd,
    fmea: fmea,
    matches: matches,
  );
}

Future<void> openFmeaRiskCheckDialog({
  required BuildContext context,
  required ApiClient api,
  required ProductLookup productLookup,
  required String articleNumber,
  required List<String> clues,
  bool canEdit = false,
}) async {
  if (articleNumber.trim().isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Bitte zuerst einen betroffenen Artikel erfassen.')),
    );
    return;
  }

  final future = _resolveFmea(api: api, productLookup: productLookup, articleNumber: articleNumber, clues: clues);

  await showDialog(
    context: context,
    builder: (ctx) {
      return FutureBuilder<_FmeaLookupResult>(
        future: future,
        builder: (ctx, snapshot) {
          if (!snapshot.hasData) {
            return const AlertDialog(
              title: Text('FMEA prüfen'),
              content: SizedBox(height: 80, child: SkeletonTextBlock(lines: 3)),
            );
          }
          final data = snapshot.data!;
          final productLabel = data.product?.productName ?? '';
          return AlertDialog(
            title: const Text('FMEA Risk-Check'),
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (productLabel.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(productLabel, style: Theme.of(ctx).textTheme.titleMedium),
                    ),
                  if (data.mdrTd != null)
                    Chip(label: Text('MDR-TD: ${data.mdrTd}')),
                  if (data.error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline, color: Colors.red),
                          const SizedBox(width: 8),
                          Expanded(child: Text(data.error!)),
                        ],
                      ),
                    ),
                  if (data.error == null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        data.matches.isEmpty
                            ? 'Keine passenden Gefährdungen gefunden.'
                            : 'Gefundene Übereinstimmungen:',
                        style: Theme.of(ctx).textTheme.titleMedium,
                      ),
                    ),
                  if (data.matches.isNotEmpty)
                    SizedBox(
                      height: 220,
                      child: ListView.builder(
                        itemCount: data.matches.length,
                        itemBuilder: (ctx, idx) {
                          final m = data.matches[idx];
                          return ListTile(
                            dense: true,
                            title: Text(m.entry.hazard.isEmpty ? 'Risiko ${m.entry.riskNumber}' : m.entry.hazard),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (m.entry.hazardSituation.isNotEmpty)
                                  Text('Situation: ${m.entry.hazardSituation}'),
                                if (m.entry.causes.isNotEmpty) Text('Ursache: ${m.entry.causes}'),
                              ],
                            ),
                            trailing: Wrap(
                              spacing: 4,
                              children: [
                                if (m.hazardMatch) const Chip(label: Text('Gefährdung')),
                                if (m.situationMatch) const Chip(label: Text('Situation')),
                                if (m.causeMatch) const Chip(label: Text('Ursache')),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Schließen')),
              if (data.mdrTd != null)
                TextButton.icon(
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => AdminFmeaPage(
                          api: api,
                          canEdit: canEdit,
                          initialMdrTd: data.mdrTd,
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.auto_awesome_mosaic_outlined),
                  label: Text(data.matches.isEmpty ? 'Neue FMEA-Gefahr anlegen' : 'FMEA öffnen'),
                ),
            ],
          );
        },
      );
    },
  );
}
