import '../../api/client.dart';

class RegulatoryApi {
  final ApiClient client;
  const RegulatoryApi(this.client);

  Future<List<Map<String, dynamic>>> getDocs() async => client.regulatoryDocs();
  Future<Map<String, dynamic>> getStatus(String slug) async => client.regulatoryStatus(slug);
  Future<Map<String, dynamic>> getDiff(String slug, {bool force = false}) => client.regulatoryDiff(slug, force: force);
  Future<Map<String, dynamic>> apply(String slug, String syncToken) =>
      client.regulatoryApply(slug, syncToken: syncToken);
  Future<Map<String, dynamic>> fetchSection(String slug, String key, {String side = 'current', String? token}) =>
      client.regulatorySection(slug, key: key, side: side, token: token);
}
