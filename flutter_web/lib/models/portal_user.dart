class PortalUserSummary {
  final String email;
  final String displayName;
  final String fullName;
  final String firstName;
  final String lastName;
  final String username;
  final String role;
  final String portalStatus;
  final bool isPrrc;
  final List<String> assignedDepartments;

  const PortalUserSummary({
    required this.email,
    required this.displayName,
    this.fullName = '',
    this.firstName = '',
    this.lastName = '',
    this.username = '',
    required this.role,
    required this.portalStatus,
    this.isPrrc = false,
    this.assignedDepartments = const [],
  });

  factory PortalUserSummary.fromJson(Map<String, dynamic> json) => PortalUserSummary(
        email: (json['email'] ?? '').toString(),
        displayName: (json['displayName'] ?? json['contact'] ?? json['company'] ?? '').toString(),
        fullName: (json['fullName'] ?? json['full_name'] ?? '').toString(),
        firstName: (json['firstName'] ?? json['firstname'] ?? json['first_name'] ?? '').toString(),
        lastName: (json['lastName'] ?? json['lastname'] ?? json['last_name'] ?? '').toString(),
        username: (json['username'] ?? json['userName'] ?? '').toString(),
        role: (json['role'] ?? '').toString(),
        portalStatus: (json['portalStatus'] ?? '').toString(),
        isPrrc: json['isPRRC'] == true || json['isPrrc'] == true,
        assignedDepartments: (json['assignedDepartments'] as List?)
                ?.whereType<String>()
                .where((d) => d.trim().isNotEmpty)
                .toList(growable: false) ??
            const [],
      );

  String get resolvedDisplayName {
    final composedName = [firstName, lastName].map((v) => v.trim()).where((v) => v.isNotEmpty).join(' ').trim();
    final candidates = [displayName, fullName, composedName, username];
    for (final candidate in candidates) {
      final name = candidate.trim();
      if (name.isNotEmpty) return name;
    }
    return '';
  }

  String get label => resolvedDisplayName.isNotEmpty ? resolvedDisplayName : 'Unbekannter Nutzer';

  String get sortKey => label.toLowerCase();
}
