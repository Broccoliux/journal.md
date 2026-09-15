/// ZIP packaging for portable journals.
///
/// The exported folder is what the user should be able to read; the archive is
/// only how a browser moves that folder in one download. Keeping it separate
/// means the format itself never depends on the container.
library;

import 'dart:typed_data';

import 'package:archive/archive.dart';

import 'portable.dart';

/// Packs a bundle into a `.zip` whose entries are prefixed with the folder
/// name, e.g. `ai-learning/journal/2026-09-01.md`.
Uint8List encodeBundle(Bundle bundle) {
  final Archive archive = Archive();
  for (final MapEntry<String, List<int>> entry in bundle.prefixed.entries) {
    archive.addFile(ArchiveFile(entry.key, entry.value.length, entry.value));
  }
  final Uint8List data = Uint8List.fromList(ZipEncoder().encode(archive));
  if (data.isEmpty) {
    throw const FormatException('Could not build the archive.');
  }
  return data;
}

/// Unpacks a `.zip` back into a bundle.
///
/// Throws [FormatException] with a readable message when the file is not a
/// usable archive, so the UI never shows a raw decoder error.
Bundle decodeArchive({
  required String archiveName,
  required Uint8List bytes,
}) {
  final Archive archive;
  try {
    archive = ZipDecoder().decodeBytes(bytes, verify: true);
  } catch (_) {
    throw FormatException(
      '"$archiveName" is not a readable .zip file. Export a journal from '
      'journal.md and import that file.',
    );
  }

  final Map<String, List<int>> files = <String, List<int>>{};
  for (final ArchiveFile file in archive.files) {
    if (!file.isFile) continue;
    final String name = _clean(file.name);
    if (name.isEmpty) continue;
    final Object? content = file.content;
    if (content is Uint8List) {
      files[name] = content;
    } else if (content is List<int>) {
      files[name] = Uint8List.fromList(content);
    }
  }

  if (files.isEmpty) {
    throw FormatException('"$archiveName" did not contain any files.');
  }
  return Bundle(folder: _sharedFolder(files.keys) ?? _baseName(archiveName), files: files);
}

String _clean(String path) =>
    path.replaceAll('\\', '/').replaceFirst(RegExp(r'^\./'), '');

/// The single folder every path sits under, if there is one.
String? _sharedFolder(Iterable<String> paths) {
  String? shared;
  for (final String path in paths) {
    final int slash = path.indexOf('/');
    if (slash <= 0) return null;
    final String head = path.substring(0, slash);
    if (shared == null) {
      shared = head;
    } else if (shared != head) {
      return null;
    }
  }
  return shared;
}

/// `ai-learning.zip` → `ai-learning`.
String _baseName(String fileName) {
  final String name = fileName.split('/').last.split('\\').last;
  final String withoutExt = name.replaceFirst(
    RegExp(r'\.(zip|md)$', caseSensitive: false),
    '',
  );
  return withoutExt.isEmpty ? 'imported-journal' : withoutExt;
}
