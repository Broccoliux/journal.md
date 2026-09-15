import 'dart:convert';
import 'dart:typed_data';

import 'models.dart';

/// Portable markdown format for journal.md.
///
/// Exports are plain files that any markdown reader can open:
///
/// ```text
/// my-journal/
/// ├── README.md
/// ├── journal/2026-09-01.md
/// └── assets/image.png
/// ```
///
/// Each entry keeps its identity in a small YAML front matter block and media
/// is referenced with relative paths, so the same folder imports back with
/// nothing lost. Nothing in here touches the browser: it works on bytes, which
/// is what makes the round trip testable.


/// A folder of files ready to become a `.zip` or to be imported.
class Bundle {
  Bundle({required this.folder, required this.files});

  /// Name of the top level folder.
  final String folder;

  /// Relative path (as written in markdown, e.g. `journal/2026-09-01.md`)
  /// mapped to file bytes.
  final Map<String, List<int>> files;

  /// Files plus the folder prefix: what actually goes into the archive.
  Map<String, List<int>> get prefixed => <String, List<int>>{
    for (final MapEntry<String, List<int>> e in files.entries)
      '${folder}/${e.key}': e.value,
  };

  int get totalBytes =>
      files.values.fold<int>(0, (int sum, List<int> b) => sum + b.length);
}

/// Outcome of reading a portable folder back in.
class ImportResult {
  ImportResult({
    required this.journal,
    required this.entries,
    required this.media,
    required this.warnings,
  });

  final Journal journal;
  final List<Entry> entries;
  final List<MediaRecord> media;

  /// Things the user should know about: missing files, skipped files, etc.
  final List<String> warnings;

  bool get isEmpty => entries.isEmpty;
}

// ------------------------------------------------------------- front matter

const String _fence = '---';

/// Splits a markdown file into its front matter map and its body.
Map<String, Object?> parseFrontMatter(
  String source, {
  required void Function(String body) onBody,
}) {
  final List<String> lines = const LineSplitter().convert(source);
  if (lines.isEmpty || lines.first.trim() != _fence) {
    onBody(source);
    return <String, Object?>{};
  }
  int end = -1;
  for (int i = 1; i < lines.length; i++) {
    if (lines[i].trim() == _fence) {
      end = i;
      break;
    }
  }
  if (end == -1) {
    // Unterminated block: keep the whole file as body so nothing is lost.
    onBody(source);
    return <String, Object?>{};
  }
  onBody(
    lines
        .sublist(end + 1)
        .join('\n')
        .replaceFirst(RegExp(r'^[\r\n]+'), ''),
  );
  return _parseSimpleYaml(lines.sublist(1, end));
}

/// A deliberately small YAML reader: scalars, comma lists and flow maps. That
/// is exactly the shape this app writes, so the format needs no dependency
/// while remaining valid YAML for other tools.
Map<String, Object?> _parseSimpleYaml(List<String> lines) {
  final Map<String, Object?> out = <String, Object?>{};
  String? listKey;
  List<String>? list;

  for (final String raw in lines) {
    if (raw.trim().isEmpty || raw.trimLeft().startsWith('#')) continue;
    final String line = raw.trimRight();

    if (line.startsWith(' ') && listKey != null && list != null) {
      final String item = line.trim();
      if (item.startsWith('- ')) list.add(item.substring(2).trim());
      continue;
    }

    final int colon = line.indexOf(':');
    if (colon <= 0) continue;
    final String key = line.substring(0, colon).trim();
    final String value = line.substring(colon + 1).trim();

    if (value.isEmpty) {
      listKey = key;
      list = <String>[];
      out[key] = list;
      continue;
    }
    listKey = null;
    list = null;
    out[key] = _scalar(value);
  }
  return out;
}

