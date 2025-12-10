class PortalUserSummary {
  final String email;
  final String displayName;
  final String role;
  final String portalStatus;
  final bool isPrrc;

  const PortalUserSummary({
    required this.email,
    required this.displayName,
    required this.role,
    required this.portalStatus,
    this.isPrrc = false,
  });

  factory PortalUserSummary.fromJson(Map<String, dynamic> json) => PortalUserSummary(
        email: (json['email'] ?? '').toString(),
        displayName: (json['displayName'] ?? json['contact'] ?? json['company'] ?? '').toString(),
        role: (json['role'] ?? '').toString(),
        portalStatus: (json['portalStatus'] ?? '').toString(),
        isPrrc: json['isPRRC'] == true || json['isPrrc'] == true,
      );

  String get label => displayName.isNotEmpty ? displayName : email;
}
