// lib/pages/rep_profile_page.dart
import 'package:flutter/material.dart';
import '../api/client.dart';
import '../l10n/app_localizations.dart';

extension _L10nX on BuildContext {
  AppLocalizations get t => AppLocalizations.of(this)!;
}

class RepProfilePage extends StatefulWidget {
  final ApiClient api;
  const RepProfilePage({super.key, required this.api});

  @override
  State<RepProfilePage> createState() => _RepProfilePageState();
}

class _RepProfilePageState extends State<RepProfilePage> {
  RepMe? _me;
  bool _loading = true;
  String? _err;

  // Profileingaben
  final _first  = TextEditingController();
  final _last   = TextEditingController();
  final _region = TextEditingController();

  // Passwort ändern
  final _pw1 = TextEditingController();
  final _pw2 = TextEditingController();
  bool _busyPw = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _err = null;
    });
    try {
      final m = await widget.api.repMe();          // Map<String, dynamic>
      final me = RepMe.fromJson(m);                // dein Modell
      _me = me;

      // Felder setzen – null-safe
      _first.text  = me.firstName;
      _last.text   = me.lastName;
      _region.text = me.region;

      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) setState(() => _err = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // Platzhalter – bis Server-Endpoint existiert.
  Future<void> _saveProfile() async {
    if (_me == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.t.profile_not_active)),
    );

    // Wenn /api/rep/update und ApiClient.repUpdateProfile(...) existieren:
    // try {
    //   await widget.api.repUpdateProfile({
    //     'firstName': _first.text.trim(),
    //     'lastName' : _last.text.trim(),
    //     'region'   : _region.text.trim(),
    //   });
    //   if (!mounted) return;
    //   ScaffoldMessenger.of(context).showSnackBar(
    //     SnackBar(content: Text(context.t.saved ?? 'Gespeichert.')),
    //   );
    //   await _load();
    // } catch (e) {
    //   if (!mounted) return;
    //   ScaffoldMessenger.of(context).showSnackBar(
    //     SnackBar(content: Text(context.t.password_set_failed('$e'))),
    //   );
    // }
  }

  Future<void> _changePassword() async {
    final t = context.t;
    final a = _pw1.text;
    final b = _pw2.text;

    if (a.isEmpty || b.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t.password_both_required)),
      );
      return;
    }
    if (a != b) {
      // nutzt bestehenden Key aus deinem Projekt (Account-Seite)
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t.passwordsDontMatch ?? t.password_mismatch)),
      );
      return;
    }
    if (a.length < 8) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t.password_min_length)),
      );
      return;
    }

    setState(() => _busyPw = true);
    try {
      await widget.api.repChangePassword(a); // setzt ggf. neues Token
      if (!mounted) return;
      _pw1.clear();
      _pw2.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t.password_changed)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t.password_set_failed('$e'))),
      );
    } finally {
      if (mounted) setState(() => _busyPw = false);
    }
  }

  @override
  void dispose() {
    _first.dispose();
    _last.dispose();
    _region.dispose();
    _pw1.dispose();
    _pw2.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final title = Text(t.profilePW);

    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: title),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_err != null) {
      return Scaffold(
        appBar: AppBar(title: title),
        body: Center(child: Text(_err!, style: const TextStyle(color: Colors.red))),
      );
    }

    final email = _me?.email ?? '';

    return Scaffold(
      appBar: AppBar(title: title),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Card(
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t.myData, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _first,
                      decoration: InputDecoration(
                        labelText: t.first_name,
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _last,
                      decoration: InputDecoration(
                        labelText: t.last_name,
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _region,
                      decoration: InputDecoration(
                        labelText: t.region,
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      enabled: false,
                      controller: TextEditingController(text: email),
                      decoration: InputDecoration(
                        labelText: t.email,
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _saveProfile, // aktuell Info-Toast
                        icon: const Icon(Icons.save),
                        label: Text(t.save_profile),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t.changePassword, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _pw1,
                      obscureText: true,
                      decoration: InputDecoration(
                        labelText: t.new_password_min8,
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _pw2,
                      obscureText: true,
                      decoration: InputDecoration(
                        labelText: t.new_password_repeat_label,
                        border: const OutlineInputBorder(),
                      ),
                      onSubmitted: (_) => _busyPw ? null : _changePassword(),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _busyPw ? null : _changePassword,
                        icon: _busyPw
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.key),
                        label: Text(t.save),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
