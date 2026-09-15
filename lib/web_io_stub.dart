import 'dart:typed_data';

/// Browser integration that only exists on the web: picking files, saving
/// downloads and opening links.
///
/// Kept behind one small facade so the rest of the app never touches DOM APIs
/// and unit tests can still compile and run.
class PickedFile {
  const PickedFile({required this.name, required this.bytes, required this.mime});

  final String name;
  final Uint8List bytes;
  final String mime;
}

/// Opens the browser's file chooser. Returns an empty list if cancelled.
Future<List<PickedFile>> pickFiles({
  String accept = '',
  bool multiple = false,
}) => throw UnsupportedError('File picking is only available in a browser.');

/// Saves bytes to the user's downloads.
void downloadBytes({
  required String fileName,
  required Uint8List bytes,
  required String mime,
}) => throw UnsupportedError('Downloads are only available in a browser.');

/// Opens a URL in a new tab.
void openExternal(String url) =>
    throw UnsupportedError('Opening links is only available in a browser.');

/// A blob URL for in-memory media, used to hand bytes to <audio>/<img>.
String createObjectUrl(Uint8List bytes, String mime) =>
    throw UnsupportedError('Object URLs are only available in a browser.');

void revokeObjectUrl(String url) {}
