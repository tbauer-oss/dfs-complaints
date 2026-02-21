import 'package:flutter/material.dart';

import '../../api/client.dart';
import '../../services/regulatory/regulatory_api.dart';

class RegulatorySyncPage extends StatefulWidget {
  final ApiClient api;
  const RegulatorySyncPage({super.key, required this.api});

  @override
  State<RegulatorySyncPage> createState() => _RegulatorySyncPageState();
}

class _RegulatorySyncPageState extends State<RegulatorySyncPage> {
  late final RegulatoryApi _regulatory = RegulatoryApi(widget.api);
  List<Map<String, dynamic>> _docs = const [];
  Map<String, dynamic>? _status;
  Map<String, dynamic>? _diff;
  String? _slug;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _loadDocs();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _loadDocs() async {
    await _run(() async {
      final docs = await _regulatory.getDocs();
      _docs = docs;
      _slug = docs.isNotEmpty ? docs.first['slug']?.toString() : null;
      if (_slug != null) {
        _status = await _regulatory.getStatus(_slug!);
      }
    });
  }

  Future<void> _syncCheck() async {
    if (_slug == null) return;
    await _run(() async {
      _status = await _regulatory.getStatus(_slug!);
      _diff = await _regulatory.getDiff(_slug!);
    });
  }

  Future<void> _apply() async {
    if (_slug == null || _diff == null) return;
    await _run(() async {
      await _regulatory.apply(
        _slug!,
        _diff!['sync_token']?.toString() ?? '',
      );
      _status = await _regulatory.getStatus(_slug!);
    });
  }

  @override
  Widget build(BuildContext context) {
    final changes = (_diff?['changes'] as List<dynamic>? ?? const []);
    final counts = (_diff?['counts'] as Map?)?.cast<String, dynamic>() ?? const {};
    final total = (counts['total'] as num?)?.toInt() ??
        ((counts['added'] as num?)?.toInt() ?? 0) +
            ((counts['removed'] as num?)?.toInt() ?? 0) +
            ((counts['modified'] as num?)?.toInt() ?? 0);
    return Scaffold(
      appBar: AppBar(title: const Text('Regulatory Sync')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DropdownButton<String>(
              value: _slug,
              hint: const Text('Dokument wählen'),
              items: _docs
                  .map((d) => DropdownMenuItem(value: d['slug']?.toString(), child: Text(d['title']?.toString() ?? d['slug'].toString())))
                  .toList(),
              onChanged: _busy
                  ? null
                  : (value) async {
                      setState(() => _slug = value);
                      if (value != null) {
                        await _run(() async => _status = await _regulatory.getStatus(value));
                      }
                    },
            ),
            const SizedBox(height: 12),
            Text('Stand: ${_status?['current_version']?['version_label'] ?? '—'}'),
            const SizedBox(height: 12),
            Row(
              children: [
                ElevatedButton(onPressed: _busy ? null : _syncCheck, child: const Text('Synchronisieren')),
                const SizedBox(width: 8),
                ElevatedButton(onPressed: _busy || (_diff?['has_update'] != true) ? null : _apply, child: const Text('Änderungen übernehmen')),
              ],
            ),
            if (_diff != null) ...[
              const SizedBox(height: 12),
              Text(total > 0 ? 'Änderungsprotokoll' : 'Keine inhaltlichen Änderungen erkannt.'),
              Text('Added: ${counts['added'] ?? 0}, Removed: ${counts['removed'] ?? 0}, Modified: ${counts['modified'] ?? 0}'),
            ],
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                itemCount: changes.length,
                itemBuilder: (_, index) {
                  final row = (changes[index] as Map).cast<String, dynamic>();
                  return ListTile(
                    dense: true,
                    title: Text(row['section_key']?.toString() ?? ''),
                    subtitle: Text('${row['section_type'] ?? ''} • ${row['change_type'] ?? ''}'),
                  );
                },
              ),
            ),
            if (_error != null) Text(_error!, style: const TextStyle(color: Colors.red)),
          ],
        ),
      ),
    );
  }
}
