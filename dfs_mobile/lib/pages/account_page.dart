// lib/pages/account_page.dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:file_saver/file_saver.dart';
import 'package:intl/intl.dart';
import '../api/client.dart';
import '../data/country_geography.dart';
import '../l10n/app_localizations.dart';
import '../models/country.dart';
import '../services/app_prefs_scope.dart';
import '../utils/lang_utils.dart';
import '../widgets/dialog_content_scroll.dart';
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
      final data = await widget.api.accountGet();
      if (!mounted) return;

      final prefs = AppPrefsScope.of(context);
      final lang = normalizeLangCode(data['lang']?.toString());
      final currentLang = prefs.locale?.languageCode.toLowerCase();
      if (currentLang != lang) {
        await prefs.setLang(lang);
      }

      setState(() {
        acc = data;
      });
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
      if (mounted) {
        setState(() {
          err = s;
        });
      }
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
          content: DialogContentScroll(
            child: SelectableText(
              pretty,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
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
        fileExtension: 'txt',       // statt ext: und statt positional 'txt'
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

  Widget _infoRow(BuildContext context, IconData icon, String label, String value) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withOpacity(0.08),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: theme.colorScheme.primary, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.labelSmall?.copyWith(
                    letterSpacing: 0.5,
                    color: theme.colorScheme.outline,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;

    final body = () {
      if (busy) return const Center(child: CircularProgressIndicator());
      if (err != null) return Center(child: Text(err!));
      // FIX: falscher Key (früher: t.editdata) -> nutze vorhandenen Key oder Fallback
      if (acc == null) return Center(child: Text(t.noDataFound ?? 'Keine Daten gefunden.'));

      final theme = Theme.of(context);
      final highlight = theme.colorScheme.primaryContainer.withOpacity(0.6);
      final surfaceTint = theme.colorScheme.surfaceVariant.withOpacity(0.35);

      return Container(
        color: surfaceTint,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 840),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 32),
              children: [
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [highlight, theme.colorScheme.primaryContainer],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: theme.colorScheme.primary.withOpacity(0.18),
                        blurRadius: 24,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.onPrimaryContainer.withOpacity(0.08),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(Icons.person_pin_circle,
                                color: theme.colorScheme.onPrimaryContainer, size: 30),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  t.myAccount ?? 'Mein Account',
                                  style: theme.textTheme.titleLarge?.copyWith(
                                    color: theme.colorScheme.onPrimaryContainer,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _val(acc!['email'], ''),
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: theme.colorScheme.onPrimaryContainer.withOpacity(0.9),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Chip(
                            backgroundColor: theme.colorScheme.onPrimaryContainer.withOpacity(0.08),
                            label: Text(
                              t.catalog_select_language,
                              style: TextStyle(
                                color: theme.colorScheme.onPrimaryContainer,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Icon(Icons.verified_user, color: theme.colorScheme.onPrimaryContainer),
                          const SizedBox(width: 8),
                          Text(
                            t.customer_number_label ?? 'Kundennr.',
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: theme.colorScheme.onPrimaryContainer.withOpacity(0.8),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _val(acc!['customerNumber'] ?? acc!['customer_no']),
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: theme.colorScheme.onPrimaryContainer,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),
                Card(
                  elevation: 4,
                  margin: EdgeInsets.zero,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          t.contact_person,
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        _infoRow(context, Icons.person_outline, t.contact_person,
                            _val(acc!['contact'])),
                        _infoRow(
                          context,
                          Icons.apartment,
                          t.company,
                          _val(acc!['company']),
                        ),
                        _infoRow(
                          context,
                          Icons.language,
                          t.catalog_select_language,
                          _langDisplay(context, acc!['lang']),
                        ),
                        _infoRow(
                          context,
                          Icons.flag_outlined,
                          t.country_label ?? 'Land',
                          _val(acc!['country']),
                        ),
                        _infoRow(
                          context,
                          Icons.location_on_outlined,
                          t.address ?? 'Adresse',
                          '${_val(acc!['street'])}, ${_val(acc!['zip'])} ${_val(acc!['city'])}',
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),
                Card(
                  elevation: 2,
                  margin: EdgeInsets.zero,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          t.editData,
                          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            FilledButton.icon(
                              icon: const Icon(Icons.edit),
                              style: FilledButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              onPressed: () => Navigator.of(context)
                                  .push(
                                    MaterialPageRoute(
                                      builder: (_) => _AccountEditPage(api: widget.api, initial: acc!),
                                    ),
                                  )
                                  .then((_) => _load()),
                              label: Text(t.editData),
                            ),
                            FilledButton.icon(
                              icon: const Icon(Icons.lock_outline),
                              style: FilledButton.styleFrom(
                                backgroundColor: theme.colorScheme.secondaryContainer,
                                foregroundColor: theme.colorScheme.onSecondaryContainer,
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              onPressed: () => Navigator.of(context).push(
                                MaterialPageRoute(builder: (_) => _PasswordPage(api: widget.api)),
                              ),
                              label: Text(t.changePassword),
                            ),
                            OutlinedButton.icon(
                              icon: _exportBusy
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    )
                                  : const Icon(Icons.file_download_outlined),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              label: Text(t.dataExportButton ?? 'Datenexport (DSGVO)'),
                              onPressed: _exportBusy ? null : _handleExport,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),
                Card(
                  color: theme.colorScheme.errorContainer.withOpacity(0.9),
                  elevation: 0,
                  margin: EdgeInsets.zero,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.warning_amber_rounded, color: theme.colorScheme.onErrorContainer),
                            const SizedBox(width: 8),
                            Text(
                              t.accountDelete,
                              style: theme.textTheme.titleMedium?.copyWith(
                                color: theme.colorScheme.onErrorContainer,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          t.accountDeleteConfirm,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onErrorContainer.withOpacity(0.9),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Align(
                          alignment: Alignment.centerRight,
                          child: OutlinedButton.icon(
                            icon: Icon(Icons.delete_forever, color: theme.colorScheme.onErrorContainer),
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(color: theme.colorScheme.onErrorContainer),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            label: Text(
                              t.accountDelete,
                              style: TextStyle(
                                color: theme.colorScheme.onErrorContainer,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            onPressed: () async {
                              // 1) Sicherheitsabfrage
                              final sure = await showDialog<bool>(
                                context: context,
                                builder: (_) => AlertDialog(
                                  title: Text(t.accountDeleteTitle),
                                  content: DialogContentScroll(child: Text(t.accountDeleteConfirm)),
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
                                    content: DialogContentScroll(
                                      child: PasswordField(
                                        controller: ctrl,
                                        decoration: InputDecoration(labelText: t.gate_password),
                                      ),
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
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
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
    final customerNo =
        (widget.initial['customerNumber'] ?? widget.initial['customer_no'] ?? '').toString().trim();

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
              if (customerNo.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  '${t.customer_number_label ?? 'Kundennr.'}: $customerNo',
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