Object _scalar(String raw) {
  final String v = raw.trim();
  if (v.startsWith('"') && v.endsWith('"') && v.length >= 2) {
    try {
      return jsonDecode(v);
    } catch (_) {
      return v.substring(1, v.length - 1);
    }
  }
  if (v.contains(',')) {
    return v
        .split(',')
        .map((String s) => s.trim())
        .where((String s) => s.isNotEmpty)
        .toList();
  }
  return v;
}
/// Parses `{id: m_1, type: image}` into a map of strings.
Map<String, String> parseFlowMap(String raw) {
  final Map<String, String> out = <String, String>{};
  final String inner = raw.trim().replaceFirst('{', '').replaceFirst(
    RegExp(r'}$'),
    '',
  );
  final List<String> parts = <String>[];
  final StringBuffer current = StringBuffer();
  bool inQuotes = false;
  for (int i = 0; i < inner.length; i++) {
    final String ch = inner[i];
    if (ch == '"') inQuotes = !inQuotes;
    if (ch == ',' && !inQuotes) {
      parts.add(current.toString());
      current.clear();
    } else {
      current.write(ch);
    }
  }
  parts.add(current.toString());
  for (final String part in parts) {
    final int colon = part.indexOf(':');
    if (colon <= 0) continue;
    final String key = part.substring(0, colon).trim();
    final String value = part.substring(colon + 1).trim();
    if (key.isEmpty) continue;
    out[key] = '${_scalar(value)}';
  }
  return out;
}

const String _yamlSpecial = '#-?*&!|>%@`[]{}\"\' ';

/// Writes one `key: value` line, quoting only when YAML requires it.
String yamlLine(Object key, String value) => '$key: ${yamlValue(value)}';

String yamlValue(String value) {
  if (value.isEmpty) return '""';
  final bool risky =
      value != value.trim() ||
      value.contains(': ') ||
      value.contains('\n') ||
      value.contains('#') ||
      _yamlSpecial.contains(value[0]) ||
      RegExp(
        r'^(true|false|null|~|yes|no)$',
        caseSensitive: false,
      ).hasMatch(value);
  return risky ? jsonEncode(value) : value;
}

// -------------------------------------------------------------------- export

/// Writes a journal, all of its entries and the media they use into a folder
/// of plain markdown files.
Bundle exportJournal({
  required Journal journal,
  required List<Entry> entries,
  required List<MediaRecord> media,
}) {
  final List<Entry> ordered = List<Entry>.of(entries)
    ..sort((Entry a, Entry b) => a.date.compareTo(b.date));

  final Map<String, List<int>> files = <String, List<int>>{};
  final List<Map<String, String>> index = <Map<String, String>>[];
  final Set<String> usedNames = <String>{};

  for (final Entry entry in ordered) {
    final String name = _uniqueName(entry, usedNames);
    final String path = 'journal/$name';
    files[path] = utf8.encode(_entryFile(entry));
    index.add(<String, String>{
      'date': isoDay(entry.date),
      'title': entry.displayTitle,
      'path': path,
      'tags': entry.tags.map((String t) => '#$t').join(' '),
    });
  }

  // Copy media once, even if two entries share a file.
  final Set<String> copied = <String>{};
  for (final MediaRecord record in media) {
    final String path = record.ref.path;
    if (!copied.add(path)) continue;
    files[path] = record.bytes;
  }

  files['README.md'] = utf8.encode(
    _readmeFile(journal, ordered, index, copied),
  );

  return Bundle(folder: journal.slug, files: files);
}

String _uniqueName(Entry entry, Set<String> used) {
  final String title = slugify(entry.title);
  final String base = title == 'journal'
      ? isoDay(entry.date)
      : '${isoDay(entry.date)}-$title';
  String candidate = '$base.md';
  int n = 2;
  while (!used.add(candidate)) {
    candidate = '$base-$n.md';
    n++;
  }
  return candidate;
}

String _entryFile(Entry entry) {
  final StringBuffer out = StringBuffer()
    ..writeln(_fence)
    ..writeln('id: ${entry.id}')
    ..writeln(yamlLine('title', entry.title))
    ..writeln('date: ${entry.date.toIso8601String()}')
    ..writeln('created: ${entry.createdAt.toIso8601String()}')
    ..writeln('updated: ${entry.updatedAt.toIso8601String()}');
  if (entry.tags.isEmpty) {
    out.writeln('tags: []');
  } else {
    out.writeln('tags: ${entry.tags.join(', ')}');
  }
  if (entry.media.isEmpty) {
    out.writeln('media: []');
  } else {
    out.writeln('media:');
    for (final MediaRef m in entry.media) {
      out.writeln(
        '  - {id: ${m.id}, type: ${m.kind.name}, name: '
        '${yamlValue(m.name)}, file: ${m.path}, mime: ${m.mime}, '
        'size: ${m.size}, duration: ${m.duration}}',
      );
    }
  }
  out
    ..writeln(_fence)
    ..writeln();
  out.write(toPortableBody(entry.content).trimRight());
  out.writeln();
  return out.toString();
}

