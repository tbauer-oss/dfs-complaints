// lib/web_compat/html_stub.dart
//
// Minimaler, crash-sicherer Stub für Nicht-Web-Plattformen.
// Wird über den bedingten Import verwendet, wenn 'dart.library.html' NICHT verfügbar ist.

library html_stub;

// --- Window, Navigator, Location ---

class Navigator {
  String userAgent = '';
}

class Location {
  String origin = '';
  String href = '';
}

class Window {
  final Map<String, String> localStorage = <String, String>{};
  final Navigator navigator = Navigator();
  final Location location = Location();

  void addEventListener(String type, void Function(dynamic)? cb) {}
  void removeEventListener(String type, void Function(dynamic)? cb) {}
  void dispatchEvent(dynamic e) {}

  void open(String url, String target) {
    // no-op auf Mobile/Desktop
  }
}

// Ein einziges globales window-Objekt:
final Window window = Window();

// Optionales Document-Placeholder (wird meist nicht gebraucht)
class Document {
  void addEventListener(String type, void Function(dynamic)? cb) {}
}
final Document? document = null;

// --- DOM-ähnliche Elemente, die du verwendest ---

class Style {
  String border = '';
  String width = '';
  String height = '';
}

class IFrameElement {
  String? src;
  final Style style = Style();
}

// --- HttpRequest- und ProgressEvent-Stubs (falls noch referenziert) ---

class ProgressEvent {
  const ProgressEvent();
}

class HttpRequest {
  int? status;
  String responseText = '';

  // API grob nachgebildet – tut auf Mobile nichts.
  Future<void> open(String method, String url, {bool async = true}) async {}
  Future<void> send([dynamic body]) async {}

  // Event-Handler (werden ignoriert)
  set onload(void Function(ProgressEvent e)? handler) {}
  set onerror(void Function(ProgressEvent e)? handler) {}
}
