// lib/pages/rep_profile_page.dart
import 'package:flutter/material.dart';
import '../api/client.dart';
import '../l10n/app_localizations.dart';
import '../services/app_prefs_scope.dart';
import '../utils/lang_utils.dart';

extension _L10nX on BuildContext {
  AppLocalizations get t => AppLocalizations.of(this)!;
}

class RepProfilePage extends StatefulWidget {
  final ApiClient api;

  /// NEU: Wenn true, wird der Passwort-Bereich ausgeblendet
  final bool hidePasswordSection;

  const RepProfilePage({
    super.key,
    required this.api,
    this.hidePasswordSection = false,
  });

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
  String _lang = 'de';

  // Passwort ändern
  final _pwOld = TextEditingController();
  final _pw1 = TextEditingController();
  final _pw2 = TextEditingController();
  bool _busyPw = false;
  bool _savingProfile = false;

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
      _lang = normalizeLangCode(me.lang.isEmpty ? 'de' : me.lang);

      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) setState(() => _err = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _saveProfile() async {
    if (_savingProfile) return;
    setState(() => _savingProfile = true);
    final t = context.t;

    try {
      final updated = await widget.api.repUpdateProfile(
        firstName: _first.text.trim(),
        lastName: _last.text.trim(),
        region: _region.text.trim(),
        lang: _lang,
      );

      final newLang = normalizeLangCode(updated.lang.isEmpty ? _lang : updated.lang);
      _first.text  = updated.firstName;
      _last.text   = updated.lastName;
      _region.text = updated.region;

      setState(() {
        _me = updated;
        _lang = newLang;
      });

      final prefs = AppPrefsScope.of(context);
      await prefs.setLang(newLang);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t.saved ?? 'Gespeichert.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${t.error ?? 'Fehler'}: $e')),
      );
    } finally {
      if (mounted) setState(() => _savingProfile = false);
    }
  }

  Future<void> _changePassword() async {
    final t = context.t;
    final old = _pwOld.text;
    final a = _pw1.text;
    final b = _pw2.text;

    if (old.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t.old_password_required ?? t.oldPassword)),
      );
      return;
    }

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
      await widget.api.repChangePassword(a, oldPw: old); // setzt ggf. neues Token
      if (!mounted) return;
      _pwOld.clear();
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
    _pwOld.dispose();
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
                    TextFormField(
                      initialValue: email,
                      readOnly: true,
                      decoration: InputDecoration(
                        labelText: t.email,
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: _lang,
                      decoration: InputDecoration(
                        labelText: t.catalog_select_language,
                        border: const OutlineInputBorder(),
                      ),
                      items: supportedLangLocales
                          .map(
                            (loc) => DropdownMenuItem<String>(
                              value: loc.languageCode,
                              child: Text(langNameFor(t, loc.languageCode)),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value == null) return;
                        setState(() => _lang = normalizeLangCode(value));
                      },
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _savingProfile ? null : _saveProfile,
                        icon: _savingProfile
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.save),
                        label: Text(_savingProfile ? t.save : t.save_profile),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Passwort-Bereich nur anzeigen, wenn NICHT ausgeblendet
            if (!widget.hidePasswordSection)
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
                        controller: _pwOld,
                        obscureText: true,
                        decoration: InputDecoration(
                          labelText: t.oldPassword,
                          border: const OutlineInputBorder(),
                        ),
                      ),
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