/// Rewrites in-app `assets/x` references into paths that resolve from
/// `journal/`, so the exported markdown renders correctly in any reader.
String toPortableBody(String content) =>
    content.replaceAll(RegExp(r'\]\((\.\./)*assets/'), '](../assets/');

/// The inverse of [toPortableBody].
String fromPortableBody(String content) =>
    content.replaceAll(RegExp(r'\]\((\.\./)+assets/'), '](assets/');

// -------------------------------------------------------------------- readme

String _readmeFile(
  Journal journal,
  List<Entry> ordered,
  List<Map<String, String>> index,
  Set<String> mediaPaths,
) {
  final StringBuffer out = StringBuffer()
    ..writeln('# ${journal.name}')
    ..writeln();
  if (journal.description.trim().isNotEmpty) {
    out
      ..writeln(journal.description.trim())
      ..writeln();
  }
  final DateTime? last = ordered.isEmpty
      ? null
      : ordered.last.updatedAt;
  out
    ..writeln('- **Created:** ${dateTimeLabel(journal.createdAt)}')
    ..writeln('- **Origin:** journal.md')
    ..writeln('- **Entries:** ${ordered.length}')
    ..writeln(
      '- **Updated:** ${last == null ? dateTimeLabel(journal.updatedAt) : dateTimeLabel(last)}',
    )
    ..writeln()
    ..writeln('Entries live in `journal/`, media in `assets/`.')
    ..writeln();

  if (index.isEmpty) {
    out
      ..writeln('## Entries')
      ..writeln()
      ..writeln('_This journal has no entries yet._')
      ..writeln();
  } else {
    out
      ..writeln('## Entries')
      ..writeln()
      ..writeln('| Date | Entry | Tags |')
      ..writeln('| --- | --- | --- |');
    for (final Map<String, String> row in index.reversed) {
      final String tags = row['tags']!.isEmpty ? '' : '`${row['tags']}`';
      out.writeln(
        '| ${row['date']} | [${_cell(row['title']!)}](${row['path']}) | $tags |',
      );
    }
    out.writeln();
  }

  if (mediaPaths.isNotEmpty) {
    out
      ..writeln('## Assets')
      ..writeln();
    for (final String path in mediaPaths) {
      out.writeln('- `${path}`');
    }
    out.writeln();
  }
  return out.toString();
}

