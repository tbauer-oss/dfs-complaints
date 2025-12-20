String normalizeEmail(String value) {
  final replaced = value.replaceAll('\u00A0', ' ');
  final collapsed = replaced.replaceAll(RegExp(r'\s+'), ' ');
  return collapsed.trim();
}

bool isValidEmail(String value) {
  final normalized = normalizeEmail(value);
  if (normalized.isEmpty) return false;
  if (normalized.contains(' ')) return false;
  final regex = RegExp(r'^[A-Za-z0-9.!#$%&\'*+/=?^_`{|}~-]+@'
      r'[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+$');
  return regex.hasMatch(normalized);
}
