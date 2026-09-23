/// Import / export for journal.md.
///
/// Export builds a zip a human can read:
///
/// ```text
/// manifest.json
/// Daily/2026-09-23.md
/// Projects/keyboard-project.md
/// assets/image-001.png
/// assets/voice-001.webm
/// ```
///
/// Every entry is a markdown file with a small front-matter header (title,
/// date, tags). `manifest.json` carries the metadata needed to restore the
/// data exactly as it was — including internal ids, so importing a backup
/// twice never duplicates anything.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import 'format_util.dart';
import 'models.dart';
import 'store.dart';
import 'web_ext.dart';

// --------------------------------------------------------------------- export

/// Builds the export zip. Public so a test can roundtrip it without a browser.
Uint8List buildExportZip(Store store) {
  final archive = Archive();
  final assetPaths = <String, String>{}; // attachment id → zip path
  final assetCounters = <String, int>{};

  // Allocate readable asset names: image-001.png, voice-001.webm…
  final attachments = <Attachment, String>{}; // attachment → zip path
  final seenAttachmentIds = <String>{};
  for (final entry in store.entries.values) {
    for (final a in entry.attachments) {
      if (!seenAttachmentIds.add(a.id)) continue;
      final prefix = a.isAudio ? 'voice' : 'image';
      final n = (assetCounters[prefix] ?? 0) + 1;
      assetCounters[prefix] = n;
      final ext = extensionForMime(a.mime);
      final path = 'assets/$prefix-${n.toString().padLeft(3, '0')}.$ext';
      assetPaths[a.id] = path;
      attachments[a] = path;
    }
  }

  // One folder per journal, with readable, unique folder names.
  final folders = <String, String>{}; // journal id → folder
  final usedFolders = <String>{};
  for (final j in store.journals) {
    var folder = sanitizeFolderName(j.name);
    if (folder.toLowerCase() == 'assets') folder = 'journal-assets';
    var candidate = folder;
    var n = 1;
    while (usedFolders.contains(candidate)) {
      n++;
      candidate = '$folder-$n';
    }
    usedFolders.add(candidate);
    folders[j.id] = candidate;
  }

  // Entry markdown files with front matter.
  final entryFiles = <Map<String, dynamic>>[]; // manifest entry records
  final perFolder = <String, Set<String>>{};

  for (final journal in store.journals) {
    final folder = folders[journal.id]!;
    final names = perFolder.putIfAbsent(folder, () => <String>{});

    for (final entry in store.entriesOf(journal.id)) {
      var base = entry.title.trim().isEmpty
          ? _isoDay(entry.date)
          : slugify(entry.title);
      if (base.isEmpty) base = 'entry';
      var fileName = '$base.md';
      var n = 1;
      while (names.contains(fileName)) {
        n++;
        fileName = '$base-$n.md';
      }
      names.add(fileName);

      // Rewrite attachment: refs into export paths so the file reads naturally.
      var content = entry.content;
      for (final a in entry.attachments) {
        final path = assetPaths[a.id];
        if (path != null) {
          content =
              content.replaceAll('attachment:${a.id}', path);
        }
      }

      final file = '$folder/$fileName';
      archive.addFile(ArchiveFile.string(file, _entryMarkdown(entry, content)));

      entryFiles.add({
        'id': entry.id,
        'journalId': entry.journalId,
        'title': entry.title,
        'date': _iso(entry.date),
        'tags': entry.tags,
        'file': file,
        'attachments': [
          for (final a in entry.attachments)
            {
              'id': a.id,
              'kind': a.kind,
              'name': a.name,
              'mime': a.mime,
              'size': a.size,
              'file': assetPaths[a.id],
            }
        ],
      });
    }
  }

  // Asset blobs.
  for (final MapEntry(:key, :value) in attachments.entries) {
    final bytes = store.asset(key.id);
    if (bytes != null) {
      archive.addFile(ArchiveFile(value, bytes.length, bytes));
    }
  }

  // Manifest ties it all together.
  final manifest = jsonEncode({
    'app': 'journal.md',
    'format': 1,
    'exportedAt': _iso(DateTime.now().millisecondsSinceEpoch),
    'journals': [
      for (final j in store.journals)
        {
          'id': j.id,
          'name': j.name,
          'description': j.description,
          'createdAt': _iso(j.createdAt),
          'updatedAt': _iso(j.updatedAt),
        }
    ],
    'entries': entryFiles,
  });
  archive.addFile(ArchiveFile.string('manifest.json', manifest));

  return ZipEncoder().encodeBytes(archive);
}

