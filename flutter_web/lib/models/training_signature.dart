class TrainingSignContext {
  const TrainingSignContext({
    required this.sessionId,
    required this.trainingTitle,
    required this.participantDisplayName,
    required this.companyName,
    required this.requiresCheckbox,
    required this.expiresAt,
  });

  final String sessionId;
  final String trainingTitle;
  final String participantDisplayName;
  final String companyName;
  final bool requiresCheckbox;
  final int expiresAt;

  factory TrainingSignContext.fromJson(Map<String, dynamic> json) {
    return TrainingSignContext(
      sessionId: (json['sessionId'] ?? '').toString(),
      trainingTitle: (json['trainingTitle'] ?? '').toString(),
      participantDisplayName: (json['participantDisplayName'] ?? '').toString(),
      companyName: (json['companyName'] ?? '').toString(),
      requiresCheckbox: json['requiresCheckbox'] == true,
      expiresAt: json['expiresAt'] == null ? 0 : int.parse(json['expiresAt'].toString()),
    );
  }
}

class TrainingSignatureTokenResponse {
  const TrainingSignatureTokenResponse({
    required this.url,
    required this.expiresAt,
  });

  final String url;
  final int expiresAt;

  factory TrainingSignatureTokenResponse.fromJson(Map<String, dynamic> json) {
    return TrainingSignatureTokenResponse(
      url: (json['url'] ?? '').toString(),
      expiresAt: json['expiresAt'] == null ? 0 : int.parse(json['expiresAt'].toString()),
    );
  }
}
