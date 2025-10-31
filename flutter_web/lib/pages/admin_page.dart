// lib/pages/admin_page.dart
import 'dart:convert';
import 'dart:html' as html;
import 'package:flutter/material.dart';

import '../api/client.dart'; // nur für den Konstruktor-Typ, nicht zwingend genutzt

class AdminPage extends StatefulWidget {
  final ApiClient? api; // optional – wir nutzen primär API_BASE/env
  const AdminPage({super.key, this.api});

  @override
  State<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends State<AdminPage> {
  late final AdminApi _api;
  final _secretCtrl = TextEditingController();

  bool _loadingPending = false;
  bool _loadingUsers = false;
  String? _err;

  List<PendingUser> _pending = [];
  List<ActiveUser> _users = [];

  // Email -> Liste von Tickets (lazy loaded)
  final Map<String, ComplaintsResult> _complaints = {};

  @override
  void initState() {
    super.initState();
    _api = AdminApi();
    // Secret aus localStorage laden
    final s = html.window.localStorage['admin_secret'] ?? '';
    _secretCtrl.text = s;
    _api.setSecret(s);
    // Beim Start gleich laden, wenn Secret vorhanden
    if (s.isNotEmpty) {
      _refreshAll();
    }
  }

  @override
  void dispose() {
    _secretCtrl.dispose();
    super.dispose();
  }

  Future<void> _refreshAll() async {
    setState(() {
      _err = null;
      _loadingPending = true;
      _loadingUsers = true;
    });
    try {
      final p = _api.fetchPending();
      final u = _api.fetchUsers();
      final both = await Future.wait([p, u]);
      if (!mounted) return;
      setState(() {
        _pending = both[0] as List<PendingUser>;
        _users = both[1] as List<ActiveUser>;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _err = '$e');
    } finally {
      if (!mounted) return;
      setState(() {
        _loadingPending = false;
        _loadingUsers = false;
      });
    }
  }

  Future<void> _approve(String email, {String? lang}) async {
    try {
      await _api.approvePending(email, lang: lang);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Freigabe ausgelöst für $email.')),
      );
      await _refreshAll();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Fehler bei Freigabe: $e')),
      );
    }
  }

