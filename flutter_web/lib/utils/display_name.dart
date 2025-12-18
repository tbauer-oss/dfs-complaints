String deriveDisplayName(String? displayName, {String? email, String fallback = 'Unbekannt'}) {
  final trimmed = (displayName ?? '').trim();
  if (trimmed.isNotEmpty) return trimmed;
  if (email == null || email.trim().isEmpty) return fallback;
  return deriveDisplayNameFromEmail(email.trim());
}

String deriveDisplayNameFromEmail(String email) {
  final trimmed = email.trim();
  final atIndex = trimmed.indexOf('@');
  if (atIndex <= 0) return trimmed;

  final localPart = trimmed.substring(0, atIndex);
  if (localPart.isEmpty) return trimmed;

  final tokens = localPart.split(RegExp(r'[._-]+')).where((t) => t.isNotEmpty).toList();
  if (tokens.isEmpty) return trimmed;

  final normalizedTokens = tokens.map((token) {
    if (token.length <= 1) return token.toUpperCase();
    final first = token[0].toUpperCase();
    final rest = token.substring(1).toLowerCase();
    return '$first$rest';
  });

  final result = normalizedTokens.join(' ');
  return result.isEmpty ? trimmed : result;
}
