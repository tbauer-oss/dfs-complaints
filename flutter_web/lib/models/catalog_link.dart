class CatalogLink {
  String label;
  String url;
  Set<String> locales;

  CatalogLink({
    required this.label,
    required this.url,
    required this.locales,
  });

  factory CatalogLink.fromJson(Map<String, dynamic> j) {
    return CatalogLink(
      label: (j['label'] ?? '').toString(),
      url: (j['url'] ?? '').toString(),
      locales: ((j['locales'] as List?) ?? const [])
          .map((e) => e.toString())
          .where((s) => s.trim().isNotEmpty)
          .map((s) => s.trim())
          .toSet(),
    );
  }

  Map<String, dynamic> toJson() => {
    'label': label,
    'url': url,
    'locales': locales.toList(),
  };
}