String _entryMarkdown(Entry entry, String content) {
  final buffer = StringBuffer();
  buffer.writeln('---');
  buffer.writeln('title: ${entry.title.isEmpty ? 'Untitled' : entry.title}');
  buffer.writeln('date: ${_iso(entry.date)}');
  if (entry.tags.isNotEmpty) {
    buffer.writeln('tags: ${entry.tags.join(', ')}');
  }
  buffer.writeln('id: ${entry.id}');
  buffer.writeln('---');
  buffer.writeln();
  buffer.write(content);
  if (!content.endsWith('\n')) buffer.writeln();
  return buffer.toString();
}

String _iso(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  String two(int n) => n.toString().padLeft(2, '0');
  return '${d.year}-${two(d.month)}-${two(d.day)}'
      'T${two(d.hour)}:${two(d.minute)}';
}

String _isoDay(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  String two(int n) => n.toString().padLeft(2, '0');
  return '${d.year}-${two(d.month)}-${two(d.day)}';
}

/// Exports everything and triggers a browser download.
void exportAll(Store store) {
  final bytes = buildExportZip(store);
  final stamp = _isoDay(DateTime.now().millisecondsSinceEpoch);
  downloadBytes(bytes, 'journal-md-export-$stamp.zip', mime: 'application/zip');
}

// --------------------------------------------------------------------- import

class ImportResult {
  ImportResult({
    required this.journals,
    required this.entries,
    required this.assets,
    required this.skipped,
  });

  final int journals;
  final int entries;
  final int assets;
  final int skipped;

  bool get isEmpty => journals == 0 && entries == 0 && assets == 0;
}

