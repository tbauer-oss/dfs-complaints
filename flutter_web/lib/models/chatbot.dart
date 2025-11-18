class ChatbotMessage {
  final String role; // 'user' oder 'assistant'
  final String message;

  const ChatbotMessage._(this.role, this.message);

  factory ChatbotMessage.user(String message) => ChatbotMessage._('user', message);
  factory ChatbotMessage.assistant(String message) => ChatbotMessage._('assistant', message);

  Map<String, dynamic> toJson() => {'role': role, 'message': message};
}

class ChatbotSource {
  final String id;
  final String title;
  final List<String> tags;
  final double? score;

  const ChatbotSource({
    required this.id,
    required this.title,
    required this.tags,
    this.score,
  });

  factory ChatbotSource.fromJson(Map<String, dynamic> json) {
    final tags = (json['tags'] as List?)?.whereType<String>().toList(growable: false) ?? const [];
    final scoreRaw = json['score'];
    final double? score;
    if (scoreRaw is num) {
      score = scoreRaw.toDouble();
    } else {
      score = null;
    }
    return ChatbotSource(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      tags: tags,
      score: score,
    );
  }
}

class ChatbotAnswer {
  final String answer;
  final List<ChatbotSource> sources;
  final bool usedOpenAI;
  final bool fallback;

  const ChatbotAnswer({
    required this.answer,
    required this.sources,
    required this.usedOpenAI,
    required this.fallback,
  });

  bool get isFallback => fallback || !usedOpenAI;

  factory ChatbotAnswer.fromJson(Map<String, dynamic> json) {
    final meta = json['metadata'];
    return ChatbotAnswer(
      answer: json['answer']?.toString() ?? '',
      sources: (json['sources'] as List?)
              ?.map((item) {
                if (item is Map<String, dynamic>) return ChatbotSource.fromJson(item);
                if (item is Map) {
                  return ChatbotSource.fromJson(
                    item.map((key, value) => MapEntry(key.toString(), value)),
                  );
                }
                return null;
              })
              .whereType<ChatbotSource>()
              .toList(growable: false) ??
          const [],
      usedOpenAI: meta is Map && meta['usedOpenAI'] == true,
      fallback: meta is Map && meta['fallback'] == true,
    );
  }
}
