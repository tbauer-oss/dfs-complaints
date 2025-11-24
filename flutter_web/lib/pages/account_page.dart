// lib/pages/account_page.dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_saver/file_saver.dart';
import 'package:intl/intl.dart';
import '../api/client.dart';
import '../data/country_geography.dart';
import '../l10n/app_localizations.dart';
import '../models/country.dart';
import '../services/app_prefs_scope.dart';
import '../utils/lang_utils.dart';
import '../widgets/legal_footer.dart';
import '../widgets/password_field.dart';

extension _L10nX on BuildContext {
  AppLocalizations get t => AppLocalizations.of(this)!;
}

// kleine Helper für "value or dash"
String _val(Object? v, [String dash = '-' ]) {
  final s = (v ?? '').toString().trim();
  return s.isEmpty ? dash : s;
}

String _langDisplay(BuildContext context, Object? value) {
  final code = value == null ? null : value.toString();
  return langNameFor(AppLocalizations.of(context), normalizeLangCode(code));
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
  bool _exportBusy = false;

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
            SnackBar(content: Text(context.t.session_expired_login_again)),
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

  Future<void> _handleExport() async {
    if (_exportBusy) return;
    setState(() => _exportBusy = true);
    try {
      final data = await widget.api.accountExport();
      if (!mounted) return;
      final pretty = const JsonEncoder.withIndent('  ').convert(data);
      final rootContext = context;
      await showDialog<void>(
        context: rootContext,
        builder: (dialogCtx) => AlertDialog(
          title: Text(dialogCtx.t.dataExportTitle ?? 'Datenexport (DSGVO)'),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480, maxHeight: 360),
            child: Scrollbar(
              thumbVisibility: true,
              child: SingleChildScrollView(
                child: SelectableText(
                  pretty,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => _downloadExportFile(pretty, rootContext),
              child: Text(dialogCtx.t.dataExportDownloadTxt ?? 'Als TXT herunterladen'),
            ),
            TextButton(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: pretty));
                if (!mounted) return;
                ScaffoldMessenger.of(rootContext).showSnackBar(
                  SnackBar(content: Text(rootContext.t.copied ?? 'In Zwischenablage kopiert.')),
                );
              },
              child: Text(dialogCtx.t.copy ?? 'Kopieren'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: Text(dialogCtx.t.close ?? 'Schließen'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${context.t.error ?? 'Fehler'}: $e')),
      );
    } finally {
      if (mounted) setState(() => _exportBusy = false);
    }
  }

  String _exportFileName() {
    final ts = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    return 'dfs_datenexport_$ts';
  }

  Future<void> _downloadExportFile(String pretty, BuildContext rootContext) async {
    try {
      final bytes = Uint8List.fromList(utf8.encode(pretty));
      await FileSaver.instance.saveFile(
        name: _exportFileName(),
        bytes: bytes,
        ext: 'txt',
        mimeType: MimeType.text,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(rootContext).showSnackBar(
        SnackBar(
          content: Text(
            rootContext.t.dataExportDownloaded ?? 'TXT-Datei wurde heruntergeladen.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(rootContext).showSnackBar(
        SnackBar(content: Text('${rootContext.t.error ?? 'Fehler'}: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;

    final body = () {
      if (busy) return const Center(child: CircularProgressIndicator());
      if (err != null) return Center(child: Text(err!));
      // FIX: falscher Key (früher: t.editdata) -> nutze vorhandenen Key oder Fallback
      if (acc == null) return Center(child: Text(t.noDataFound ?? 'Keine Daten gefunden.'));

      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // evtl. Kurz-Variable, damit wir nicht ständig acc! schreiben
              Text('E-Mail: ${_val(acc!['email'], '')}'),
              Text('${t.company}: ${_val(acc!['company'])}'),
              Text('${t.contact_person}: ${_val(acc!['contact'])}'),
              Text('${t.country_label ?? 'Land'}: ${_val(acc!['country'])}'),
              Text('${t.catalog_select_language}: ${_langDisplay(context, acc!['lang'])}'),

              // NEU: Kundennummer (nur Anzeige)
              // Backend liefert "customerNumber" (oder optional "customer_no")
              Builder(
                builder: (_) {
                  final raw = (acc!['customerNumber'] ?? acc!['customer_no'] ?? '').toString().trim();
                  if (raw.isEmpty) {
                    // Wenn du bei "nicht hinterlegt" NICHTS anzeigen willst:
                    // return const SizedBox.shrink();
                    return Text(
                      '${t.customer_number_label}: -',
                    );
                  }
                  return Text(
                    '${t.customer_number_label}: $raw',
                  );
                },
              ),

              const SizedBox(height: 16),

              FilledButton.icon(
                icon: const Icon(Icons.edit),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => _AccountEditPage(api: widget.api, initial: acc!),
                  ),
                ).then((_) => _load()),
                label: Text(t.editData),
              ),
              const SizedBox(height: 12),

              FilledButton.icon(
                icon: const Icon(Icons.lock),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => _PasswordPage(api: widget.api)),
                ),
                label: Text(t.changePassword),
              ),
              const SizedBox(height: 12),

              OutlinedButton.icon(
                icon: _exportBusy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.file_download),
                label: Text(t.dataExportButton ?? 'Datenexport (DSGVO)'),
                onPressed: _exportBusy ? null : _handleExport,
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                icon: const Icon(Icons.delete_forever, color: Colors.red),
                label: Text(t.accountDelete, style: const TextStyle(color: Colors.red)),
                onPressed: () async {
                  // 1) Sicherheitsabfrage
                  final sure = await showDialog<bool>(
                    context: context,
                    builder: (_) => AlertDialog(
                      title: Text(t.accountDeleteTitle),
                      content: Text(t.accountDeleteConfirm),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: Text(t.cancel),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: Text(t.continueLabel),
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
                        // FIX: Key existierte nicht -> kompatibler Key + Fallback
                        title: Text(t.confirmPassword ?? 'Passwort bestätigen'),
                        content: PasswordField(
                          controller: ctrl,
                          decoration: InputDecoration(labelText: t.gate_password),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: Text(t.cancel),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.pop(context, ctrl.text),
                            child: Text(t.accountDelete),
                          ),
                        ],
                      );
                    },
                  );
                  if (pwd == null || pwd.isEmpty) return;

                  try {
                    await widget.api.accountDelete(pwd);

                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(t.accountDeleted ?? 'Account gelöscht.')),
                    );

                    // Zur Start-/Loginseite zurück
                    Navigator.of(context).popUntil((r) => r.isFirst);
                  } catch (e) {
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('${t.error}: $e')),
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
        title: Text(t.myAccount ?? 'Mein Account'),
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

  Country? _countrySel;

  bool busy = false;
  late String _selectedLang;

  @override
  void initState() {
    super.initState();
    _selectedLang = normalizeLangCode(widget.initial['lang']?.toString());
    _countrySel = _resolveCountry(
      widget.initial['countryCode']?.toString() ?? '',
      widget.initial['country']?.toString() ?? '',
    );
  }

  @override
  void dispose() {
    email.dispose();
    company.dispose();
    contact.dispose();
    street.dispose();
    zip.dispose();
    city.dispose();
    super.dispose();
  }

  Country _selectedCountry(BuildContext context) {
    final fallback = kCountries.first;
    return _countrySel ?? _resolveCountry(
          widget.initial['countryCode']?.toString() ?? '',
          widget.initial['country']?.toString() ?? '',
        ) ??
        fallback;
  }

  Country? _resolveCountry(String code, String name) {
    final resolved = CountryGeography.resolveCode(code.isNotEmpty ? code : name);
    if (resolved == null) return null;
    for (final country in kCountries) {
      if (country.code.toUpperCase() == resolved.toUpperCase()) return country;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final prefs = AppPrefsScope.of(context);
    final customerNo = (widget.initial['customerNumber'] ?? widget.initial['customer_no'] ?? '').toString().trim();

    return Scaffold(
      appBar: AppBar(title: Text(t.editData ?? 'Daten ändern')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              TextField(
                controller: email,
                decoration: InputDecoration(
                  labelText: t.email, border: const OutlineInputBorder(),
                ),
              ),              
              // NEU: Kundennummer nur lesend anzeigen
              if (customerNo.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  '${t.customer_number_label}: $customerNo',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ],              
              const SizedBox(height: 8),
              TextField(
                controller: contact,
                decoration: InputDecoration(
                  labelText: t.contact_person, border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: _selectedLang,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: t.catalog_select_language,
                  border: const OutlineInputBorder(),
                ),
                items: supportedLangCodes
                    .map((code) => DropdownMenuItem<String>(
                          value: code,
                          child: Text(langNameFor(t, code)),
                        ))
                    .toList(),
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => _selectedLang = value);
                  prefs.setLang(value);
                },
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<Country>(
                value: _selectedCountry(context),
                decoration: InputDecoration(
                  labelText: t.country_label,
                  border: const OutlineInputBorder(),
                ),
                items: kCountries
                    .map(
                      (country) => DropdownMenuItem<Country>(
                        value: country,
                        child: Text(country.label(context)),
                      ),
                    )
                    .toList(),
                onChanged: (val) => setState(() => _countrySel = val),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: company,
                decoration: InputDecoration(
                  labelText: t.company, border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: street,
                decoration: InputDecoration(
                  labelText: t.address ?? 'Adresse', border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: zip,
                      decoration: InputDecoration(
                        labelText: t.zip ?? 'PLZ', border: const OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: city,
                      decoration: InputDecoration(
                        labelText: t.city ?? 'Ort', border: const OutlineInputBorder(),
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
                        final country = _selectedCountry(context);
                        await widget.api.accountUpdate({
                          'email':   email.text.trim(),
                          'contact': contact.text.trim(),
                          'company': company.text.trim(),
                          'street':  street.text.trim(),
                          'zip':     zip.text.trim(),
                          'city':    city.text.trim(),
                          'lang':    _selectedLang,
                          'country': country.label(context),
                          'countryCode': country.code,
                        });
                        await prefs.setLang(_selectedLang);
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(context.t.saved ?? 'Gespeichert.')),
                        );
                        Navigator.of(context).pop();
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('${context.t.error ?? 'Fehler'}: $e')),
                          );
                        }
                      } finally {
                        if (mounted) setState(() => busy = false);
                      }
                    },
                    child: busy
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : Text(context.t.save ?? 'Speichern'),
                  ),

                  const SizedBox(width: 12),
                  OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(t.cancel),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: LegalFooter(api: widget.api),
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
  void dispose() {
    oldPw.dispose();
    newPw1.dispose();
    newPw2.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;

    return Scaffold(
      appBar: AppBar(title: Text(t.changePassword ?? 'Passwort ändern')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              PasswordField(
                controller: oldPw,
                decoration: InputDecoration(
                  labelText: t.oldPassword ?? 'Altes Passwort', border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              PasswordField(
                controller: newPw1,
                decoration: InputDecoration(
                  labelText: t.newPassword ?? 'Neues Passwort',
                  border: const OutlineInputBorder(),
                  helperText: t.password_requirements,
                ),
              ),
              const SizedBox(height: 8),
              PasswordField(
                controller: newPw2,
                decoration: InputDecoration(
                  labelText: t.newPasswordRepeat ?? 'Neues Passwort (Wdh.)',
                  border: const OutlineInputBorder(),
                  helperText: t.password_requirements,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  FilledButton(
                    onPressed: busy ? null : () async {
                      if (newPw1.text != newPw2.text) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(t.passwordsDontMatch ?? 'Passwörter stimmen nicht überein.')),
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
                          SnackBar(content: Text(t.passwordChanged ?? 'Passwort geändert.')),
                        );
                        Navigator.of(context).pop();
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('${t.error ?? 'Fehler'}: $e')),
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
                        : Text(t.save ?? 'Speichern'),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(t.cancel),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: LegalFooter(api: widget.api),
    );
  }
}
