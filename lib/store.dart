import 'dart:convert';
import 'dart:typed_data';

import 'package:sembast/sembast.dart';

import 'db_factory.dart';
import 'models.dart';

/// A storage level problem worth telling the user about.
class StoreFailure implements Exception {
  StoreFailure(this.message, [this.detail]);

  final String message;
  final String? detail;

  @override
  String toString() => detail == null ? message : '$message ($detail)';
}

/// Metadata plus bytes for one stored media file.
// NOTE: defined in models.dart so both storage and the portable format can use
// it without depending on each other.
typedef StoredMedia = MediaRecord;

/// Everything read at startup, plus anything that had to be skipped.
class LoadResult {
  const LoadResult({
    required this.journals,
    required this.entries,
    required this.issues,
  });

  final List<Journal> journals;
  final List<Entry> entries;
  final List<String> issues;
}

typedef _Row = RecordSnapshot<String, Map<String, Object?>>;

/// Local-first persistence for journals, entries and media.
///
/// Deliberately the only thing in the app that knows how data is stored. It
/// uses a document store: `Map` records in three collections, with media bytes
/// kept out of the entry records so lists stay cheap. On the web the backing
/// store is IndexedDB; in tests it is memory.
class JournalStore {
  JournalStore._(this._db, {required this.persistent, required this.warning});

  final Database _db;

  /// False when the browser refused real storage and we fell back to memory.
  final bool persistent;

  /// Non-null when the user must be warned that nothing will be saved.
  final String? warning;

  static const String _journals = 'journals';
  static const String _entries = 'entries';
  static const String _media = 'media';

  /// Anything unreadable is moved here instead of being thrown away.
  static const String _quarantine = 'quarantine';

  /// Preferences live apart from user content so they are easy to ignore.
  static const String _settings = 'settings';

  static final StoreRef<String, Map<String, Object?>> _journalStore =
      StoreRef<String, Map<String, Object?>>(_journals);
  static final StoreRef<String, Map<String, Object?>> _entryStore =
      StoreRef<String, Map<String, Object?>>(_entries);
  static final StoreRef<String, Map<String, Object?>> _mediaStore =
      StoreRef<String, Map<String, Object?>>(_media);
  static final StoreRef<String, Map<String, Object?>> _quarantineStore =
      StoreRef<String, Map<String, Object?>>(_quarantine);
  static final StoreRef<String, Map<String, Object?>> _settingsStore =
      StoreRef<String, Map<String, Object?>>(_settings);

  /// Opens the store, degrading to memory rather than failing to start.
  static Future<JournalStore> open({String name = 'journal_md'}) async {
    try {
      return JournalStore._(
        await openJournalDatabase(name),
        persistent: true,
        warning: null,
      );
    } catch (error) {
      return JournalStore._(
        await databaseFactoryMemory.openDatabase(name),
        persistent: false,
        warning:
            'Local browser storage is unavailable, so this session is '
            'temporary. Export your journal to keep this work. ($error)',
      );
    }
  }

  Future<void> close() => _db.close();

  /// How many records had to be quarantined after being unreadable.
  Future<int> quarantineCount() async {
    try {
      return (await _quarantineStore.find(_db)).length;
    } catch (_) {
      return 0;
    }
  }

  /// Erases every record. Callers must confirm with the user first.
  Future<void> wipe() async {
    try {
      await _db.transaction((Transaction txn) async {
        await _journalStore.delete(txn);
        await _entryStore.delete(txn);
        await _mediaStore.delete(txn);
      });
    } catch (error) {
      throw StoreFailure('Could not clear local storage.', '$error');
    }
  }

  // ---------------------------------------------------------------- journals

  Future<List<Journal>> loadJournals() async {
    final List<Journal> out = <Journal>[];
    final List<_Row> rows = await _guard(
      () => _journalStore.find(_db),
      'Could not read your journals. Reload the page and try again.',
    );
    for (final _Row row in rows) {
      final Journal? journal = Journal.fromJson(row.value);
      if (journal == null) {
        await _quarantineRow(_journalStore, row.key, row.value);
      } else {
        out.add(journal);
      }
    }
    return out;
  }

  Future<void> saveJournal(Journal journal) => _guard(
    () => _journalStore.record(journal.id).put(_db, journal.toJson()),
    'Could not save the journal "${journal.name}".',
  );

  /// Removes a journal with all of its entries and media. Nothing is implicit:
  /// callers must confirm with the user first.
  Future<void> deleteJournal(String journalId) => _guard(() async {
    final List<_Row> entries = await _entryStore.find(_db);
    for (final _Row row in entries) {
      if (row.value['journalId'] != journalId) continue;
      for (final MediaRef ref in _mediaOf(row.value)) {
        await _mediaStore.record(ref.path).delete(_db);
      }
      await _entryStore.record(row.key).delete(_db);
    }
    await _journalStore.record(journalId).delete(_db);
  }, 'Could not delete the journal.');

  // ----------------------------------------------------------------- entries

  Future<List<Entry>> loadEntries() async {
    final List<Entry> out = <Entry>[];
    final List<_Row> rows = await _guard(
      () => _entryStore.find(_db),
      'Could not read your entries. Reload the page and try again.',
    );
    for (final _Row row in rows) {
      final Entry? entry = Entry.fromJson(row.value);
      if (entry == null) {
        await _quarantineRow(_entryStore, row.key, row.value);
      } else {
        out.add(entry);
      }
    }
    return out;
  }

