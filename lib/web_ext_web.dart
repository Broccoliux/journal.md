/// Real browser implementations for [web_ext] — selected when compiling for
/// the web (dart2js / DDC).
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Whether the user asked the OS for reduced motion.
bool prefersReducedMotion() {
  try {
    return web.window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  } catch (_) {
    return false;
  }
}

/// True when MediaRecorder + getUserMedia exist (voice note support).
bool microphoneSupported() {
  try {
    return web.window.navigator.has('mediaDevices') &&
        web.window.has('MediaRecorder');
  } catch (_) {
    return false;
  }
}

/// Create a blob object URL for [bytes] with an optional [mime] type.
String createBlobUrl(Uint8List bytes, String? mime) {
  final blob = web.Blob(
    <web.BlobPart>[bytes.toJS].toJS,
    web.BlobPropertyBag(type: mime ?? 'application/octet-stream'),
  );
  return web.URL.createObjectURL(blob);
}

void revokeBlobUrl(String url) {
  try {
    web.URL.revokeObjectURL(url);
  } catch (_) {}
}

/// Download [bytes] as a file named [filename] via the browser.
void downloadBytes(Uint8List bytes, String filename, {String? mime}) {
  final url = createBlobUrl(bytes, mime);
  final a = web.document.createElement('a') as web.HTMLAnchorElement;
  a.href = url;
  a.download = filename;
  a.rel = 'noopener';
  web.document.body?.appendChild(a);
  a.click();
  a.remove();
  // Give the browser a moment to start the download before releasing.
  Future.delayed(const Duration(seconds: 30), () => revokeBlobUrl(url));
}

/// Fetch a blob/object URL back into bytes (used after stopping a recording).
Future<Uint8List?> fetchBlobBytes(String url) async {
  try {
    final response = await web.window.fetch(url.toJS).toDart;
    if (!response.ok) return null;
    final buffer = await response.arrayBuffer().toDart;
    return buffer.toDart.asUint8List();
  } catch (_) {
    return null;
  }
}

/// Calls [onHide] whenever the tab becomes hidden (used to flush autosave).
void onTabHidden(void Function() onHide) {
  try {
    web.document.addEventListener(
      'visibilitychange',
      ((JSAny _) {
        if (web.document.visibilityState == 'hidden') onHide();
      }).toJS,
    );
  } catch (_) {}
}

/// Opens a URL in a new tab (markdown links).
void openInNewTab(String url) {
  try {
    web.window.open(url, '_blank');
  } catch (_) {}
}
