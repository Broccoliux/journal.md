/// Local-first persistence for journal.md.
///
/// Everything lives in one Hive box backed by the browser's IndexedDB:
///  * `data`          → JSON of all journals + entries
///  * `ui`            → theme mode + last location
///  * `asset:<id>`    → raw bytes of images / voice notes
///
/// Mutations update in-memory state immediately (so the UI is instant) and
/// persist with a short debounce. [flush] is called when the tab is hidden.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:hive_ce_flutter/hive_flutter.dart';

import 'models.dart';

enum SaveState { clean, pending, saving, error }

class Store extends ChangeNotifier {
  static const _boxName = 'journalmd';
  static const _dataKey = 'data';
  static const _uiKey = 'ui';
  static const _assetPrefix = 'asset:';

  Box? _box;

  final List<Journal> journals = [];
  final Map<String, Entry> entries = {};

  bool ready = false;
  String? loadError;

  ThemeMode themeMode = ThemeMode.system;

  SaveState saveState = SaveState.clean;
  DateTime? lastSavedAt;

  Timer? _saveTimer;

  // ---------------------------------------------------------------- open

  Future<void> open() async {
    assert(_box == null, 'Store.open() called twice');
    try {
      await Hive.initFlutter();
      _box = await Hive.openBox(_boxName);
      _readAll();
      ready = true;
    } catch (e) {
      loadError = 'Could not open local storage: $e';
      debugPrint('journal.md store open failed: $e');
    }
    notifyListeners();
  }

  void _readAll() {
    final box = _box!;
    final raw = box.get(_dataKey);
    if (raw is String && raw.isNotEmpty) {
      try {
        final db = decodeDb(raw);
        journals
          ..clear()
          ..addAll(db.journals);
        entries
          ..clear()
          ..addEntries([for (final e in db.entries) MapEntry(e.id, e)]);
      } catch (e) {
        loadError = 'Saved data could not be read: $e';
        debugPrint('journal.md decode failed: $e');
      }
    }
    final ui = box.get(_uiKey);
    if (ui is String && ui.isNotEmpty) {
      try {
        final map = jsonDecode(ui) as Map<String, dynamic>;
        final mode = map['themeMode'];
        if (mode == 'light') themeMode = ThemeMode.light;
        if (mode == 'dark') themeMode = ThemeMode.dark;
      } catch (_) {}
    }
    _deleteUnreferencedAssets();
  }

  // ------------------------------------------------------------- journals

