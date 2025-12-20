String normalizeEmail(String value) {
  final replaced = value.replaceAll('\u00A0', ' ');
  final collapsed = replaced.replaceAll(RegExp(r'\s+'), ' ');
  return collapsed.trim();
}

bool isValidEmail(String value) {
  final normalized = normalizeEmail(value);
  if (normalized.isEmpty) return false;
  if (normalized.contains(' ')) return false;
  final parts = normalized.split('@');
  if (parts.length != 2) return false;
  final localPart = parts[0];
  final domainPart = parts[1];
  if (localPart.isEmpty) return false;
  if (domainPart.length < 3) return false;
  if (!domainPart.contains('.')) return false;
  if (domainPart.contains('..')) return false;
  final domainParts = domainPart.split('.');
  if (domainParts.any((part) => part.isEmpty)) return false;
  final tld = domainParts.last;
  if (tld.length < 2) return false;
  return true;
}
