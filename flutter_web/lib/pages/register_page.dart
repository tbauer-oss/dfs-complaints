// lib/pages/register_page.dart
import 'dart:math';

import 'package:flutter/material.dart';
import '../api/client.dart';
import '../l10n/app_localizations.dart';
import '../models/country.dart';
import '../widgets/lang_action.dart';
import '../services/app_prefs.dart';
import '../services/app_prefs_scope.dart';
import '../utils/lang_utils.dart';
import '../widgets/gate_code_input.dart';
import '../widgets/theme_action.dart' as w;
import '../widgets/legal_footer.dart';
import '../widgets/password_field.dart';

enum Salutation { mr, ms, diverse }

// ---- L10n-Helper (top-level, NICHT in der Klasse!) ----
extension _L10nX on BuildContext {
  AppLocalizations get t => AppLocalizations.of(this)!;
}

class RegisterPage extends StatefulWidget {
  final ApiClient api;
  const RegisterPage({super.key, required this.api});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  InputDecoration _decor(BuildContext context, String label,
      {IconData? icon, String? hint}) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = scheme.brightness == Brightness.dark;
    final baseBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(
        color: scheme.outline.withOpacity(isDark ? 0.3 : 0.2),
      ),
    );

    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: icon != null ? Icon(icon) : null,
      filled: true,
      fillColor: isDark
          ? scheme.surfaceVariant.withOpacity(0.32)
          : scheme.surfaceVariant.withOpacity(0.7),
      border: baseBorder,
      enabledBorder: baseBorder,
      focusedBorder: baseBorder.copyWith(
        borderSide: BorderSide(color: scheme.primary, width: 1.6),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
    );
  }

  Widget _sectionTitle(BuildContext context, IconData icon, String title,
      {String? subtitle}) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                decoration: BoxDecoration(
                  color: scheme.primary.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.all(8),
                child: Icon(icon, size: 18, color: scheme.primary),
              ),
              const SizedBox(width: 12),
              Text(
                title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurface.withOpacity(0.7),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _dualFields(BuildContext context, Widget left, Widget right) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 460) {
          return Column(
            children: [
              left,
              const SizedBox(height: 12),
              right,
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: left),
            const SizedBox(width: 16),
            Expanded(child: right),
          ],
        );
      },
    );
  }

  Widget _messageBanner(BuildContext context,
      {required String message,
      required Color color,
      required IconData icon}) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.32)),
        boxShadow: [
          if (scheme.brightness == Brightness.light)
            BoxShadow(
              color: color.withOpacity(0.12),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Gate (AUTH_PASSWORD) – vor Betreten der Registrierung
  final _gateCompany = TextEditingController();
  final _gateEmail = TextEditingController();
  String _gateCode = '';
  bool _gateBusy = false;
  bool _gateRequestBusy = false;
  String? _gateErr;
  String? _gateInfo;

  // Formular
  final _email = TextEditingController();
  final _pw = TextEditingController();
  final _pw2 = TextEditingController();
  final _company = TextEditingController();
  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  final _street = TextEditingController();
  final _zip = TextEditingController();
  final _city = TextEditingController();
  final _phone = TextEditingController();

  Country? _countrySel;
  Salutation _salutation = Salutation.mr;
  bool _privacy = false;
  String _humanQuestion = '';
  int _humanAnswer = 0;
  List<int> _humanOptions = const [];
  bool _humanVerified = false;
  String _selectedLang = 'de';

  bool get _canSubmit => !_busy && _privacy && _humanVerified;

  bool _busy = false;
  String? _err;
  String? _info;

  final _random = Random.secure();

  // --- Fehlende Member für AppBar-Actions (minimal) ---
  bool _loading = false;
  Future<void> _loadAll() async {
    // optional: später echtes Reload einbauen
    setState(() => _loading = true);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    if (mounted) setState(() => _loading = false);
  }

  void _logout() {
    Navigator.of(context).pushNamedAndRemoveUntil('/', (Route<dynamic> r) => false);
  }
  // -----------------------------------------------------

  @override
  void initState() {
    super.initState();
    _countrySel = kCountries.firstWhere(
      (c) => c.code == 'DE',
      orElse: () => kCountries.first,
    );
    _rollHumanChallenge();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final prefs = AppPrefsScope.of(context);
    final locale = prefs.locale ?? Localizations.localeOf(context);
    final normalized = normalizeLangCode(locale.languageCode);
    if (_selectedLang != normalized) {
      _selectedLang = normalized;
    }
  }

  @override
  void dispose() {
    _gateCompany.dispose();
    _gateEmail.dispose();
    _email.dispose();
    _pw.dispose();
    _pw2.dispose();
    _company.dispose();
    _firstName.dispose();
    _lastName.dispose();
    _street.dispose();
    _zip.dispose();
    _city.dispose();
    _phone.dispose();
    super.dispose();
  }

  String _salutationLabel(AppLocalizations t, Salutation s) {
    switch (s) {
      case Salutation.mr:
        return t.salutation_mr;
      case Salutation.ms:
        return t.salutation_ms;
      case Salutation.diverse:
        return t.salutation_diverse;
    }
  }

  bool _isValidEmail(String email) {
    final regex = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
    return regex.hasMatch(email);
  }

  void _rollHumanChallenge() {
    final a = _random.nextInt(4) + 2; // 2–5
    final b = _random.nextInt(4) + 2; // 2–5
    final answer = a + b;

    final options = <int>{answer};
    while (options.length < 3) {
      final delta = _random.nextInt(3) + 1; // 1–3
      final candidate = answer + (_random.nextBool() ? delta : -delta);
      if (candidate > 0) options.add(candidate);
    }

    final shuffled = options.toList()..shuffle(_random);

    setState(() {
      _humanQuestion = '$a + $b = ?';
      _humanAnswer = answer;
      _humanOptions = shuffled;
      _humanVerified = false;
    });
  }

  void _handleHumanSelection(int value) {
    setState(() => _humanVerified = value == _humanAnswer);
  }

  Future<void> _unlockGate() async {
    final t = context.t;
    final email = _gateEmail.text.trim();
    final company = _gateCompany.text.trim();
    final password = _gateCode.trim();

    setState(() {
      _gateErr = null;
      _gateInfo = null;
    });

    if (company.isEmpty) {
      setState(() => _gateErr = t.gateCompanyRequired);
      return;
    }
    if (email.isEmpty) {
      setState(() => _gateErr = t.gateEmailRequired);
      return;
    }
    if (!_isValidEmail(email)) {
      setState(() => _gateErr = t.gateInvalidEmail);
      return;
    }
    if (password.isEmpty) {
      setState(() => _gateErr = t.gatePasswordRequired);
      return;
    }

    setState(() {
      _gateBusy = true;
    });
    try {
      final ok = await widget.api.gateUnlock(
        password,
        email: email,
        company: company,
      );
      if (!mounted) return;
      if (!ok) {
        setState(() => _gateErr = t.wrongPassword);
        return;
      }
      if (_email.text.trim().isEmpty) {
        _email.text = email;
      }
      if (_company.text.trim().isEmpty) {
        _company.text = company;
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _gateErr = '${t.network_cors_error}: $e');
    } finally {
      if (mounted) setState(() => _gateBusy = false);
    }
  }

  Future<void> _requestGatePassword() async {
    final t = context.t;
    final email = _gateEmail.text.trim();
    final company = _gateCompany.text.trim();

    setState(() {
      _gateErr = null;
      _gateInfo = null;
    });

    if (company.isEmpty) {
      setState(() => _gateErr = t.gateCompanyRequired);
      return;
    }
    if (email.isEmpty) {
      setState(() => _gateErr = t.gateEmailRequired);
      return;
    }
    if (!_isValidEmail(email)) {
      setState(() => _gateErr = t.gateInvalidEmail);
      return;
    }

    setState(() => _gateRequestBusy = true);
    try {
      final err = await widget.api.gateRequestPassword(
        email,
        company: company,
      );
      if (!mounted) return;
      if (err == null) {
        setState(() => _gateInfo = t.gateRequestInfo);
      } else {
        setState(() => _gateErr = t.gateRequestError(err));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _gateErr = t.gateRequestError('$e'));
    } finally {
      if (mounted) setState(() => _gateRequestBusy = false);
    }
  }

  Future<void> _submit() async {
    final t = context.t;
    setState(() {
      _busy = true;
      _err = null;
      _info = null;
    });

    try {
      if (_pw.text != _pw2.text) {
        setState(() => _err = t.password_mismatch);
        return;
      }
      if (!_isHuman) {
        setState(() => _err = t.human_check_required);
        return;
      }
      if (!_privacy) {
        setState(() => _err = t.privacy_required);
        return;
      }
      if (_firstName.text.trim().isEmpty || _lastName.text.trim().isEmpty) {
        setState(() => _err = t.name_required);
        return;
      }

      final sel = _countrySel ?? kCountries.first;

      final payload = <String, dynamic>{
        'email': _email.text.trim(),
        'password': _pw.text,
        'password2': _pw2.text,
        'company': _company.text.trim(),
        'firstName': _firstName.text.trim(),
        'lastName': _lastName.text.trim(),
        'salutation': _salutation.name, // "mr" | "ms" | "diverse"
        'contact': '${_firstName.text.trim()} ${_lastName.text.trim()}'.trim(),
        'street': _street.text.trim(),
        'zip': _zip.text.trim(),
        'city': _city.text.trim(),
        'country': sel.label(context),
        'countryCode': sel.code,
        'phone': _phone.text.trim(),
        'privacy': true,
        'lang': _selectedLang,
      };

      final String? errMsg = await widget.api.register(payload);
      if (!mounted) return;

      if (errMsg == null) {
        setState(() => _info = t.registration_received);
        return;
      }

      // Fehlertext heuristisch auswerten
      final em = errMsg.toLowerCase();
      if (em.contains('user_exists') || em.contains('409')) {
        setState(() => _err = t.email_exists);
      } else if (em.contains('pending') || em.contains('resent')) {
        setState(() => _err = t.register_pending_resent);
      } else {
        setState(() => _err = t.register_failed(errMsg));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _err = '${t.network_cors_error}: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  List<Widget> _buildGateUnlockSection(
    BuildContext context,
    AppLocalizations t,
  ) {
    final widgets = <Widget>[
      Text(
        t.gateUnlockHint,
        style: const TextStyle(fontWeight: FontWeight.w500),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _gateCompany,
        textCapitalization: TextCapitalization.words,
        decoration: InputDecoration(
          labelText: t.company,
          border: const OutlineInputBorder(),
        ),
        onSubmitted: (_) {
          if (!_gateBusy && !_gateRequestBusy) _unlockGate();
        },
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _gateEmail,
        keyboardType: TextInputType.emailAddress,
        autofillHints: const [AutofillHints.email],
        decoration: InputDecoration(
          labelText: t.email,
          border: const OutlineInputBorder(),
        ),
        onSubmitted: (_) {
          if (!_gateBusy && !_gateRequestBusy) _unlockGate();
        },
      ),
      const SizedBox(height: 12),
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            t.gate_password,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 8),
          Center(
            child: GateCodeInput(
              onChanged: (value) {
                if (_gateCode != (value ?? '')) {
                  setState(() => _gateCode = value ?? '');
                }
              },
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),
      FilledButton(
        onPressed: (_gateBusy || _gateRequestBusy) ? null : _unlockGate,
        child: _gateBusy
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Text(t.unlock),
      ),
      const SizedBox(height: 8),
      OutlinedButton(
        onPressed: (_gateBusy || _gateRequestBusy) ? null : _requestGatePassword,
        child: _gateRequestBusy
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Text(t.gateRequestPassword),
      ),
    ];

    if (_gateErr != null) {
      widgets.addAll([
        const SizedBox(height: 8),
        Text(_gateErr!, style: const TextStyle(color: Colors.red)),
      ]);
    }
    if (_gateInfo != null) {
      widgets.addAll([
        const SizedBox(height: 8),
        Text(
          _gateInfo!,
          style: const TextStyle(color: Colors.green),
        ),
      ]);
    }

    widgets.addAll([
      const SizedBox(height: 8),
      TextButton(
        onPressed: () => Navigator.of(context).maybePop(),
        child: Text(t.back),
      ),
    ]);

    return widgets;
  }

  Widget _buildRegistrationCard(
    BuildContext context,
    AppLocalizations t,
    ColorScheme scheme,
    AppPrefs prefs,
  ) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
      decoration: BoxDecoration(
        color: scheme.surface
            .withOpacity(scheme.brightness == Brightness.dark ? 0.92 : 0.98),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: scheme.outline.withOpacity(0.08)),
        boxShadow: [
          if (scheme.brightness == Brightness.light)
            BoxShadow(
              color: scheme.primary.withOpacity(0.12),
              blurRadius: 32,
              offset: const Offset(0, 18),
            ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(
            context,
            Icons.lock_outline,
            t.auth_register,
          ),
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            decoration: _decor(
              context,
              t.email,
              icon: Icons.alternate_email,
            ),
          ),
          const SizedBox(height: 16),
          _dualFields(
            context,
            PasswordField(
              controller: _pw,
              decoration: _decor(
                context,
                t.password,
                icon: Icons.lock_outline,
              ),
            ),
            PasswordField(
              controller: _pw2,
              decoration: _decor(
                context,
                t.password_repeat,
                icon: Icons.lock_reset,
              ),
            ),
          ),
          const SizedBox(height: 24),
          Divider(height: 1, color: scheme.outline.withOpacity(0.12)),
          const SizedBox(height: 24),
          _sectionTitle(
            context,
            Icons.business_center_outlined,
            t.company_plain,
          ),
          TextField(
            controller: _company,
            decoration: _decor(
              context,
              t.company,
              icon: Icons.business_outlined,
            ),
          ),
          const SizedBox(height: 24),
          _sectionTitle(
            context,
            Icons.person_outline,
            t.contact_person,
          ),
          _dualFields(
            context,
            DropdownButtonFormField<Salutation>(
              value: _salutation,
              isExpanded: true,
              decoration: _decor(
                context,
                t.salutation,
                icon: Icons.wc,
              ),
              items: [
                DropdownMenuItem(
                  value: Salutation.mr,
                  child: Text(_salutationLabel(t, Salutation.mr)),
                ),
                DropdownMenuItem(
                  value: Salutation.ms,
                  child: Text(_salutationLabel(t, Salutation.ms)),
                ),
                DropdownMenuItem(
                  value: Salutation.diverse,
                  child: Text(_salutationLabel(t, Salutation.diverse)),
                ),
              ],
              onChanged: (v) => setState(() => _salutation = v ?? Salutation.mr),
            ),
            DropdownButtonFormField<String>(
              value: _selectedLang,
              isExpanded: true,
              decoration: _decor(
                context,
                t.catalog_select_language,
                icon: Icons.language_outlined,
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
          ),
          const SizedBox(height: 16),
          _dualFields(
            context,
            TextField(
              controller: _firstName,
              decoration: _decor(
                context,
                t.first_name,
                icon: Icons.badge_outlined,
              ),
            ),
            TextField(
              controller: _lastName,
              decoration: _decor(
                context,
                t.last_name,
                icon: Icons.badge,
              ),
            ),
          ),
          const SizedBox(height: 24),
          Divider(height: 1, color: scheme.outline.withOpacity(0.12)),
          const SizedBox(height: 24),
          _sectionTitle(
            context,
            Icons.location_on_outlined,
            t.address,
          ),
          TextField(
            controller: _street,
            decoration: _decor(
              context,
              t.street,
              icon: Icons.route_outlined,
            ),
          ),
          const SizedBox(height: 16),
          _dualFields(
            context,
            TextField(
              controller: _zip,
              decoration: _decor(
                context,
                t.zip,
                icon: Icons.local_post_office_outlined,
              ),
            ),
            TextField(
              controller: _city,
              decoration: _decor(
                context,
                t.city,
                icon: Icons.location_city_outlined,
              ),
            ),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<Country>(
            value: _countrySel,
            isExpanded: true,
            decoration: _decor(
              context,
              t.country,
              icon: Icons.public,
            ),
            items: kCountries
                .map((c) => DropdownMenuItem<Country>(
                    value: c, child: Text(c.label(context))))
                .toList(),
            onChanged: (val) => setState(() => _countrySel = val),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            decoration: _decor(
              context,
              t.phone,
              icon: Icons.phone_outlined,
            ),
          ),
          const SizedBox(height: 24),
          AnimatedContainer(
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeInOutCubic,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _humanVerified
                  ? scheme.secondaryContainer.withOpacity(0.35)
                  : scheme.secondary.withOpacity(0.05),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: _humanVerified
                    ? scheme.secondary.withOpacity(0.4)
                    : scheme.secondary.withOpacity(0.1),
              ),
              boxShadow: _humanVerified
                  ? [
                      BoxShadow(
                        color: scheme.secondary.withOpacity(0.16),
                        blurRadius: 18,
                        offset: const Offset(0, 10),
                      ),
                    ]
                  : [],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      _humanVerified
                          ? Icons.verified_user_outlined
                          : Icons.gesture_outlined,
                      color: _humanVerified
                          ? scheme.secondary
                          : scheme.onSurface.withOpacity(0.7),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      t.human_check_label,
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: _rollHumanChallenge,
                      icon: const Icon(Icons.refresh),
                      label: Text(t.human_check_refresh),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                AnimatedCrossFade(
                  duration: const Duration(milliseconds: 300),
                  crossFadeState: _humanVerified
                      ? CrossFadeState.showSecond
                      : CrossFadeState.showFirst,
                  firstChild: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        t.human_check_helper(_humanQuestion),
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: scheme.onSurface.withOpacity(0.75)),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          for (final option in _humanOptions)
                            ChoiceChip(
                              label: Text(option.toString()),
                              selectedColor:
                                  scheme.secondaryContainer.withOpacity(0.7),
                              selected: _humanVerified && option == _humanAnswer,
                              onSelected: (_) => _handleHumanSelection(option),
                              avatar: Icon(
                                Icons.touch_app_outlined,
                                size: 18,
                                color: _humanVerified && option == _humanAnswer
                                    ? scheme.onSecondaryContainer
                                    : scheme.onSurface.withOpacity(0.8),
                              ),
                              labelStyle: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: _humanVerified && option == _humanAnswer
                                    ? scheme.onSecondaryContainer
                                    : null,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                  secondChild: Row(
                    children: [
                      Icon(Icons.check_circle, color: scheme.secondary),
                      const SizedBox(width: 10),
                      Text(
                        t.human_check_success,
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(
                              color: scheme.secondary,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: scheme.primary.withOpacity(0.05),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: scheme.primary.withOpacity(0.1)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Checkbox(
                  value: _privacy,
                  onChanged: (v) => setState(() => _privacy = v ?? false),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        t.privacy_agree,
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 6),
                      InkWell(
                        onTap: () =>
                            Navigator.of(context).pushNamed('/legal/privacy'),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.privacy_tip_outlined,
                              size: 18,
                              color: scheme.primary,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              t.privacy_view,
                              style: TextStyle(
                                color: scheme.primary,
                                decoration: TextDecoration.underline,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (_err != null) ...[
            const SizedBox(height: 20),
            _messageBanner(
              context,
              message: _err!,
              color: scheme.error,
              icon: Icons.error_outline,
            ),
          ],
          if (_info != null) ...[
            const SizedBox(height: 20),
            _messageBanner(
              context,
              message: _info!,
              color: scheme.secondary,
              icon: Icons.check_circle_outline,
            ),
          ],
          const SizedBox(height: 24),
          Align(
            alignment: Alignment.centerRight,
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              alignment: WrapAlignment.end,
              children: [
                OutlinedButton.icon(
                  onPressed: () {
                    final nav = Navigator.of(context);
                    if (nav.canPop()) {
                      nav.pop();
                    } else {
                      nav.pushReplacementNamed('/');
                    }
                  },
                  icon: const Icon(Icons.arrow_back),
                  label: Text(t.back),
                ),
                FilledButton(
                  onPressed: _canSubmit ? _submit : null,
                  child: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.check_circle_outline),
                            const SizedBox(width: 8),
                            Text(t.auth_register),
                          ],
                        ),
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
    final needsGate = widget.api.gate == null || widget.api.gate!.isEmpty;
    final prefs = AppPrefsScope.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final gradient = LinearGradient(
      colors: [
        scheme.primary.withOpacity(scheme.brightness == Brightness.dark ? 0.25 : 0.45),
        scheme.secondary.withOpacity(scheme.brightness == Brightness.dark ? 0.18 : 0.3),
        scheme.surface.withOpacity(0.92),
      ],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    );

    return WillPopScope(
      onWillPop: () async => true, // Pop NICHT abfangen – normal durchlassen
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            tooltip: t.back,
            onPressed: () {
              final nav = Navigator.of(context);
              if (nav.canPop()) {
                nav.pop(); // sofort poppen, kein await/maybePop
              } else {
                nav.pushReplacementNamed('/'); // Fallback zur Startseite
              }
            },
          ),
          title: Text(needsGate ? t.unlock : t.auth_register),
          actions: [
            IconButton(
              tooltip: t.newLoad,
              onPressed: _loading ? null : _loadAll,
              icon: const Icon(Icons.refresh),
            ),
            const SizedBox(width: 4),
            LangAction(onLocaleChanged: (l) => prefs.setLang(l.languageCode)),
            const SizedBox(width: 4),
            w.ThemeAction(),
            const SizedBox(width: 8),
            TextButton.icon(
              onPressed: () {
                Navigator.of(context).pushNamedAndRemoveUntil('/', (r) => false);
              },
              icon: const Icon(Icons.home),
              label: Text(t.back), // oder eigener Key z.B. t.to_home
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: AnimatedContainer(
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeInOutCubic,
          decoration: needsGate
              ? null
              : BoxDecoration(
                  gradient: gradient,
                ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
                children: needsGate
                    ? _buildGateUnlockSection(context, t)
                    : [
                        _buildRegistrationCard(context, t, scheme, prefs),
                      ],
              ),
            ),
          ),
        ),
        bottomNavigationBar: LegalFooter(api: widget.api),
      ),
    );
  }
}