  Journal createJournal(String name, [String description = '']) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final journal = Journal(
      id: newId(),
      name: name.trim().isEmpty ? 'Untitled' : name.trim(),
      description: description.trim(),
      createdAt: now,
      updatedAt: now,
    );
    journals.add(journal);
    _changed();
    return journal;
  }

  Journal? journal(String id) {
    for (final j in journals) {
      if (j.id == id) return j;
    }
    return null;
  }

  void updateJournal(String id, {String? name, String? description}) {
    final j = journal(id);
    if (j == null) return;
    if (name != null && name.trim().isNotEmpty) j.name = name.trim();
    if (description != null) j.description = description.trim();
    j.updatedAt = DateTime.now().millisecondsSinceEpoch;
    _changed();
  }

  Future<void> deleteJournal(String id) async {
    entries.removeWhere((_, e) => e.journalId == id);
    journals.removeWhere((j) => j.id == id);
    await _deleteUnreferencedAssets();
    _changed();
  }

  int entryCount(String journalId) =>
      entries.values.where((e) => e.journalId == journalId).length;

  int lastActivity(String journalId) {
    var latest = journal(journalId)?.updatedAt ?? 0;
    for (final e in entries.values) {
      if (e.journalId == journalId && e.updatedAt > latest) {
        latest = e.updatedAt;
      }
    }
    return latest;
  }

  // -------------------------------------------------------------- entries

  Entry createEntry(String journalId) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final entry = Entry(
      id: newId(),
      journalId: journalId,
      date: now,
      createdAt: now,
      updatedAt: now,
    );
    entries[entry.id] = entry;
    _touchJournal(journalId);
    _changed();
    return entry;
  }

  Entry? entry(String id) => entries[id];

  /// Mark an entry as edited — called on every editor change (autosave).
  void touchEntry(Entry e) {
    e.updatedAt = DateTime.now().millisecondsSinceEpoch;
    _touchJournal(e.journalId);
    _changed();
  }

  Entry? duplicateEntry(String id) {
    final source = entries[id];
    if (source == null) return null;
    final copy = source.duplicate();
    entries[copy.id] = copy;
    _touchJournal(copy.journalId);
    _changed();
    return copy;
  }

  Future<void> deleteEntry(String id) async {
    entries.remove(id);
    await _deleteUnreferencedAssets();
    _changed();
  }

  /// Entries of one journal, newest first.
  List<Entry> entriesOf(String journalId) {
    final list = [
      for (final e in entries.values)
        if (e.journalId == journalId) e
    ]..sort((a, b) => b.date.compareTo(a.date));
    return list;
  }

  /// All entries, newest first.
  List<Entry> allEntries() {
    final list = List<Entry>.of(entries.values)
      ..sort((a, b) => b.date.compareTo(a.date));
    return list;
  }

  // ----------------------------------------------------------------- tags

  Map<String, int> tagCounts() {
    final counts = <String, int>{};
    for (final e in entries.values) {
      for (final t in e.tags) {
        counts[t] = (counts[t] ?? 0) + 1;
      }
    }
    return counts;
  }

  List<Entry> entriesWithTag(String tag) {
    final list = [
      for (final e in entries.values)
        if (e.tags.contains(tag)) e
    ]..sort((a, b) => b.date.compareTo(a.date));
    return list;
  }

  // --------------------------------------------------------------- assets

  Future<void> putAsset(String id, Uint8List bytes) async {
    await _box?.put('$_assetPrefix$id', bytes);
  }

  Uint8List? asset(String id) {
    final bytes = _box?.get('$_assetPrefix$id');
    return bytes is Uint8List ? bytes : null;
  }

  bool hasAsset(String id) => asset(id) != null;

  /// Looks up an attachment metadata record by its id (for the renderer).
  Attachment? attachmentById(String id) {
    for (final e in entries.values) {
      for (final a in e.attachments) {
        if (a.id == id) return a;
      }
    }
    return null;
  }

  Future<void> deleteAsset(String id) async {
    await _box?.delete('$_assetPrefix$id');
  }

  /// Remove asset blobs that are no longer referenced by any entry.
  Future<void> _deleteUnreferencedAssets() async {
    final box = _box;
    if (box == null) return;
    final referenced = <String>{
      for (final e in entries.values)
        for (final a in e.attachments) a.id
    };
    final keys = List.of(box.keys);
    for (final key in keys) {
      if (key is String && key.startsWith(_assetPrefix)) {
        final id = key.substring(_assetPrefix.length);
        if (!referenced.contains(id)) {
          await box.delete(key);
        }
      }
    }
  }

  /// Approximate size of all stored media.
  int approxAssetBytes() {
    var total = 0;
    final seen = <String>{};
    for (final e in entries.values) {
      for (final a in e.attachments) {
        if (seen.add(a.id)) total += a.size;
      }
    }
    return total;
  }

  // ----------------------------------------------------------- persistence

  void _touchJournal(String journalId) {
    final j = journal(journalId);
    if (j != null) j.updatedAt = DateTime.now().millisecondsSinceEpoch;
  }

  void _changed() {
    saveState = SaveState.pending;
    notifyListeners();
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 600), _persist);
  }

  Future<void> _persist() async {
    final box = _box;
    if (box == null || saveState != SaveState.pending) return;
    saveState = SaveState.saving;
    notifyListeners();
    try {
      await box.put(_dataKey, encodeDb(journals, entries.values));
      saveState = SaveState.clean;
      lastSavedAt = DateTime.now();
    } catch (e) {
      debugPrint('journal.md persist failed: $e');
      saveState = SaveState.error;
    }
    notifyListeners();
  }

  /// Force a write now (called when the tab becomes hidden).
  Future<void> flush() async {
    if (saveState == SaveState.pending) {
      _saveTimer?.cancel();
      await _persist();
    }
  }

  /// Persist small UI state (theme + last location) immediately.
  Future<void> saveUi({
    String section = 'journals',
    String? journalId,
    String? entryId,
  }) async {
    await _writeUi({
      'section': section,
      'journalId': journalId,
      'entryId': entryId,
    });
  }

  Map<String, dynamic> _readUiMap() {
    final ui = _box?.get(_uiKey);
    if (ui is String && ui.isNotEmpty) {
      try {
        return jsonDecode(ui) as Map<String, dynamic>;
      } catch (_) {}
    }
    return {};
  }

  Future<void> _writeUi(Map<String, dynamic> updates) async {
    final map = _readUiMap()..addAll(updates);
    try {
      await _box?.put(_uiKey, jsonEncode(map));
    } catch (_) {}
  }

  ({String section, String? journalId, String? entryId})? readUi() {
    final map = _readUiMap();
    final section = map['section'] as String?;
    if (section == null) return null;
    return (
      section: section,
      journalId: map['journalId'] as String?,
      entryId: map['entryId'] as String?,
    );
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    themeMode = mode;
    notifyListeners();
    await _writeUi({'themeMode': mode.name});
  }

  /// Erase everything (after a double confirmation in the UI).
  Future<void> eraseAll() async {
    journals.clear();
    entries.clear();
    await _box?.clear();
    saveState = SaveState.clean;
    lastSavedAt = DateTime.now();
    notifyListeners();
  }

  // ------------------------------------------------- import / export glue

  /// Merge an imported bundle into the store. Existing ids are skipped so
  /// importing the same backup twice is idempotent.
  Future<({int journals, int entries, int assets, int skipped})> mergeImport({
    required List<Journal> newJournals,
    required List<Entry> newEntries,
    required Map<String, Uint8List> newAssets,
    required String Function(String name) dedupeJournalName,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    var addedJournals = 0;
    var addedEntries = 0;
    var addedAssets = 0;
    var skipped = 0;

    for (final j in newJournals) {
      if (journal(j.id) != null) {
        skipped++;
        continue;
      }
      // Avoid duplicate journal names so exports stay unambiguous.
      j.name = dedupeJournalName(j.name);
      journals.add(j);
      addedJournals++;
    }

    for (final e in newEntries) {
      if (entries.containsKey(e.id)) {
        skipped++;
        continue;
      }
      // Guard against entries pointing at journals that were skipped or
      // otherwise missing: keep the entry, attach to an "Imported" journal.
      if (journal(e.journalId) == null) {
        Journal? imported;
        for (final j in journals) {
          if (j.name == 'Imported') {
            imported = j;
            break;
          }
        }
        imported ??= Journal(
          id: newId(),
          name: 'Imported',
          createdAt: now,
          updatedAt: now,
        );
        if (!journals.contains(imported)) {
          journals.add(imported);
          addedJournals++;
        }
        e.journalId = imported.id;
      }
      entries[e.id] = e;
      addedEntries++;
    }

    for (final id in newAssets.keys) {
      if (!hasAsset(id)) {
        await putAsset(id, newAssets[id]!);
        addedAssets++;
      } else {
        skipped++;
      }
    }

    _changed();
    return (
      journals: addedJournals,
      entries: addedEntries,
      assets: addedAssets,
      skipped: skipped
    );
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    super.dispose();
  }
}