  Future<void> saveEntry(Entry entry) => _guard(
    () => _entryStore.record(entry.id).put(_db, entry.toJson()),
    'Could not save this entry.',
  );

  Future<void> deleteEntry(String entryId) => _guard(
    () => _entryStore.record(entryId).delete(_db),
    'Could not delete this entry.',
  );

  // ------------------------------------------------------------------- media

  /// Stores media bytes under its [MediaRef.path] so markdown references and
  /// stored bytes always agree.
  Future<void> saveMedia(MediaRef ref, Uint8List bytes) =>
      _guard(() => _putMedia(_db, ref, bytes), 'Could not save "${ref.name}".');

  /// Bytes for a markdown reference such as `assets/img-1.png`. Returns null
  /// when the file is missing, which callers render as a missing-file note.
  Future<Uint8List?> loadMediaBytes(String path) async {
    final Map<String, Object?>? row = await _guard(
      () => _mediaStore.record(path).get(_db),
      'Could not read the file "$path".',
    );
    final String? data = row?['data'] as String?;
    if (data == null) return null;
    try {
      return base64Decode(data);
    } catch (_) {
      return null;
    }
  }

  Future<void> deleteMedia(String path) => _guard(
    () => _mediaStore.record(path).delete(_db),
    'Could not delete the file "$path".',
  );

  /// Every stored file. Only export needs the whole set at once.
  Future<List<MediaRecord>> loadAllMedia() async {
    final List<_Row> rows = await _guard(
      () => _mediaStore.find(_db),
      'Could not read stored files.',
    );
    final List<MediaRecord> out = <MediaRecord>[];
    for (final _Row row in rows) {
      final String? data = row.value['data'] as String?;
      if (data == null) continue;
      try {
        out.add(
          MediaRecord(
            MediaRef(
              id: row.key,
              kind: MediaKind.image,
              name: row.key.split('/').last,
              path: row.key,
              mime:
                  (row.value['mime'] as String?) ?? 'application/octet-stream',
              size: (row.value['size'] as int?) ?? 0,
            ),
            base64Decode(data),
          ),
        );
      } catch (_) {
        // Unreadable blob: skip it, export keeps going.
      }
    }
    return out;
  }

  // ---------------------------------------------------------------- upkeep

  /// Removes every stored file that no entry references any more.
  Future<int> pruneMedia(List<Entry> entries) async {
    final Set<String> live = <String>{
      for (final Entry e in entries)
        for (final MediaRef m in e.media) m.path,
    };
    final List<_Row> rows = await _guard(
      () => _mediaStore.find(_db),
      'Could not tidy stored files.',
    );
    int removed = 0;
    for (final _Row row in rows) {
      if (!live.contains(row.key)) {
        await _mediaStore.record(row.key).delete(_db);
        removed++;
      }
    }
    return removed;
  }

  /// Writes a whole imported journal in one transaction, so a failed import
  /// cannot leave half a journal behind.
  Future<void> importAll({
    required List<Journal> journals,
    required List<Entry> entries,
    required List<MediaRecord> media,
  }) async {
    try {
      await _db.transaction((Transaction txn) async {
        for (final Journal j in journals) {
          await _journalStore.record(j.id).put(txn, j.toJson());
        }
        for (final Entry e in entries) {
          await _entryStore.record(e.id).put(txn, e.toJson());
        }
        for (final MediaRecord m in media) {
          await _putMedia(txn, m.ref, m.bytes);
        }
      });
    } catch (error) {
      throw StoreFailure(
        'Import failed while writing to local storage. Nothing was changed.',
        '$error',
      );
    }
  }

  // ------------------------------------------------------------- internals

  Future<void> _putMedia(
    DatabaseClient client,
    MediaRef ref,
    Uint8List bytes,
  ) => _mediaStore.record(ref.path).put(client, <String, Object?>{
    'path': ref.path,
    'mime': ref.mime,
    'size': bytes.length,
    'data': base64Encode(bytes),
  });

  static List<MediaRef> _mediaOf(Map<String, Object?> row) {
    final Object? media = row['media'];
    if (media is! List) return const <MediaRef>[];
    final List<MediaRef> out = <MediaRef>[];
    for (final Object? item in media) {
      final MediaRef? ref = MediaRef.fromJson(item);
      if (ref != null) out.add(ref);
    }
    return out;
  }

  /// Moves an unreadable record aside instead of deleting it.
  Future<void> _quarantineRow(
    StoreRef<String, Map<String, Object?>> source,
    String key,
    Map<String, Object?> value,
  ) async {
    try {
      await _quarantineStore
          .record('${source.name}:$key')
          .put(_db, <String, Object?>{
            'source': source.name,
            'key': key,
            'at': DateTime.now().toIso8601String(),
            'raw': value.map(
              (String k, Object? v) => MapEntry<String, String>(k, '$v'),
            ),
          });
      await source.record(key).delete(_db);
    } catch (_) {
      // Quarantine is best effort; never block startup for it.
    }
  }

  /// Runs a storage operation, translating failures into a friendly error.
  Future<T> _guard<T>(Future<T> Function() action, String message) async {
    try {
      return await action();
    } on StoreFailure {
      rethrow;
    } catch (error) {
      throw StoreFailure(message, '$error');
    }
  }
}
}