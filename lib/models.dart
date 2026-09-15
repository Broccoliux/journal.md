import 'dart:math';
import 'dart:typed_data';

/// Data model for journal.md.
///
/// Everything the app persists is one of these three records. They are plain
/// immutable Dart objects with `Map` round-tripping so the same shape can be
/// written to local storage and to portable markdown front matter.
library;

final Random _rng = Random();

/// Short, sortable-ish, collision-safe enough identifier.
String newId(String prefix) {
  final int t = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
  final String r = _rng.nextInt(1 << 32).toRadixString(36).padLeft(7, '0');
  return '${prefix}_$t$r';
}

DateTime? _parseDate(Object? value) {
  if (value is DateTime) return value;
  if (value is String && value.isNotEmpty) return DateTime.tryParse(value);
  return null;
}

String _asString(Object? value, [String fallback = '']) =>
    value is String ? value : (value?.toString() ?? fallback);

/// A journal is a named collection of entries.
class Journal {
  const Journal({
    required this.id,
    required this.name,
    this.description = '',
    this.accent = 0xFF12695F,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final String description;

  /// Accent colour (ARGB) used to give each journal its own identity.
  final int accent;
  final DateTime createdAt;
  final DateTime updatedAt;

  String get slug => slugify(name);

  Journal copyWith({
    String? name,
    String? description,
    int? accent,
    DateTime? updatedAt,
  }) => Journal(
    id: id,
    name: name ?? this.name,
    description: description ?? this.description,
    accent: accent ?? this.accent,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'accent': accent,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  static Journal? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final DateTime? created = _parseDate(raw['createdAt']);
    final DateTime? updated = _parseDate(raw['updatedAt']);
    final String name = _asString(raw['name']).trim();
    if (name.isEmpty || created == null) return null;
    return Journal(
      id: _asString(raw['id'], newId('j')),
      name: name,
      description: _asString(raw['description']),
      accent: raw['accent'] is int ? raw['accent'] as int : 0xFF12695F,
      createdAt: created,
      updatedAt: updated ?? created,
    );
  }
}

/// One of the two kinds of media an entry can hold.
enum MediaKind { image, voice }

/// Metadata for a media file. The bytes live separately (see `JournalStore`)
/// so entry records stay small and lists stay fast.
class MediaRef {
  const MediaRef({
    required this.id,
    required this.kind,
    required this.name,
    required this.path,
    required this.mime,
    this.size = 0,
    this.duration = 0,
  });

  final String id;
  final MediaKind kind;
  final String name;

  /// Repo-relative path used inside markdown, e.g. `assets/img-1.png`.
  final String path;
  final String mime;
  final int size;

  /// Seconds. Only meaningful for voice notes.
  final double duration;

  String get kindLabel => kind == MediaKind.image ? 'Image' : 'Voice note';

  bool get isImage => kind == MediaKind.image;

  MediaRef copyWith({String? name, String? path, double? duration}) => MediaRef(
    id: id,
    kind: kind,
    name: name ?? this.name,
    path: path ?? this.path,
    mime: mime,
    size: size,
    duration: duration ?? this.duration,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'kind': kind.name,
    'name': name,
    'path': path,
    'mime': mime,
    'size': size,
    'duration': duration,
  };

  static MediaRef? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final String path = _asString(raw['path']).trim();
    if (path.isEmpty) return null;
    final String? kindName = raw['kind'] is String
        ? raw['kind'] as String
        : null;
    return MediaRef(
      id: _asString(raw['id'], newId('m')),
      kind: kindName == MediaKind.voice.name ? MediaKind.voice : MediaKind.image,
      name: _asString(raw['name'], path.split('/').last),
      path: path,
      mime: _asString(raw['mime'], 'application/octet-stream'),
      size: raw['size'] is int ? raw['size'] as int : 0,
      duration: raw['duration'] is num
          ? (raw['duration'] as num).toDouble()
          : 0,
    );
  }
}

/// A single dated journal entry.
class Entry {
  const Entry({
    required this.id,
    required this.journalId,
    required this.title,
    this.content = '',
    this.tags = const <String>[],
    this.media = const <MediaRef>[],
    required this.date,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String journalId;
  final String title;

  /// Markdown body. Media is referenced with repo-relative paths
  /// (e.g. `![](assets/img-1.png)`) so exported markdown stays readable.
  final String content;
  final List<String> tags;
  final List<MediaRef> media;

  /// Date the entry is *about* (user editable).
  final DateTime date;
  final DateTime createdAt;
  final DateTime updatedAt;

  String get displayTitle => title.trim().isEmpty ? 'Untitled entry' : title;

  /// First meaningful line of the body, used for previews.
  String preview({int max = 180}) {
    final String flat = content
        .replaceAll(RegExp(r'```[\s\S]*?```'), ' ')
        .replaceAll(RegExp(r'!\[[^\]]*\]\([^)]*\)'), ' ')
        .replaceAll(RegExp(r'\[([^\]]*)\]\([^)]*\)'), r'$1')
        .replaceAll(RegExp(r'[#>*`_~\-]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (flat.length <= max) return flat;
    return '${flat.substring(0, max).trimRight()}…';
  }

  /// Preview ignoring inline media, which is already shown as a thumbnail.
  String previewWithoutMedia({int max = 200}) => content
      .replaceAll(RegExp(r'!\[[^\]]*\]\(assets/[^)]*\)'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  Entry copyWith({
    String? title,
    String? content,
    List<String>? tags,
    List<MediaRef>? media,
    DateTime? date,
    DateTime? updatedAt,
  }) => Entry(
    id: id,
    journalId: journalId,
    title: title ?? this.title,
    content: content ?? this.content,
    tags: tags ?? this.tags,
    media: media ?? this.media,
    date: date ?? this.date,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'journalId': journalId,
    'title': title,
    'content': content,
    'tags': tags,
    'media': media.map((MediaRef m) => m.toJson()).toList(),
    'date': date.toIso8601String(),
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  static Entry? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final DateTime? date = _parseDate(raw['date']);
    final String? journalId = raw['journalId'] is String
        ? raw['journalId'] as String
        : null;
    if (date == null || journalId == null || journalId.isEmpty) return null;

    final List<String> tags = <String>[];
    if (raw['tags'] is List) {
      for (final Object? t in raw['tags'] as List<Object?>) {
        final String tag = normalizeTag(_asString(t));
        if (tag.isNotEmpty && !tags.contains(tag)) tags.add(tag);
      }
    }
    final List<MediaRef> media = <MediaRef>[];
    if (raw['media'] is List) {
      for (final Object? m in raw['media'] as List<Object?>) {
        final MediaRef? ref = MediaRef.fromJson(m);
        if (ref != null) media.add(ref);
      }
    }
    final DateTime? created = _parseDate(raw['createdAt']) ?? date;
    return Entry(
      id: _asString(raw['id'], newId('e')),
      journalId: journalId,
      title: _asString(raw['title']),
      content: _asString(raw['content']),
      tags: tags,
      media: media,
      date: date,
      createdAt: created,
      updatedAt: _parseDate(raw['updatedAt']) ?? created,
    );
  }
}

/// Accents used to give each journal its own colour identity. Chosen to sit
/// calmly next to the paper and midnight palettes.
const List<int> journalAccents = <int>[
  0xFF0E6A5F, // viridian
  0xFF9C7538, // brass
  0xFF35506B, // slate blue
  0xFF7A3E52, // plum
  0xFF4A5A2B, // olive
  0xFF8A4B22, // rust
];

int accentFor(int index) => journalAccents[index % journalAccents.length];

/// A media reference together with the bytes it points at.
class MediaRecord {
  const MediaRecord(this.ref, this.bytes);

  final MediaRef ref;
  final Uint8List bytes;
}

/// Turns `  #Ai  ` into `ai`. Tags are matched case-insensitively.
String normalizeTag(String raw) {
  return raw
      .trim()
      .replaceAll(RegExp(r'^#+'), '')
      .replaceAll(RegExp(r'\s+'), '-')
      .toLowerCase();
}

/// Lower-case, dash separated, filesystem friendly.
String slugify(String raw) {
  final String slug = raw
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  return slug.isEmpty ? 'journal' : slug;
}

const List<String> _months = <String>[
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// Human friendly short date, e.g. `1 Sep 2026`.
String shortDate(DateTime d) => '${d.day} ${_months[d.month - 1]} ${d.year}';

/// `2026-09-01` — the filename form used by exported entries.
String isoDay(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// `1 Sep 2026 · 14:05`.
String dateTimeLabel(DateTime d) =>
    '${shortDate(d)} · ${d.hour.toString().padLeft(2, '0')}:'
    '${d.minute.toString().padLeft(2, '0')}';

/// `just now`, `4 min ago`, `3 Sep 2026`.
String relativeTime(DateTime d, [DateTime? now]) {
  final DateTime ref = now ?? DateTime.now();
  final Duration diff = ref.difference(d);
  if (diff.isNegative) return shortDate(d);
  if (diff.inSeconds < 45) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
  if (diff.inHours < 24 && d.day == ref.day) return '${diff.inHours} h ago';
  if (diff.inDays < 7) return '${diff.inDays} d ago';
  return shortDate(d);
}

/// `12:04` style duration for voice notes.
String durationLabel(double seconds) {
  final int total = seconds.isFinite && seconds > 0 ? seconds.round() : 0;
  final int m = total ~/ 60;
  final int s = total % 60;
  return '$m:${s.toString().padLeft(2, '0')}';
}

/// `1.2 MB`, `840 KB`.
String sizeLabel(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).round()} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

/// `September 2026` — timeline section headers.
String monthLabel(DateTime d) => const <String>[
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
][d.month - 1];
