// lib/pages/account_page.dart
import 'package:flutter/material.dart';
import '../api/client.dart';
import '../l10n/app_localizations.dart';

extension _L10nX on BuildContext {
  AppLocalizations get t => AppLocalizations.of(this)!;
}

class AccountPage extends StatefulWidget {
  final ApiClient api;
  const AccountPage({super.key, required this.api});
  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  bool busy = true;
  String? err;
  Map<String, dynamic>? acc;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { busy = true; err = null; });
    try {
      acc = await widget.api.accountGet();
    } catch (e) {
      final s = e.toString();
      if (s.contains('401')) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(t.session_expired_login_again)),
          );
          Navigator.of(context).pop();
        }
        return;
      }
      err = s;
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final body = () {
      if (busy) return const Center(child: CircularProgressIndicator());
      if (err != null) return Center(child: Text(err!));
      if (acc == null) return const Center(child: Text(t.edit_data));

      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text('E-Mail: ${acc!['email'] ?? ''}'),
              Text('Firma: ${acc!['company'] ?? ''}'),
              Text('Ansprechpartner: ${acc!['contact'] ?? ''}'),
              const SizedBox(height: 16),

              FilledButton.icon(
                icon: const Icon(Icons.edit),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => _AccountEditPage(api: widget.api, initial: acc!),
                  ),
                ).then((_) => _load()),
                label: const Text('Daten ändern'),
              ),
              const SizedBox(height: 12),

              FilledButton.icon(
                icon: const Icon(Icons.lock),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => _PasswordPage(api: widget.api)),
                ),
                label: const Text('Passwort ändern'),
              ),
              const SizedBox(height: 12),

              OutlinedButton.icon(
                icon: const Icon(Icons.delete_forever, color: Colors.red),
                label: const Text('Account löschen', style: TextStyle(color: Colors.red)),
                onPressed: () async {
                  // 1) Sicherheitsabfrage
                  final sure = await showDialog<bool>(
                    context: context,
                    builder: (_) => AlertDialog(
                      title: const Text('Account löschen?'),
                      content: const Text(
                        'Bist du sicher? Dieser Vorgang kann nicht rückgängig gemacht werden.'
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('Abbrechen'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text('Weiter'),
                        ),
                      ],
                    ),
                  );
                  if (sure != true) return;

                  // 2) Passwort-Abfrage
                  final pwd = await showDialog<String>(
                    context: context,
                    builder: (_) {
                      final ctrl = TextEditingController();
                      return AlertDialog(
                        title: const Text('Passwort bestätigen'),
                        content: TextField(
                          controller: ctrl, obscureText: true,
                          decoration: const InputDecoration(labelText: 'Passwort'),
                        ),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Abbrechen')),
                          FilledButton(onPressed: () => Navigator.pop(context, ctrl.text), child: const Text('Account löschen')),
                        ],
                      );
                    },
                  );
                  if (pwd == null || pwd.isEmpty) return;

                  try {
                    // wirft bei Fehler -> catch
                    await widget.api.accountDelete(pwd);

                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Account gelöscht.')),
                    );

                    // Zur Start-/Loginseite zurück
                    Navigator.of(context).popUntil((r) => r.isFirst);
                  } catch (e) {
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Fehler: $e')),
                    );
                  }
                },
              ),
            ],
          ),
        ),
      );
    }();

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Mein Account'),
      ),
      body: body,
    );
  }
}

// ===== Unterseiten =====

class _AccountEditPage extends StatefulWidget {
  final ApiClient api;
  final Map<String, dynamic> initial;
  const _AccountEditPage({required this.api, required this.initial});
  @override
  State<_AccountEditPage> createState() => _AccountEditPageState();
}

class _AccountEditPageState extends State<_AccountEditPage> {
  late final TextEditingController email   =
      TextEditingController(text: widget.initial['email']?.toString() ?? '');
  late final TextEditingController company =
      TextEditingController(text: widget.initial['company']?.toString() ?? '');
  late final TextEditingController contact =
      TextEditingController(text: widget.initial['contact']?.toString() ?? '');
  late final TextEditingController street  =
      TextEditingController(text: widget.initial['street']?.toString() ?? '');
  late final TextEditingController zip     =
      TextEditingController(text: widget.initial['zip']?.toString() ?? '');
  late final TextEditingController city    =
      TextEditingController(text: widget.initial['city']?.toString() ?? '');

  bool busy = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Daten ändern')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              TextField(
                controller: email,
                decoration: const InputDecoration(
                  labelText: 'E-Mail', border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: contact,
                decoration: const InputDecoration(
                  labelText: 'Ansprechpartner', border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: company,
                decoration: const InputDecoration(
                  labelText: 'Firma', border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: street,
                decoration: const InputDecoration(
                  labelText: 'Adresse', border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: zip,
                      decoration: const InputDecoration(
                        labelText: 'PLZ', border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: city,
                      decoration: const InputDecoration(
                        labelText: 'Ort', border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  FilledButton(
                    onPressed: busy ? null : () async {
                      setState(() => busy = true);
                      try {
                        await widget.api.accountUpdate({
                          'email':   email.text.trim(),
                          'contact': contact.text.trim(),
                          'company': company.text.trim(),
                          'street':  street.text.trim(),
                          'zip':     zip.text.trim(),
                          'city':    city.text.trim(),
                        });
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Gespeichert.')),
                        );
                        Navigator.of(context).pop();
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Fehler: $e')),
                          );
                        }
                      } finally {
                        if (mounted) setState(() => busy = false);
                      }
                    },
                    child: busy
                        ? const SizedBox(
                            width: 18, height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Speichern'),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Abbrechen'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PasswordPage extends StatefulWidget {
  final ApiClient api;
  const _PasswordPage({required this.api});
  @override
  State<_PasswordPage> createState() => _PasswordPageState();
}

class _PasswordPageState extends State<_PasswordPage> {
  final oldPw = TextEditingController();
  final newPw1 = TextEditingController();
  final newPw2 = TextEditingController();
  bool busy = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Passwort ändern')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              TextField(
                controller: oldPw, obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Altes Passwort', border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: newPw1, obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Neues Passwort', border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: newPw2, obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Neues Passwort (Wdh.)', border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  FilledButton(
                    onPressed: busy ? null : () async {
                      if (newPw1.text != newPw2.text) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Passwörter stimmen nicht überein.')),
                        );
                        return;
                      }
                      setState(() => busy = true);
                      try {
                        await widget.api.accountChangePassword(
                          oldPw.text, newPw1.text,
                        );
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Passwort geändert.')),
                        );
                        Navigator.of(context).pop();
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Fehler: $e')),
                          );
                        }
                      } finally {
                        if (mounted) setState(() => busy = false);
                      }
                    },
                    child: busy
                        ? const SizedBox(
                            width: 18, height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Speichern'),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Abbrechen'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
