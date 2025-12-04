// lib/web_compat/html_stub.dart
library html_stub;

class Navigator { String userAgent = ''; }
class Location { String origin = ''; String href = ''; }

class Window {
  final Map<String, String> localStorage = <String, String>{};
  final Navigator navigator = Navigator();
  final Location location = Location();
  void addEventListener(String type, void Function(dynamic)? cb) {}
  void removeEventListener(String type, void Function(dynamic)? cb) {}
  void dispatchEvent(dynamic e) {}
  void open(String url, String target) {} // no-op
}
final Window window = Window();

class Document {
  String title = '';
  void addEventListener(String type, void Function(dynamic)? cb) {}
  void removeEventListener(String type, void Function(dynamic)? cb) {}
  void dispatchEvent(dynamic e) {}
}
final Document document = Document();

class Style { String border = ''; String width = ''; String height = ''; }

class IFrameElement {
  String? src;
  final Style style = Style();
}

class ProgressEvent { const ProgressEvent(); }

class HttpRequest {
  int? status;
  String responseText = '';
  Future<void> open(String method, String url, {bool async = true}) async {}
  Future<void> send([dynamic body]) async {}
  set onload(void Function(ProgressEvent e)? handler) {}
  set onerror(void Function(ProgressEvent e)? handler) {}
}
