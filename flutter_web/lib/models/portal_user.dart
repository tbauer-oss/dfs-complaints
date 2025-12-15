class PortalUserSummary {
  final String email;
  final String displayName;
  final String role;
  final String portalStatus;
  final bool isPrrc;
  final List<String> assignedDepartments;

  const PortalUserSummary({
    required this.email,
    required this.displayName,
    required this.role,
    required this.portalStatus,
    this.isPrrc = false,
    this.assignedDepartments = const [],
  });

  factory PortalUserSummary.fromJson(Map<String, dynamic> json) => PortalUserSummary(
        email: (json['email'] ?? '').toString(),
        displayName: (json['displayName'] ?? json['contact'] ?? json['company'] ?? '').toString(),
        role: (json['role'] ?? '').toString(),
        portalStatus: (json['portalStatus'] ?? '').toString(),
        isPrrc: json['isPRRC'] == true || json['isPrrc'] == true,
        assignedDepartments: (json['assignedDepartments'] as List?)
                ?.whereType<String>()
                .where((d) => d.trim().isNotEmpty)
                .toList(growable: false) ??
            const [],
      );

  String get label => displayName.isNotEmpty ? displayName : email;
}
