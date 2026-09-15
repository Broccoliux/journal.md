import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'web_io_stub.dart' show PickedFile;

/// Opens a native file chooser and reads the chosen files.
///
/// Resolves with an empty list when the user cancels, which is why a focus
/// based fallback is needed: `change` simply never fires in that case.
Future<List<PickedFile>> pickFiles({
  String accept = '',
  bool multiple = false,
}) async {
  final Completer<List<PickedFile>> completer =
      Completer<List<PickedFile>>();
  final web.HTMLInputElement input = web.HTMLInputElement();
  input.type = 'file';
  if (accept.isNotEmpty) input.accept = accept;
  input.multiple = multiple;
  input.style.display = 'none';
  web.document.body?.appendChild(input);

  bool settled = false;
  Timer? fallback;

  void finish(List<PickedFile> files) {
    if (settled) return;
    settled = true;
    fallback?.cancel();
    input.remove();
    if (!completer.isCompleted) completer.complete(files);
  }

  input.onchange = ((web.Event _) async {
    final List<PickedFile> out = <PickedFile>[];
    final web.FileList? list = input.files;
    if (list != null) {
      for (int i = 0; i < list.length; i++) {
        final web.File? file = list.item(i);
        if (file == null) continue;
        try {
          out.add(
            PickedFile(
              name: file.name,
              bytes: await _readFile(file),
              mime: file.type.isEmpty ? 'application/octet-stream' : file.type,
            ),
          );
        } catch (_) {
          // Skip an unreadable file rather than failing the whole selection.
        }
      }
    }
    finish(out);
  }).toJS;

  // The chooser steals focus; when it comes back without a change, treat it as
  // a cancel so the UI never waits forever.
  web.window.onfocus = ((web.Event _) {
    fallback ??= Timer(const Duration(milliseconds: 900), () {
      finish(<PickedFile>[]);
    });
  }).toJS;

  input.click();
  return completer.future;
}

Future<Uint8List> _readFile(web.File file) async {
  final JSArrayBuffer buffer = await file.arrayBuffer().toDart;
  return buffer.toDart.asUint8List();
}

/// Saves bytes to the browser's downloads.
void downloadBytes({
  required String fileName,
  required Uint8List bytes,
  required String mime,
}) {
  final web.Blob blob = web.Blob(
    <JSAny>[bytes.toJS].toJS,
    web.BlobPropertyBag(type: mime),
  );
  final String url = web.URL.createObjectURL(blob);
  final web.HTMLAnchorElement anchor = web.HTMLAnchorElement()
    ..href = url
    ..download = fileName
    ..style.display = 'none';
  web.document.body?.appendChild(anchor);
  anchor.click();
  anchor.remove();
  // Give the browser a moment to start the download before releasing the URL.
  Timer(const Duration(seconds: 20), () => web.URL.revokeObjectURL(url));
}

/// Opens a URL in a new tab.
void openExternal(String url) {
  web.window.open(url, '_blank', 'noopener,noreferrer');
}

/// A blob URL so in-memory media can be handed to the browser's own players.
String createObjectUrl(Uint8List bytes, String mime) {
  final web.Blob blob = web.Blob(
    <JSAny>[bytes.toJS].toJS,
    web.BlobPropertyBag(type: mime),
  );
  return web.URL.createObjectURL(blob);
}

void revokeObjectUrl(String url) {
  if (url.isEmpty) return;
  web.URL.revokeObjectURL(url);
}