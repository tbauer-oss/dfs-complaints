class AdminRepSummary {
  final String id;
  final String firstName;
  final String lastName;
  final String email;

  const AdminRepSummary({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.email,
  });

  String get label {
    final parts = [firstName.trim(), lastName.trim()].where((p) => p.isNotEmpty).toList();
    final name = parts.isEmpty ? '' : parts.join(' ');
    if (name.isNotEmpty) return '$name (${email.trim()})';
    return email.trim();
  }

  factory AdminRepSummary.fromJson(Map<String, dynamic> json) {
    return AdminRepSummary(
      id: (json['id'] ?? '').toString(),
      firstName: (json['firstName'] ?? '').toString(),
      lastName: (json['lastName'] ?? '').toString(),
      email: (json['email'] ?? '').toString(),
    );
  }
}
