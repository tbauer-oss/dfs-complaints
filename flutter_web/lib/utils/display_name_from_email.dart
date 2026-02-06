String displayNameFromEmail(String email) {
  final trimmed = email.trim();
  final atIndex = trimmed.indexOf('@');
  if (atIndex <= 0) return trimmed;

  final localPart = trimmed.substring(0, atIndex);
  if (localPart.isEmpty) return trimmed;

  final tokens = localPart
      .split(RegExp(r'[._-]+'))
      .where((t) => t.isNotEmpty)
      .map((token) {
    final stripped = token.replaceAll(RegExp(r'^[0-9]+|[0-9]+\$'), '');
    return stripped.isEmpty ? token : stripped;
  }).toList();
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