/// Keeps table formatting safe by flattening separators.
String _cell(String value) => value
    .replaceAll('|', r'\|')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();
    try {
      final Object? decoded = jsonDecode(v);
      if (decoded is String) return decoded;
// -------------------------------------------------------------------- import

/// Reads a portable folder back into application data.
///
/// Files it cannot understand are reported in [ImportResult.warnings] rather
/// than failing the whole import, and missing media is kept as a reference so
/// the entry shows a placeholder instead of losing the link.
ImportResult importBundle(
  Bundle bundle, {
  String? fallbackName,
  DateTime? now,
}) {
  final DateTime stamp = now ?? DateTime.now();
  final List<String> warnings = <String>[];
  final Map<String, List<int>> files = _flatten(bundle);

  // Assets first: entries validate their references against this set.
  final Map<String, List<int>> assetFiles = <String, List<int>>{};
  for (final MapEntry<String, List<int>> e in files.entries) {
    if (e.key.startsWith('assets/') && !e.key.endsWith('/')) {
      assetFiles[e.key] = e.value;
    }
  }

  final _Heading heading = _readmeHeading(_readmeSource(files));

  final List<String> entryPaths = <String>[
    for (final String path in files.keys)
      if (_isEntryFile(path)) path,
  ]..sort();
  if (entryPaths.isEmpty) {
    warnings.add(
      'No entries were found. Expected markdown files inside a "journal/" '
      'folder.',
    );
  }

  final String journalId = newId('j');
  final List<Entry> entries = <Entry>[];
  final Set<String> usedIds = <String>{};

  for (final String path in entryPaths) {
    String body = '';
    final Map<String, Object?> meta = parseFrontMatter(
      _decode(files[path]!),
      onBody: (String b) => body = b,
    );
    final Entry? parsed = _entryFrom(
      path: path,
      body: fromPortableBody(body),
      meta: meta,
      journalId: journalId,
      stamp: stamp,
      assetFiles: assetFiles,
      warnings: warnings,
    );
    if (parsed == null) continue;
    entries.add(usedIds.add(parsed.id) ? parsed : _withFreshId(parsed));
  }
  entries.sort((Entry a, Entry b) => a.date.compareTo(b.date));

  // Only carry the assets the imported entries actually point at.
  final Set<String> referenced = <String>{
    for (final Entry e in entries)
      for (final MediaRef m in e.media) m.path,
  };
  final List<MediaRecord> media = <MediaRecord>[];
  for (final String path in referenced) {
    final List<int>? bytes = assetFiles[path];
    if (bytes == null) {
      warnings.add('Missing file "$path" — that entry shows a placeholder.');
      continue;
    }
    media.add(
      MediaRecord(
        MediaRef(
          id: newId('m'),
          kind: _kindFor(path),
          name: path.split('/').last,
          path: path,
          mime: guessMime(path),
          size: bytes.length,
        ),
        Uint8List.fromList(bytes),
      ),
    );
  }

  final DateTime created = entries.isEmpty
      ? stamp
      : entries
            .map((Entry e) => e.createdAt)
            .reduce((DateTime a, DateTime b) => a.isBefore(b) ? a : b);
  final DateTime updated = entries.isEmpty
      ? stamp
      : entries
            .map((Entry e) => e.updatedAt)
            .reduce((DateTime a, DateTime b) => a.isAfter(b) ? a : b);

  final String fallback = (fallbackName ?? '').trim();
  final String name = heading.title.isNotEmpty
      ? heading.title
      : (fallback.isNotEmpty ? fallback : 'Imported journal');

  return ImportResult(
    journal: Journal(
      id: journalId,
      name: name,
      description: heading.description,
      createdAt: created,
      updatedAt: updated,
    ),
    entries: entries,
    media: media,
    warnings: warnings,
  );
}

Entry _withFreshId(Entry e) => Entry(
  id: newId('e'),
  journalId: e.journalId,
  title: e.title,
  content: e.content,
  tags: e.tags,
  media: e.media,
  date: e.date,
  createdAt: e.createdAt,
  updatedAt: e.updatedAt,
/// Builds one entry from a parsed markdown file.
Entry? _entryFrom({
  required String path,
  required String body,
  required Map<String, Object?> meta,
  required String journalId,
  required DateTime stamp,
  required Map<String, List<int>> assetFiles,
  required List<String> warnings,
}) {
  final String fileName = path.split('/').last.replaceAll(
    RegExp(r'\.md$', caseSensitive: false),
    '',
  );
  final DateTime? fromName = _dateFromName(fileName);
  final DateTime? parsedDate = _date(meta['date']);
  final DateTime date = parsedDate ?? fromName ?? stamp;

  final List<String> tags = <String>[];
  for (final String tag in _stringList(meta['tags'])) {
    final String normalised = normalizeTag(tag);
    if (normalised.isNotEmpty && !tags.contains(normalised)) {
      tags.add(normalised);
    }
  }

  final List<MediaRef> media = <MediaRef>[];
  for (final String raw in _stringList(meta['media'])) {
    if (!raw.startsWith('{')) continue;
    final Map<String, String> m = parseFlowMap(raw);
    final String file = (m['file'] ?? '').replaceAll(RegExp(r'^(\.\./)+'), '');
    if (file.isEmpty) continue;
    final MediaKind kind = m['type'] == MediaKind.voice.name
        ? MediaKind.voice
        : _kindFor(file);
    media.add(
      MediaRef(
        id: m['id']?.isNotEmpty ?? false ? m['id']! : newId('m'),
        kind: kind,
        name: m['name']?.isNotEmpty ?? false ? m['name']! : file.split('/').last,
        path: file,
        mime: m['mime']?.isNotEmpty ?? false ? m['mime']! : guessMime(file),
        size: int.tryParse(m['size'] ?? '') ?? 0,
        duration: double.tryParse(m['duration'] ?? '') ?? 0,
      ),
    );
  }

  // Anything the body links to but the front matter forgot still counts.
  for (final String referenced in _referencedAssets(body)) {
    if (media.any((MediaRef m) => m.path == referenced)) continue;
    if (!assetFiles.containsKey(referenced)) continue;
    media.add(
      MediaRef(
        id: newId('m'),
        kind: _kindFor(referenced),
        name: referenced.split('/').last,
        path: referenced,
        mime: guessMime(referenced),
        size: assetFiles[referenced]!.length,
      ),
    );
  }

  String title = (meta['title'] is String ? meta['title']! as String : '').trim();
  if (title.isEmpty) title = _firstHeading(body) ?? _titleFromName(fileName);
  if (title.isEmpty && body.trim().isEmpty && media.isEmpty) {
    warnings.add('Skipped "$path" because it had no content.');
    return null;
  }

  final DateTime created = _date(meta['created']) ?? date;
  final DateTime updated = _date(meta['updated']) ?? created;
  final String? id = meta['id'] is String && (meta['id']! as String).isNotEmpty
      ? meta['id']! as String
      : null;

  return Entry(
    id: id ?? newId('e'),
    journalId: journalId,
    title: title,
    content: body.trimRight(),
    tags: tags,
    media: media,
    date: date,
    createdAt: created,
    updatedAt: updated,
  );
}

List<String> _stringList(Object? value) {
  if (value is List) {
    return <String>[
      for (final Object? item in value)
        if (item is String && item.trim().isNotEmpty) item.trim(),
    ];
  }
  if (value is String && value.trim().isNotEmpty) {
    return <String>[value.trim()];
  }
  return const <String>[];
}

DateTime? _date(Object? value) =>
    value is String ? DateTime.tryParse(value) : null;

/// `2026-09-01-my-title` or `2026-09-01` → a date.
DateTime? _dateFromName(String name) {
  final RegExpMatch? match = RegExp(
    r'(\d{4})-(\d{2})-(\d{2})',
  ).firstMatch(name);
  if (match == null) return null;
  return DateTime.tryParse(match.group(0)!);
}

/// `2026-09-01-my-title` → `my title`.
String _titleFromName(String name) {
  final String withoutDate = name.replaceFirst(
    RegExp(r'^\d{4}-\d{2}-\d{2}[-_]?'),
    '',
  );
  return withoutDate
      .replaceAll(RegExp(r'[-_]+'), ' ')
      .trim()
      .split(' ')
      .where((String w) => w.isNotEmpty)
      .map(
        (String w) => w.length == 1
            ? w.toUpperCase()
            : '${w[0].toUpperCase()}${w.substring(1)}',
      )
      .join(' ');
}

String? _firstHeading(String body) {
  for (final String line in const LineSplitter().convert(body)) {
    final String trimmed = line.trim();
    if (trimmed.startsWith('#')) {
      final String heading = trimmed.replaceFirst(RegExp(r'^#+\s*'), '').trim();
      if (heading.isNotEmpty) return heading;
    }
  }
  return null;
}

/// `assets/img-1.png` paths referenced by the markdown body.
Iterable<String> _referencedAssets(String body) {
  final Set<String> out = <String>{};
  final RegExp image = RegExp(r'!\[[^\]]*\]\(([^)\s]+)');
  for (final RegExpMatch m in image.allMatches(body)) {
    final String raw = m.group(1)!.replaceAll(RegExp(r'^(\.\./)+'), '');
    if (raw.startsWith('assets/')) out.add(raw);
  }
  final RegExp link = RegExp(r'\[[^\]]*\]\((assets/[^)\s]+)');
  for (final RegExpMatch m in link.allMatches(body)) {
    out.add(m.group(1)!.replaceAll(RegExp(r'^(\.\./)+'), ''));
  }
  return out;
}

/// Strips a single shared top level folder, so `my-journal/journal/x.md`
/// behaves the same as `journal/x.md`.
Map<String, List<int>> _flatten(Bundle bundle) {
  final Map<String, List<int>> files = bundle.files;
  if (files.isEmpty) return files;
  final bool nested = files.keys.every(
    (String k) => k.startsWith('${bundle.folder}/'),
  );
  if (!nested) return files;
  return <String, List<int>>{
    for (final MapEntry<String, List<int>> e in files.entries)
      e.key.substring(bundle.folder.length + 1): e.value,
  };
}

bool _isEntryFile(String path) {
  final String lower = path.toLowerCase();
  if (!lower.endsWith('.md')) return false;
  if (lower.endsWith('readme.md')) return false;
  if (lower.startsWith('assets/')) return false;
  return true;
}

String? _readmeSource(Map<String, List<int>> files) {
  for (final MapEntry<String, List<int>> e in files.entries) {
    if (e.key.toLowerCase() == 'readme.md') return _decode(e.value);
  }
  return null;
}

String _decode(List<int> bytes) {
  try {
    return utf8.decode(bytes);
  } catch (_) {
    return utf8.decode(bytes, allowMalformed: true);
  }
}

class _Heading {
  const _Heading(this.title, this.description);

  final String title;
  final String description;
}

/// Pulls the journal name and blurb out of an exported README.
_Heading _readmeHeading(String? source) {
  if (source == null) return const _Heading('', '');
  String title = '';
  final StringBuffer description = StringBuffer();
  bool inTitle = false;
  for (final String line in const LineSplitter().convert(source)) {
    final String trimmed = line.trim();
    if (!inTitle) {
      if (trimmed.startsWith('# ')) {
        title = trimmed.substring(2).trim();
        inTitle = true;
      }
      continue;
    }
    if (trimmed.startsWith('## ') ||
        trimmed.startsWith('- **') ||
        trimmed.startsWith('- *')) {
      break;
    }
    if (trimmed.isEmpty) {
      if (description.isNotEmpty) break;
      continue;
    }
    if (description.isNotEmpty) description.write('\n');
    description.write(trimmed);
  }
  return _Heading(title, description.toString().trim());
}

/// Voice note formats, everything else is treated as an image.
const List<String> _voiceExtensions = <String>[
  '.webm',
  '.ogg',
  '.m4a',
  '.mp3',
  '.wav',
];

MediaKind _kindFor(String path) {
  final String lower = path.toLowerCase();
  for (final String ext in _voiceExtensions) {
    if (lower.endsWith(ext)) return MediaKind.voice;
  }
  return MediaKind.image;
}

/// Mime type from a file extension, used for imported assets.
String guessMime(String path) {
  const Map<String, String> table = <String, String>{
    '.png': 'image/png',
    '.jpg': 'image/jpeg',
    '.jpeg': 'image/jpeg',
    '.gif': 'image/gif',
    '.webp': 'image/webp',
    '.avif': 'image/avif',
    '.bmp': 'image/bmp',
    '.svg': 'image/svg+xml',
    '.webm': 'audio/webm',
    '.ogg': 'audio/ogg',
    '.mp3': 'audio/mpeg',
    '.m4a': 'audio/mp4',
    '.wav': 'audio/wav',
  };
  final String lower = path.toLowerCase();
  for (final MapEntry<String, String> e in table.entries) {
    if (lower.endsWith(e.key)) return e.value;
  }
  return 'application/octet-stream';
}

/// File extension for a mime type, used when naming freshly captured media.
String extensionFor(String mime, {String fallback = '.bin'}) {
  const Map<String, String> table = <String, String>{
    'image/png': '.png',
    'image/jpeg': '.jpg',
    'image/gif': '.gif',
    'image/webp': '.webp',
    'image/avif': '.avif',
    'image/bmp': '.bmp',
    'audio/webm': '.webm',
    'audio/ogg': '.ogg',
    'audio/mpeg': '.mp3',
    'audio/mp4': '.m4a',
    'audio/wav': '.wav',
  };
  return table[mime] ?? fallback;
}

/// `assets/img-1.png` style name that will not clash with existing media.
String mediaPath(MediaKind kind, String mime, Iterable<String> existing) {
  final String base = kind == MediaKind.voice ? 'voice-note' : 'image';
  final String ext = extensionFor(mime, fallback: kind == MediaKind.voice ? '.webm' : '.png');
  final Set<String> taken = existing.toSet();
  int n = 1;
  while (taken.contains('assets/$base-$n$ext')) {
    n++;
  }
  return 'assets/$base-$n$ext';
}

  return v;
}