  Future<void> _reject(String email) async {
    final ok = await _confirm('Anmeldung ablehnen', 'Soll $email wirklich abgelehnt werden?');
    if (ok != true) return;
    try {
      await _api.rejectPending(email);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Eintrag verworfen: $email')),
      );
      await _refreshAll();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Fehler beim Ablehnen: $e')),
      );
    }
  }

  Future<void> _deleteUser(String email) async {
    final ok = await _confirm('Nutzer löschen', 'Soll der aktive Nutzer $email wirklich gelöscht werden?');
    if (ok != true) return;
    try {
      await _api.deleteUser(email);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Nutzer gelöscht: $email')),
      );
      await _refreshAll();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Fehler beim Löschen: $e')),
      );
    }
  }

  Future<bool?> _confirm(String title, String message) async {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('OK')),
        ],
      ),
    );
  }

  Future<void> _loadComplaints(String email) async {
    if (_complaints[email]?.loading == true) return;
    setState(() {
      _complaints[email] = ComplaintsResult.loading();
    });
    try {
      final list = await _api.fetchComplaintsFor(email);
      if (!mounted) return;
      setState(() {
        _complaints[email] = ComplaintsResult.ok(list);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _complaints[email] = ComplaintsResult.err('$e');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Adminbereich – DFS Customer Complaint'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                // Zeile 1: Admin-Secret + Laden
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _secretCtrl,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: 'Admin-Secret (X-Admin-Secret)',
                          border: OutlineInputBorder(),
                        ),
                        onSubmitted: (_) => _applySecret(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: _applySecret,
                      icon: const Icon(Icons.key),
                      label: const Text('Übernehmen & Laden'),
                    ),
                  ],
                ),
                if (_err != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(_err!, style: TextStyle(color: theme.colorScheme.error)),
                  ),

                const SizedBox(height: 16),

                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Pending
                      Expanded(
                        child: Card(
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Icon(Icons.hourglass_top),
                                    const SizedBox(width: 8),
                                    const Text('Pending (Freigabe ausstehend)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                                    const Spacer(),
                                    IconButton(
                                      tooltip: 'Neu laden',
                                      onPressed: _loadingPending ? null : () async {
                                        setState(() => _loadingPending = true);
                                        try {
                                          final list = await _api.fetchPending();
                                          if (!mounted) return;
                                          setState(() => _pending = list);
                                        } catch (e) {
                                          if (!mounted) return;
                                          setState(() => _err = '$e');
                                        } finally {
                                          if (!mounted) return;
                                          setState(() => _loadingPending = false);
                                        }
                                      },
                                      icon: const Icon(Icons.refresh),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                if (_loadingPending) const LinearProgressIndicator(),
                                const SizedBox(height: 8),
                                Expanded(
                                  child: _pending.isEmpty
                                      ? const Center(child: Text('Keine Pending-Anmeldungen.'))
                                      : ListView.separated(
                                          itemCount: _pending.length,
                                          separatorBuilder: (_, __) => const Divider(height: 1),
                                          itemBuilder: (ctx, i) {
                                            final p = _pending[i];
                                            return _PendingTile(
                                              data: p,
                                              onApprove: () => _approve(p.email, lang: p.lang),
                                              onReject: () => _reject(p.email),
                                              onLoadComplaints: () => _loadComplaints(p.email),
                                              complaints: _complaints[p.email],
                                            );
                                          },
                                        ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Users
                      Expanded(
                        child: Card(
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Icon(Icons.people),
                                    const SizedBox(width: 8),
                                    const Text('Aktive Nutzer', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                                    const Spacer(),
                                    IconButton(
                                      tooltip: 'Neu laden',
                                      onPressed: _loadingUsers ? null : () async {
                                        setState(() => _loadingUsers = true);
                                        try {
                                          final list = await _api.fetchUsers();
                                          if (!mounted) return;
                                          setState(() => _users = list);
                                        } catch (e) {
                                          if (!mounted) return;
                                          setState(() => _err = '$e');
                                        } finally {
                                          if (!mounted) return;
                                          setState(() => _loadingUsers = false);
                                        }
                                      },
                                      icon: const Icon(Icons.refresh),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                if (_loadingUsers) const LinearProgressIndicator(),
                                const SizedBox(height: 8),
                                Expanded(
                                  child: _users.isEmpty
                                      ? const Center(child: Text('Keine aktiven Nutzer.'))
                                      : ListView.separated(
                                          itemCount: _users.length,
                                          separatorBuilder: (_, __) => const Divider(height: 1),
                                          itemBuilder: (ctx, i) {
                                            final u = _users[i];
                                            return _UserTile(
                                              data: u,
                                              onDelete: () => _deleteUser(u.email),
                                              onLoadComplaints: () => _loadComplaints(u.email),
                                              complaints: _complaints[u.email],
                                            );
                                          },
                                        ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _applySecret() {
    final s = _secretCtrl.text.trim();
    _api.setSecret(s);
    html.window.localStorage['admin_secret'] = s;
    _refreshAll();
  }
}

// -------------------- UI Widgets --------------------

class _Field extends StatelessWidget {
  final String label;
  final String value;
  const _Field({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).textTheme.bodySmall;
    return Wrap(
      spacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text('$label:', style: muted),
        Text(value.isEmpty ? '—' : value),
      ],
    );
  }
}

class _PendingTile extends StatefulWidget {
  final PendingUser data;
  final VoidCallback onApprove;
  final VoidCallback onReject;
  final VoidCallback onLoadComplaints;
  final ComplaintsResult? complaints;
  const _PendingTile({
    required this.data,
    required this.onApprove,
    required this.onReject,
    required this.onLoadComplaints,
    required this.complaints,
  });

  @override
  State<_PendingTile> createState() => _PendingTileState();
}

class _PendingTileState extends State<_PendingTile> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final d = widget.data;
    return Column(
      children: [
        ListTile(
          title: Text(d.email),
          subtitle: Wrap(
            spacing: 12,
            runSpacing: 4,
            children: [
              _Field(label: 'Firma', value: d.company),
              _Field(label: 'Kontakt', value: d.contact),
              _Field(label: 'Ort', value: '${d.zip} ${d.city}'),
              _Field(label: 'Land', value: d.country),
              _Field(label: 'Telefon', value: d.phone),
              _Field(label: 'Sprache', value: d.lang.toUpperCase()),
              _Field(label: 'Erstellt', value: d.createdAt ?? '—'),
            ],
          ),
          trailing: Wrap(
            spacing: 8,
            children: [
              IconButton(
                tooltip: 'Reklamationen anzeigen',
                onPressed: () {
                  setState(() => _expanded = !_expanded);
                  if (_expanded) widget.onLoadComplaints();
                },
                icon: Icon(_expanded ? Icons.expand_less : Icons.receipt_long),
              ),
              FilledButton(
                onPressed: widget.onApprove,
                child: const Text('Freigeben'),
              ),
              OutlinedButton(
                onPressed: widget.onReject,
                child: const Text('Ablehnen'),
              ),
            ],
          ),
        ),
        if (_expanded)
          _ComplaintsView(email: d.email, result: widget.complaints),
        const Divider(height: 1),
      ],
    );
  }
}

class _UserTile extends StatefulWidget {
  final ActiveUser data;
  final VoidCallback onDelete;
  final VoidCallback onLoadComplaints;
  final ComplaintsResult? complaints;
  const _UserTile({
    required this.data,
    required this.onDelete,
    required this.onLoadComplaints,
    required this.complaints,
  });

  @override
  State<_UserTile> createState() => _UserTileState();
}

class _UserTileState extends State<_UserTile> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final d = widget.data;
    return Column(
      children: [
        ListTile(
          title: Text(d.email),
          subtitle: Wrap(
            spacing: 12,
            runSpacing: 4,
            children: [
              _Field(label: 'Firma', value: d.company),
              _Field(label: 'Kontakt', value: d.contact),
              _Field(label: 'Ort', value: '${d.zip} ${d.city}'),
              _Field(label: 'Land', value: d.country),
              _Field(label: 'Telefon', value: d.phone),
              _Field(label: 'Sprache', value: d.lang.toUpperCase()),
              _Field(label: 'Aktiv seit', value: d.createdAt ?? '—'),
            ],
          ),
          trailing: Wrap(
            spacing: 8,
            children: [
              IconButton(
                tooltip: 'Reklamationen anzeigen',
                onPressed: () {
                  setState(() => _expanded = !_expanded);
                  if (_expanded) widget.onLoadComplaints();
                },
                icon: Icon(_expanded ? Icons.expand_less : Icons.receipt_long),
              ),
              OutlinedButton(
                onPressed: widget.onDelete,
                child: const Text('Löschen'),
              ),
            ],
          ),
        ),
        if (_expanded)
          _ComplaintsView(email: d.email, result: widget.complaints),
        const Divider(height: 1),
      ],
    );
  }
}

class _ComplaintsView extends StatelessWidget {
  final String email;
  final ComplaintsResult? result;
  const _ComplaintsView({required this.email, required this.result});

  @override
  Widget build(BuildContext context) {
    final r = result;
    if (r == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Text('Noch nicht geladen.'),
      );
    }
    if (r.loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: LinearProgressIndicator(),
      );
    }
    if (r.error != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Text('Fehler beim Laden: ${r.error}', style: const TextStyle(color: Colors.red)),
      );
    }
    if (r.tickets.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Text('Keine Reklamationen gefunden.'),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(),
          const Text('Reklamationen (Tickets):', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8, runSpacing: 6,
            children: r.tickets.map((t) => Chip(label: Text(t))).toList(),
          ),
        ],
      ),
    );
  }
}

// -------------------- Models --------------------

class PendingUser {
  final String email;
  final String company;
  final String contact;
  final String street;
  final String zip;
  final String city;
  final String country;
  final String phone;
  final String lang;       // 'de' | 'en' | 'fr' | 'it' | 'es'
  final String? createdAt;

  PendingUser({
    required this.email,
    required this.company,
    required this.contact,
    required this.street,
    required this.zip,
    required this.city,
    required this.country,
    required this.phone,
    required this.lang,
    required this.createdAt,
  });

  factory PendingUser.fromJson(Map<String, dynamic> j) => PendingUser(
    email: j['email'] ?? '',
    company: j['company'] ?? '',
    contact: j['contact'] ?? '',
    street: j['street'] ?? '',
    zip: j['zip'] ?? '',
    city: j['city'] ?? '',
    country: j['country'] ?? '',
    phone: j['phone'] ?? '',
    lang: (j['lang'] ?? 'de').toString(),
    createdAt: j['createdAt']?.toString(),
  );
}

class ActiveUser {
  final String email;
  final String company;
  final String contact;
  final String street;
  final String zip;
  final String city;
  final String country;
  final String phone;
  final String lang;
  final String? createdAt;

  ActiveUser({
    required this.email,
    required this.company,
    required this.contact,
    required this.street,
    required this.zip,
    required this.city,
    required this.country,
    required this.phone,
    required this.lang,
    required this.createdAt,
  });

  factory ActiveUser.fromJson(Map<String, dynamic> j) => ActiveUser(
    email: j['email'] ?? '',
    company: j['company'] ?? '',
    contact: j['contact'] ?? '',
    street: j['street'] ?? '',
    zip: j['zip'] ?? '',
    city: j['city'] ?? '',
    country: j['country'] ?? '',
    phone: j['phone'] ?? '',
    lang: (j['lang'] ?? 'de').toString(),
    createdAt: j['createdAt']?.toString(),
  );
}

class ComplaintsResult {
  final bool loading;
  final String? error;
  final List<String> tickets;
  ComplaintsResult._(this.loading, this.error, this.tickets);
  factory ComplaintsResult.loading() => ComplaintsResult._(true, null, const []);
  factory ComplaintsResult.err(String e) => ComplaintsResult._(false, e, const []);
  factory ComplaintsResult.ok(List<String> t) => ComplaintsResult._(false, null, t);
}

// -------------------- API Helper --------------------

class AdminApi {
  String _secret = '';
  final String _base;

  AdminApi() : _base = const String.fromEnvironment('API_BASE', defaultValue: '') {
    // Fallback, falls nicht über --dart-define gesetzt:
    if (_base.isEmpty) {
      // auf das gleiche Origin zeigen (falls Backend dort erreichbar ist)
      // oder auf ein Default – passe ggf. an
      // ignore: avoid_print
      print('API_BASE (env) leer – nutze window.location.origin als Fallback.');
    }
  }

  void setSecret(String s) {
    _secret = s;
  }

  String get baseUrl {
    final b = const String.fromEnvironment('API_BASE', defaultValue: '');
    if (b.isNotEmpty) return b;
    return html.window.location.origin; // Fallback
  }

  Map<String, String> _headersJson() => {
    'Content-Type': 'application/json; charset=utf-8',
    if (_secret.isNotEmpty) 'X-Admin-Secret': _secret,
  };

  Uri _u(String path, [Map<String, String>? q]) {
    final uri = Uri.parse('$baseUrl$path');
    if (q == null || q.isEmpty) return uri;
    return uri.replace(queryParameters: q);
    }

  // ---- Pending ----
  Future<List<PendingUser>> fetchPending() async {
    final res = await html.HttpRequest.request(
      _u('/api/admin/pending').toString(),
      method: 'GET',
      requestHeaders: _headersJson(),
      withCredentials: true,
    );
    if (res.status != 200) {
      throw 'pending GET: HTTP ${res.status} ${res.responseText}';
    }
    final List data = jsonDecode(res.responseText ?? '[]');
    return data.map((e) => PendingUser.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Approve pending user. Backend soll daraufhin Bestätigungsmail (DE/EN/FR/IT/ES) anhand `lang` versenden.
  Future<void> approvePending(String email, {String? lang}) async {
    final body = jsonEncode({'email': email, 'action': 'approve', if (lang != null) 'lang': lang});
    final res = await html.HttpRequest.request(
      _u('/api/admin/pending').toString(),
      method: 'POST',
      requestHeaders: _headersJson(),
      sendData: body,
      withCredentials: true,
    );
    if (res.status != 200) {
      throw 'pending POST approve: HTTP ${res.status} ${res.responseText}';
    }
  }

  Future<void> rejectPending(String email) async {
    final res = await html.HttpRequest.request(
      _u('/api/admin/pending', {'email': email}).toString(),
      method: 'DELETE',
      requestHeaders: _headersJson(),
      withCredentials: true,
    );
    if (res.status != 200) {
      throw 'pending DELETE: HTTP ${res.status} ${res.responseText}';
    }
  }

  // ---- Users ----
  Future<List<ActiveUser>> fetchUsers() async {
    final res = await html.HttpRequest.request(
      _u('/api/admin/users').toString(),
      method: 'GET',
      requestHeaders: _headersJson(),
      withCredentials: true,
    );
    if (res.status != 200) {
      throw 'users GET: HTTP ${res.status} ${res.responseText}';
    }
    final List data = jsonDecode(res.responseText ?? '[]');
    return data.map((e) => ActiveUser.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> deleteUser(String email) async {
    final res = await html.HttpRequest.request(
      _u('/api/admin/users', {'email': email}).toString(),
      method: 'DELETE',
      requestHeaders: _headersJson(),
      withCredentials: true,
    );
    if (res.status != 200) {
      throw 'users DELETE: HTTP ${res.status} ${res.responseText}';
    }
  }

  // ---- Complaints ----
  Future<List<String>> fetchComplaintsFor(String email) async {
    final res = await html.HttpRequest.request(
      _u('/api/admin/complaints', {'email': email}).toString(),
      method: 'GET',
      requestHeaders: _headersJson(),
      withCredentials: true,
    );
    if (res.status != 200) {
      throw 'complaints GET: HTTP ${res.status} ${res.responseText}';
    }
    final List data = jsonDecode(res.responseText ?? '[]');
    // Expect list of ticket strings like ["DFS_CP000001", ...]
    return data.map((e) => e.toString()).toList();
  }
}
