import 'display_name_from_email.dart';

String deriveDisplayName(String? displayName, {String? email, String fallback = 'Unbekannt'}) {
  final trimmed = (displayName ?? '').trim();
  final looksLikeEmail = trimmed.contains('@');
  if (trimmed.isNotEmpty && !looksLikeEmail) return trimmed;

  final candidateEmail = (looksLikeEmail ? trimmed : (email ?? '').trim());
  if (candidateEmail.isNotEmpty) return deriveDisplayNameFromEmail(candidateEmail);
  if (trimmed.isNotEmpty) return trimmed;
  return fallback;
}

String deriveDisplayNameFromEmail(String email) => displayNameFromEmail(email);
