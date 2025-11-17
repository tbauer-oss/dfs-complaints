import 'package:flutter/material.dart';
import '../api/client.dart';
import '../l10n/app_localizations.dart';
import '../widgets/legal_footer.dart';

class ResetPasswordPage extends StatefulWidget {
  final ApiClient api;
  const ResetPasswordPage({super.key, required this.api});

  @override
  State<ResetPasswordPage> createState() => _ResetPasswordPageState();
}

class _ResetPasswordPageState extends State<ResetPasswordPage> {
  final _requestEmail = TextEditingController();
  final _confirmEmail = TextEditingController();
  final _tempPassword = TextEditingController();
  final _newPassword1 = TextEditingController();
  final _newPassword2 = TextEditingController();

  bool _requestBusy = false;
  bool _completeBusy = false;
  String? _requestMessage;
  String? _requestError;
  String? _completeMessage;
  String? _completeError;

  @override
  void initState() {
    super.initState();
    final params = Uri.base.queryParameters;
    final email = params['email'];
    if (email != null && email.isNotEmpty) {
      _requestEmail.text = email;
      _confirmEmail.text = email;
    }
  }

  @override
  void dispose() {
    _requestEmail.dispose();
    _confirmEmail.dispose();
    _tempPassword.dispose();
    _newPassword1.dispose();
    _newPassword2.dispose();
    super.dispose();
  }

  Future<void> _requestReset() async {
    final t = AppLocalizations.of(context)!;
    final email = _requestEmail.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(() {
        _requestError = t.forgot_password_invalid_email;
        _requestMessage = null;
      });
      return;
    }
    setState(() {
      _requestBusy = true;
      _requestError = null;
      _requestMessage = null;
    });
    final result = await widget.api.requestPasswordReset(email);
    if (!mounted) return;
    setState(() {
      _requestBusy = false;
      if (result.ok) {
        _requestMessage = t.forgot_password_success(email);
        _requestError = null;
      } else {
        if (result.statusCode == 404) {
          _requestError = t.forgot_password_unknown_account;
        } else if (result.statusCode == 400) {
          _requestError = t.forgot_password_invalid_email;
        } else {
          _requestError = result.message ?? t.forgot_password_unknown_account;
        }
        _requestMessage = null;
      }
    });
  }

  Future<void> _completeReset() async {
    final t = AppLocalizations.of(context)!;
    final email = _confirmEmail.text.trim();
    final temp = _tempPassword.text.trim();
    final new1 = _newPassword1.text;
    final new2 = _newPassword2.text;

    if (email.isEmpty || !email.contains('@')) {
      setState(() {
        _completeError = t.forgot_password_invalid_email;
        _completeMessage = null;
      });
      return;
    }
    if (temp.isEmpty) {
      setState(() {
        _completeError = t.reset_password_temp_error;
        _completeMessage = null;
      });
      return;
    }
    if (new1.isEmpty || new2.isEmpty) {
      setState(() {
        _completeError = t.password_both_required;
        _completeMessage = null;
      });
      return;
    }
    if (new1 != new2) {
      setState(() {
        _completeError = t.password_not_match;
        _completeMessage = null;
      });
      return;
    }

    setState(() {
      _completeBusy = true;
      _completeError = null;
      _completeMessage = null;
    });

    final result = await widget.api.completePasswordReset(email, temp, new1);
    if (!mounted) return;

    setState(() {
      _completeBusy = false;
      if (result.ok) {
        _completeMessage = t.reset_password_success;
        _completeError = null;
        _tempPassword.clear();
        _newPassword1.clear();
        _newPassword2.clear();
      } else {
        if (result.statusCode == 410 || result.statusCode == 400) {
          _completeError = t.reset_password_temp_error;
        } else {
          _completeError = result.message ?? t.reset_password_temp_error;
        }
        _completeMessage = null;
      }
    });
  }

  Widget _sectionCard({required String title, required List<Widget> children}) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 12),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        appBar: AppBar(title: Text(t.reset_password_page_title)),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: Column(
                  children: [
                    _sectionCard(
                      title: t.reset_password_request_title,
                      children: [
                        Text(t.forgot_password_instructions),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _requestEmail,
                          keyboardType: TextInputType.emailAddress,
                          decoration: InputDecoration(labelText: t.email),
                          onSubmitted: (_) => _requestReset(),
                        ),
                        const SizedBox(height: 12),
                        if (_requestError != null)
                          Text(_requestError!, style: TextStyle(color: theme.colorScheme.error)),
                        if (_requestMessage != null)
                          Text(_requestMessage!, style: TextStyle(color: theme.colorScheme.tertiary)),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: _requestBusy ? null : _requestReset,
                          child: _requestBusy
                              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                              : Text(t.reset_password_request_action),
                        ),
                      ],
                    ),
                    _sectionCard(
                      title: t.reset_password_unlock_title,
                      children: [
                        Text(t.reset_password_unlock_info),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _confirmEmail,
                          keyboardType: TextInputType.emailAddress,
                          decoration: InputDecoration(labelText: t.email),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _tempPassword,
                          obscureText: true,
                          decoration: InputDecoration(labelText: t.reset_password_temp_label),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _newPassword1,
                          obscureText: true,
                          decoration: InputDecoration(labelText: t.newPassword),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _newPassword2,
                          obscureText: true,
                          decoration: InputDecoration(labelText: t.newPasswordRepeat),
                        ),
                        const SizedBox(height: 12),
                        if (_completeError != null)
                          Text(_completeError!, style: TextStyle(color: theme.colorScheme.error)),
                        if (_completeMessage != null)
                          Text(_completeMessage!, style: TextStyle(color: theme.colorScheme.tertiary)),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: _completeBusy ? null : _completeReset,
                          child: _completeBusy
                              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                              : Text(t.reset_password_submit),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        bottomNavigationBar: LegalFooter(api: widget.api),
      ),
    );
  }
}
