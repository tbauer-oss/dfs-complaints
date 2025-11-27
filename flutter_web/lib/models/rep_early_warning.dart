class RepEarlyWarning {
  final String id;
  final String type; // article | customer | productGroup
  final String level; // info | warn | critical
  final String title;
  final String description;
  final String? productGroup;
  final String? customerEmail;
  final String? productName;
  final List<String> articleNumbers;
  final int recentCount;
  final int previousCount;
  final double? changePercent;

  const RepEarlyWarning({
    required this.id,
    required this.type,
    required this.level,
    required this.title,
    required this.description,
    required this.articleNumbers,
    required this.recentCount,
    required this.previousCount,
    this.productGroup,
    this.customerEmail,
    this.productName,
    this.changePercent,
  });

  factory RepEarlyWarning.fromJson(Map<String, dynamic> json) {
    List<String> _pickList(dynamic v) {
      if (v is List) return v.map((e) => e.toString()).toList(growable: false);
      return const [];
    }

    double? _pickDouble(dynamic v) {
      if (v == null) return null;
      final n = double.tryParse(v.toString());
      return n;
    }

    return RepEarlyWarning(
      id: json['id']?.toString() ?? '',
      type: json['type']?.toString() ?? 'article',
      level: json['level']?.toString() ?? 'info',
      title: json['title']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      productGroup: (json['productGroup'] ?? '').toString().isEmpty
          ? null
          : json['productGroup'].toString(),
      productName: (json['productName'] ?? '').toString().isEmpty
          ? null
          : json['productName'].toString(),
      customerEmail: (json['customerEmail'] ?? '').toString().isEmpty
          ? null
          : json['customerEmail'].toString(),
      articleNumbers: _pickList(json['articleNumbers']),
      recentCount: int.tryParse(json['recentCount']?.toString() ?? '') ?? 0,
      previousCount: int.tryParse(json['previousCount']?.toString() ?? '') ?? 0,
      changePercent: _pickDouble(json['changePercent']),
    );
  }
}
