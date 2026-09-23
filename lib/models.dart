/// Data model for journal.md — journals, entries and attachments.
///
/// Pure Dart (no Flutter imports) so it can be unit-tested directly.
library;

import 'dart:convert';
import 'dart:math';

String newId() {
  final r = Random();
  final t = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
  final suffix =
      List.generate(4, (_) => r.nextInt(36).toRadixString(36)).join();
  return '$t$suffix';
}

class Journal {
  Journal({
    required this.id,
    required this.name,
    this.description = '',
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  String name;
  String description;
  int createdAt; // epoch ms
  int updatedAt; // epoch ms

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'createdAt': createdAt,
        'updatedAt': updatedAt,
      };

  factory Journal.fromJson(Map<String, dynamic> json) => Journal(
        id: json['id'] as String,
        name: (json['name'] as String?) ?? 'Untitled',
        description: (json['description'] as String?) ?? '',
        createdAt: (json['createdAt'] as num?)?.toInt() ?? 0,
        updatedAt: (json['updatedAt'] as num?)?.toInt() ?? 0,
      );
}

class Attachment {
  Attachment({
    required this.id,
    required this.kind, // 'image' | 'audio'
    required this.name,
    this.mime,
    required this.size,
    required this.createdAt,
  });

  final String id;
  final String kind;
  String name;
  String? mime;
  int size;
  int createdAt;

  bool get isImage => kind == 'image';
  bool get isAudio => kind == 'audio';

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind,
        'name': name,
        'mime': mime,
        'size': size,
        'createdAt': createdAt,
      };

  factory Attachment.fromJson(Map<String, dynamic> json) => Attachment(
        id: json['id'] as String,
        kind: (json['kind'] as String?) ?? 'image',
        name: (json['name'] as String?) ?? 'file',
        mime: json['mime'] as String?,
        size: (json['size'] as num?)?.toInt() ?? 0,
        createdAt: (json['createdAt'] as num?)?.toInt() ?? 0,
      );
}

class Entry {
  Entry({
    required this.id,
    required this.journalId,
    this.title = '',
    required this.date, // the entry's user-facing date/time, epoch ms
    required this.createdAt,
    required this.updatedAt,
    List<String>? tags,
    this.content = '',
    List<Attachment>? attachments,
  })  : tags = tags ?? [],
        attachments = attachments ?? [];

  final String id;
  String journalId;
  String title;
  int date;
  int createdAt;
  int updatedAt;
  List<String> tags; // lowercase, no '#'
  String content; // markdown
  List<Attachment> attachments;

  Iterable<Attachment> get images => attachments.where((a) => a.isImage);
  Iterable<Attachment> get audioNotes => attachments.where((a) => a.isAudio);

  Map<String, dynamic> toJson() => {
        'id': id,
        'journalId': journalId,
        'title': title,
        'date': date,
        'createdAt': createdAt,
        'updatedAt': updatedAt,
        'tags': tags,
        'content': content,
        'attachments': [for (final a in attachments) a.toJson()],
      };

  factory Entry.fromJson(Map<String, dynamic> json) => Entry(
        id: json['id'] as String,
        journalId: (json['journalId'] as String?) ?? '',
        title: (json['title'] as String?) ?? '',
        date: (json['date'] as num?)?.toInt() ??
            (json['createdAt'] as num?)?.toInt() ??
            0,
        createdAt: (json['createdAt'] as num?)?.toInt() ?? 0,
        updatedAt: (json['updatedAt'] as num?)?.toInt() ?? 0,
        tags: [
          for (final t in (json['tags'] as List? ?? []))
            t.toString().toLowerCase()
        ],
        content: (json['content'] as String?) ?? '',
        attachments: [
          for (final a in (json['attachments'] as List? ?? []))
            if (a is Map<String, dynamic>) Attachment.fromJson(a)
        ],
      );

  /// A shallow copy with a new id — used by "duplicate".
  Entry duplicate() {
    final now = DateTime.now().millisecondsSinceEpoch;
    return Entry(
      id: newId(),
      journalId: journalId,
      title: title.isEmpty ? 'Copy' : '$title (copy)',
      date: date,
      createdAt: now,
      updatedAt: now,
      tags: List.of(tags),
      content: content,
      attachments: [for (final a in attachments) a],
    );
  }
}

/// Whole-database JSON codec. `version` allows future migrations.
String encodeDb(Iterable<Journal> journals, Iterable<Entry> entries) =>
    jsonEncode({
      'version': 1,
      'journals': [for (final j in journals) j.toJson()],
      'entries': [for (final e in entries) e.toJson()],
    });

({List<Journal> journals, List<Entry> entries}) decodeDb(String raw) {
  final data = jsonDecode(raw) as Map<String, dynamic>;
  final journals = [
    for (final j in (data['journals'] as List? ?? []))
      if (j is Map<String, dynamic>) Journal.fromJson(j)
  ];
  final entries = [
    for (final e in (data['entries'] as List? ?? []))
      if (e is Map<String, dynamic>) Entry.fromJson(e)
  ];
  return (journals: journals, entries: entries);
}
