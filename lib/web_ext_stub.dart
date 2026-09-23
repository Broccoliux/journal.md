/// VM-safe stubs for [web_ext] — selected when not compiling for the web
/// (unit tests, analysis). Every browser feature degrades quietly; nothing
/// here should ever be reachable in a shipped web build.
library;

import 'dart:typed_data';

bool prefersReducedMotion() => false;

bool microphoneSupported() => false;

String createBlobUrl(Uint8List bytes, String? mime) =>
    throw UnsupportedError('blob URLs are web-only');

void revokeBlobUrl(String url) {}

void downloadBytes(Uint8List bytes, String filename, {String? mime}) =>
    throw UnsupportedError('downloads are web-only');

Future<Uint8List?> fetchBlobBytes(String url) async => null;

void onTabHidden(void Function() onHide) {}

void openInNewTab(String url) {}