class ImportFailure implements Exception {
  ImportFailure(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Parses an exported zip back into journals / entries / asset bytes.
({List<Journal> journals, List<Entry> entries, Map<String, Uint8List> assets})
    parseImportZip(Uint8List bytes) {
  Archive archive;
  try {
    archive = ZipDecoder().decodeBytes(bytes);
  } catch (_) {
    throw ImportFailure('That file is not a readable journal.md backup (zip).');
  }

  // Find manifest.json — at the root, or inside a single wrapping folder.
  var prefix = '';
  ArchiveFile? manifestFile;
  for (final f in archive.files) {
    if (!f.isFile) continue;
    if (f.name == 'manifest.json' || f.name.endsWith('/manifest.json')) {
      manifestFile = f;
      prefix = f.name == 'manifest.json'
          ? ''
          : f.name.substring(0, f.name.length - 'manifest.json'.length);
      break;
    }
  }
  if (manifestFile == null) {
    throw ImportFailure(
        'No manifest.json inside — is this a journal.md export?');
  }

  Map<String, dynamic> manifest;
  try {
    manifest =
        jsonDecode(utf8.decode(manifestFile.content)) as Map<String, dynamic>;
  } catch (_) {
    throw ImportFailure('The backup manifest is corrupted.');
  }

  final filesByName = <String, Uint8List>{
    for (final f in archive.files)
      if (f.isFile) f.name: f.content
  };

  Uint8List? readFile(String? path) {
    if (path == null) return null;
    return filesByName['$prefix$path'] ?? filesByName[path];
  }

  // Journals keep their original ids so entries stay attached.
  final journals = <Journal>[];
  for (final j in (manifest['journals'] as List? ?? [])) {
    if (j is! Map<String, dynamic>) continue;
    journals.add(Journal(
      id: j['id'] as String,
      name: (j['name'] as String?) ?? 'Untitled',
      description: (j['description'] as String?) ?? '',
      createdAt: _parseIso(j['createdAt']) ?? 0,
      updatedAt: _parseIso(j['updatedAt']) ?? 0,
    ));
  }

  final assets = <String, Uint8List>{};
  final entries = <Entry>[];

  for (final e in (manifest['entries'] as List? ?? [])) {
    if (e is! Map<String, dynamic>) continue;
    final entryId = e['id'] as String? ?? newId();

    // Read the markdown body and strip front matter.
    final file = e['file'] as String?;
    var content = '';
    if (file != null) {
      final raw = readFile(file);
      if (raw != null) {
        content = _stripFrontMatter(utf8.decode(raw, allowMalformed: true));
      }
    }

    // Attachments: restore bytes + rewrite content refs to attachment:<id>.
    final attachments = <Attachment>[];
    for (final a in (e['attachments'] as List? ?? [])) {
      if (a is! Map<String, dynamic>) continue;
      final id = a['id'] as String? ?? newId();
      final path = a['file'] as String?;
      final bytes = readFile(path);
      final attachment = Attachment(
        id: id,
        kind: (a['kind'] as String?) ?? 'image',
        name: (a['name'] as String?) ?? 'file',
        mime: a['mime'] as String?,
        size: (a['size'] as num?)?.toInt() ?? bytes?.length ?? 0,
        createdAt: _parseIso(e['date']) ?? 0,
      );
      attachments.add(attachment);
      if (bytes != null) {
        assets[id] = bytes;
        if (path != null) {
          // Rewrite readable export refs back to internal ones.
          content = content.replaceAll(path, 'attachment:$id');
        }
      }
    }

    final date = _parseIso(e['date']) ?? _parseIso(e['createdAt']) ?? 0;
    entries.add(Entry(
      id: entryId,
      journalId: (e['journalId'] as String?) ?? '',
      title: (e['title'] as String?) ?? '',
      date: date,
      createdAt: date,
      updatedAt: date,
      tags: [
        for (final t in (e['tags'] as List? ?? []))
          t.toString().toLowerCase().trim()
      ]..removeWhere((t) => t.isEmpty),
      content: content,
      attachments: attachments,
    ));
  }

  // Journals with no entries still need folder presence… nothing to restore.
  return (journals: journals, entries: entries, assets: assets);
}

/// Removes front matter (`---` header block) from an entry file, including
/// the blank separator line the exporter writes after it, so content
/// roundtrips exactly.
String _stripFrontMatter(String raw) {
  final text = raw.replaceFirst(RegExp(r'^\uFEFF'), '');
  if (!text.startsWith('---')) return text;
  final end = text.indexOf('\n---', 3);
  if (end < 0) return text;
  var rest = text.substring(end + 4);
  if (rest.startsWith('\n')) rest = rest.substring(1); // end of `---` line
  if (rest.startsWith('\n')) rest = rest.substring(1); // separator line
  return rest;
}

int? _parseIso(Object? value) {
  if (value is! String || value.isEmpty) return null;
  final parsed = DateTime.tryParse(value);
  if (parsed == null) return null;
  return parsed.millisecondsSinceEpoch;
}

// ------------------------------------------------------------------ UI glue

Future<void> runExport(BuildContext context, Store store) async {
  try {
    if (store.entries.isEmpty && store.journals.isEmpty) {
      _toast(context, 'Nothing to export yet — write something first.');
      return;
    }
    exportAll(store);
    _toast(context, 'Export started — check your downloads folder.');
  } catch (e) {
    _toast(context, 'Export failed: $e');
  }
}

Future<void> runImport(BuildContext context, Store store) async {
  try {
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(label: 'journal.md backup', extensions: ['zip']),
      ],
    );
    if (file == null) return; // cancelled

    final bytes = await file.readAsBytes();
    if (!context.mounted) return;
    if (bytes.isEmpty) {
      _toast(context, 'That file is empty.');
      return;
    }

    final parsed = parseImportZip(bytes);

    // Keep journal names unique against what already exists.
    final existingNames = {
      for (final j in store.journals) j.name.toLowerCase()
    };
    final usedNames = <String>{};
    String dedupe(String name) {
      var base = name.trim().isEmpty ? 'Imported' : name.trim();
      var candidate = base;
      var n = 1;
      while (existingNames.contains(candidate.toLowerCase()) ||
          usedNames.contains(candidate.toLowerCase())) {
        n++;
        candidate = '$base (imported $n)';
      }
      usedNames.add(candidate.toLowerCase());
      return candidate;
    }

    final result = await store.mergeImport(
      newJournals: parsed.journals,
      newEntries: parsed.entries,
      newAssets: parsed.assets,
      dedupeJournalName: dedupe,
    );
    if (!context.mounted) return;

    if (result.entries == 0 && result.journals == 0) {
      _toast(context,
          'Everything in this backup is already in your journal — nothing was duplicated.');
      return;
    }
    _toast(
      context,
      'Imported ${result.journals} journal${result.journals == 1 ? '' : 's'}, '
      '${result.entries} entri${result.entries == 1 ? 'y' : 'es'}'
      '${result.assets > 0 ? ' and ${result.assets} media file${result.assets == 1 ? '' : 's'}' : ''}.',
    );
  } on ImportFailure catch (e) {
    if (!context.mounted) return;
    _toast(context, e.message);
  } catch (e) {
    if (!context.mounted) return;
    _toast(context, 'Import failed: $e');
  }
}

void _toast(BuildContext context, String message) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}
