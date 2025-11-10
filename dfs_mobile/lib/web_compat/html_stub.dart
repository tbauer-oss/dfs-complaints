// Minimaler Stub, damit der Code kompiliert – wird auf Nicht-Web benutzt.
class _FakeWindow {
  final Map<String, String> localStorage = {};
  final _Navigator navigator = _Navigator();
  final _Location location = _Location();
  void addEventListener(String _type, Function(dynamic) _cb) {}
  void open(String _url, String _target) {}
}
class _Navigator { String userAgent = ''; }
class _Location { String origin = ''; }

class HttpRequest {}
class ProgressEvent {}
class IFrameElement {}

final _FakeWindow window = _FakeWindow();
final dynamic document = null;
