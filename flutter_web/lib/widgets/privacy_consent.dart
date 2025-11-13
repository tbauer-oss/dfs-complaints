// lib/widgets/privacy_consent.dart
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:html' as html;
import '../constants.dart';

class PrivacyConsent extends StatelessWidget {
  final bool value;
  final ValueChanged<bool?> onChanged;

  /// Optional: lokalisiert anpassbar
  final String? labelPrefix;   // z. B. "Ich habe die "
  final String? linkLabel;     // z. B. "Datenschutzhinweise"
  final String? labelSuffix;   // z. B. " gelesen und stimme zu."

  const PrivacyConsent({
    super.key,
    required this.value,
    required this.onChanged,
    this.labelPrefix,
    this.linkLabel,
    this.labelSuffix,
  });

  @override
  Widget build(BuildContext context) {
    final lp = (labelPrefix ?? 'Ich habe die ').trim();
    final ll = (linkLabel ?? 'Datenschutzinformationen').trim();
    final ls = (labelSuffix ?? ' gelesen und stimme zu.').trim();

    final linkStyle = TextStyle(
      color: Theme.of(context).colorScheme.primary,
      decoration: TextDecoration.underline,
      fontWeight: FontWeight.w600,
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Checkbox(
          value: value,
          onChanged: onChanged,
        ),
        const SizedBox(width: 6),
        // Text mit klickbarem Link – bricht sauber um
        Expanded(
          child: Wrap(
            alignment: WrapAlignment.start,
            crossAxisAlignment: WrapCrossAlignment.center,
            runSpacing: 4,
            children: [
              Text(lp),
              InkWell(
                onTap: () => html.window.open(kPrivacyUrl, '_blank'),
                child: Text(ll, style: linkStyle),
              ),
              Text(ls),
            ],
          ),
        ),
      ],
    );
  }
}
