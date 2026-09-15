import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'models.dart';
import 'portable.dart';
import 'store.dart';

/// Top level areas of the app, used by the rail and the mobile tab bar.
enum Section {
  journals('Journals'),
  timeline('Timeline'),
  search('Search'),
  data('Library');

  const Section(this.label);

  final String label;
}

/// One search result, ranked and ready to display.
class SearchHit {
  const SearchHit({
    required this.entry,
    required this.journal,
    required this.score,
    required this.snippet,
    required this.where,
  });

  final Entry entry;
  final Journal? journal;
  final int score;
  final String snippet;

  /// Which fields matched: `title`, `content`, `tags`, `journal`.
  final Set<String> where;

  bool get matchedTitle => where.contains('title');
}

/// One media reference that exists only in a markdown body, not in front
/// matter — normally because the file was lost. Surfaced so nothing is silent.
class MissingMedia {
  const MissingMedia(this.path, this.entry);

  final String path;
  final Entry entry;
}

/// Makes [AppState] available to the whole tree without pulling in a
/// dependency injection package.
class AppScope extends InheritedNotifier<AppState> {
  const AppScope({required AppState state, required super.child, super.key})
    : super(notifier: state);

  /// Reads the state and rebuilds the caller when it changes.
  static AppState of(BuildContext context) {
    final AppScope? scope = context
        .dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope?.notifier != null, 'AppScope is missing above this widget.');
    return scope!.notifier!;
  }

  /// Reads the state without subscribing to changes. For callbacks.
  static AppState read(BuildContext context) {
    final AppScope? scope = context
        .getInheritedWidgetOfExactType<AppScope>();
    assert(scope?.notifier != null, 'AppScope is missing above this widget.');
    return scope!.notifier!;
  }
}

/// Everything the UI needs to know, in one place.
///
/// Small on purpose: a list of journals, a map of entries, and the current
/// selection. Writes go straight through to [JournalStore] so what is on
/// screen is what is saved.
class AppState extends ChangeNotifier {
  AppState(this._store);

  final JournalStore _store;

  final StreamController<String> _messages =
      StreamController<String>.broadcast();

  /// User-facing notices (saved, imported, failed…). The shell listens.
  Stream<String> get messages => _messages.stream;

  void say(String text) => _messages.add(text);

  final List<Journal> _journals = <Journal>[];
  final Map<String, Entry> _entries = <String, Entry>{};

  /// Recently used media bytes, so scrolling a list does not re-decode files.
  final Map<String, Uint8List> _mediaCache = <String, Uint8List>{};
  static const int _mediaCacheLimit = 32;

  bool loading = true;
  String? startupError;

  /// True when the browser gave us real, persistent storage.
  bool get persistent => _store.persistent;

  String? get storageWarning => _store.warning;

  /// Records moved aside because they could not be read.
  int quarantined = 0;

  /// Files referenced by entries but not present in storage.
  final List<MissingMedia> missingMedia = <MissingMedia>[];

  ThemeMode themeMode = ThemeMode.system;

  // Selection.
  Section section = Section.journals;
  String? journalId;
  String? entryId;
  bool editingEntry = false;

  /// Tag filter applied to lists and the timeline.
  String? tagFilter;

  // ------------------------------------------------------------------- load

  /// Reads everything the app needs, then checks that media still resolves.
  Future<void> load() async {
    try {
      final List<Journal> journals = await _store.loadJournals();
      final List<Entry> entries = await _store.loadEntries();
      _journals
        ..clear()
        ..addAll(journals..sort(_byName));
      _entries
        ..clear()
        ..addEntries(
          entries.map((Entry e) => MapEntry<String, Entry>(e.id, e)),
        );
      await _checkMedia();
    } on StoreFailure catch (error) {
      startupError = error.message;
    } catch (error) {
      startupError = 'journal.md could not read its local data: $error';
    }

    try {
      final Map<String, Object?> settings = await _store.loadSettings();
      final Object? mode = settings['themeMode'];
      themeMode = ThemeMode.values.firstWhere(
        (ThemeMode m) => m.name == mode,
        orElse: () => ThemeMode.system,
      );
      journalId = settings['lastJournalId'] as String?;
      if (journalId != null && journal(journalId!) == null) journalId = null;
      if (journalId == null && _journals.isNotEmpty) {
        journalId = _journals.first.id;
      }
    } catch (_) {
      // Preferences are optional; ignore anything unreadable.
    }

    quarantined = await _store.quarantineCount();
    loading = false;
    notifyListeners();
  }

  static int _byName(Journal a, Journal b) =>
      a.name.toLowerCase().compareTo(b.name.toLowerCase());

  /// Finds entries whose markdown points at a file we no longer have.
  Future<void> _checkMedia() async {
    missingMedia.clear();
    for (final Entry entry in _entries.values) {
      for (final String path in _assetPathsIn(entry)) {
        if (entry.media.any((MediaRef m) => m.path == path)) continue;
        final Uint8List? bytes = await _store.loadMediaBytes(path);
        if (bytes == null) missingMedia.add(MissingMedia(path, entry));
      }
    }
  }

  static Iterable<String> _assetPathsIn(Entry entry) {
    final Set<String> out = <String>{};
    final RegExp pattern = RegExp(r'\]\(((?:\.\./)*assets/[^)\s]+)\)');
    for (final RegExpMatch m in pattern.allMatches(entry.content)) {
      out.add(m.group(1)!.replaceAll(RegExp(r'^(\.\./)+'), ''));
    }
    return out;
  }

  // ------------------------------------------------------------------ reads

  List<Journal> get journals => List<Journal>.unmodifiable(_journals);

  /// Every entry, newest first.
  List<Entry> get allEntries {
    final List<Entry> list = _entries.values.toList()
      ..sort((Entry a, Entry b) => b.date.compareTo(a.date));
    return list;
  }

  /// All tags in use, most used first.
  List<String> get tags {
    final Map<String, int> counts = <String, int>{};
    for (final Entry e in _entries.values) {
      for (final String tag in e.tags) {
        counts[tag] = (counts[tag] ?? 0) + 1;
      }
    }
    final List<String> sorted = counts.keys.toList()
      ..sort((String a, String b) {
        final int byCount = counts[b]!.compareTo(counts[a]!);
        return byCount != 0 ? byCount : a.compareTo(b);
      });
    return sorted;
  }

  Journal? journal(String? id) {
    if (id == null) return null;
    for (final Journal j in _journals) {
      if (j.id == id) return j;
    }
    return null;
  }

  Entry? entry(String? id) => id == null ? null : _entries[id];

  Journal? get currentJournal => journal(journalId);

  Entry? get currentEntry => entry(entryId);

  List<Entry> entriesOf(String journalId) {
    final List<Entry> list = <Entry>[
      for (final Entry e in _entries.values)
        if (e.journalId == journalId) e,
    ]..sort((Entry a, Entry b) => b.date.compareTo(a.date));
    return list;
  }

  int entryCount(String journalId) =>
      _entries.values.where((Entry e) => e.journalId == journalId).length;

  DateTime? lastUpdated(String journalId) {
    final List<Entry> list = entriesOf(journalId);
    if (list.isEmpty) return null;
    return list
        .map((Entry e) => e.updatedAt)
        .reduce((DateTime a, DateTime b) => a.isAfter(b) ? a : b);
  }

  // ---------------------------------------------------------------- mutation

  Future<void> setThemeMode(ThemeMode mode) async {
    themeMode = mode;
    notifyListeners();
    await _store.saveSetting('themeMode', mode.name);
  }

  void selectJournal(String? id) {
    journalId = id;
    entryId = null;
    editingEntry = false;
    section = Section.journals;
    notifyListeners();
    if (id != null) unawaited(_store.saveSetting('lastJournalId', id));
  }

  void selectEntry(String? id, {bool edit = false}) {
    entryId = id;
    editingEntry = edit && id != null;
    notifyListeners();
  }

  void stopEditing() {
    editingEntry = false;
    notifyListeners();
  }

  void goTo(Section next) {
    section = next;
    notifyListeners();
  }

  void setTagFilter(String? tag) {
    tagFilter = tag;
    notifyListeners();
  }

  Future<Journal> createJournal(String name, {String description = ''}) async {
    final DateTime now = DateTime.now();
    final Journal journal = Journal(
      id: newId('j'),
      name: name.trim().isEmpty ? 'Untitled journal' : name.trim(),
      description: description.trim(),
      accent: accentFor(_journals.length),
      createdAt: now,
      updatedAt: now,
    );
    await _guardWrite(
      () => _store.saveJournal(journal),
      'Could not create the journal.',
    );
    _journals
      ..add(journal)
      ..sort(_byName);
    journalId = journal.id;
    entryId = null;
    section = Section.journals;
    notifyListeners();
    await _store.saveSetting('lastJournalId', journal.id);
    return journal;
  }

  Future<void> updateJournal(Journal journal) async {
    final Journal updated = journal.copyWith(updatedAt: DateTime.now());
    await _guardWrite(
      () => _store.saveJournal(updated),
      'Could not save the journal.',
    );
    final int at = _journals.indexWhere((Journal j) => j.id == updated.id);
    if (at == -1) {
      _journals.add(updated);
    } else {
      _journals[at] = updated;
    }
    _journals.sort(_byName);
    notifyListeners();
  }

  /// Deletes a journal, its entries and their files. Callers must confirm.
  Future<void> deleteJournal(String id) async {
    await _guardWrite(
      () => _store.deleteJournal(id),
      'Could not delete the journal.',
    );
    _journals.removeWhere((Journal j) => j.id == id);
    _entries.removeWhere((String _, Entry e) => e.journalId == id);
    _mediaCache.clear();
    if (journalId == id) {
      journalId = _journals.isEmpty ? null : _journals.first.id;
      entryId = null;
    }
    await _checkMedia();
    notifyListeners();
  }

  Future<Entry> createEntry(
    String journalId, {
    String title = '',
    DateTime? date,
  }) async {
    final DateTime now = DateTime.now();
    final Entry entry = Entry(
      id: newId('e'),
      journalId: journalId,
      title: title,
      date: date ?? now,
      createdAt: now,
      updatedAt: now,
    );
    await _guardWrite(
      () => _store.saveEntry(entry),
      'Could not create the entry.',
    );
    _entries[entry.id] = entry;
    entryId = entry.id;
    editingEntry = true;
    notifyListeners();
    return entry;
  }

  /// The single write path for entry edits: autosave and explicit saves both
  /// go through here, so they always behave the same way.
  Future<void> saveEntry(Entry entry) async {
    final Entry updated = entry.copyWith(updatedAt: DateTime.now());
    await _guardWrite(
      () => _store.saveEntry(updated),
      'Could not save this entry.',
    );
    _entries[updated.id] = updated;
    notifyListeners();
  }

  Future<void> deleteEntry(String id) async {
    await _guardWrite(
      () => _store.deleteEntry(id),
      'Could not delete this entry.',
    );
    _entries.remove(id);
    if (entryId == id) {
      entryId = null;
      editingEntry = false;
    }
    // Drop files nothing points at any more.
    await _store.pruneMedia(_entries.values.toList());
    _mediaCache.clear();
    await _checkMedia();
    notifyListeners();
  }

  /// Copies an entry including its files, so the two stay independent.
  Future<Entry?> duplicateEntry(String id) async {
    final Entry? source = _entries[id];
    if (source == null) return null;
    final DateTime now = DateTime.now();
    final List<MediaRef> copied = <MediaRef>[];
    final Set<String> taken = _liveMediaPaths();
    bool allCopied = true;

    for (final MediaRef ref in source.media) {
      final Uint8List? bytes = await _store.loadMediaBytes(ref.path);
      if (bytes == null) {
        allCopied = false;
        continue;
      }
      final String path = mediaPath(ref.kind, ref.mime, taken);
      taken.add(path);
      final MediaRef copy = MediaRef(
        id: newId('m'),
        kind: ref.kind,
        name: path.split('/').last,
        path: path,
        mime: ref.mime,
        size: bytes.length,
        duration: ref.duration,
      );
      await _guardWrite(
        () => _store.saveMedia(copy, bytes),
        'Could not copy a file with this entry.',
      );
      copied.add(copy);
    }

    // Point the body at the copied files so edits stay separate.
    String content = source.content;
    if (allCopied && copied.length == source.media.length) {
      for (int i = 0; i < source.media.length; i++) {
        content = content.replaceAll(
          'assets/${source.media[i].path.split('/').last}',
          'assets/${copied[i].path.split('/').last}',
        );
      }
    }

    final Entry copy = Entry(
      id: newId('e'),
      journalId: source.journalId,
      title: '${source.displayTitle} copy',
      content: content,
      tags: List<String>.of(source.tags),
      media: copied,
      date: DateTime(source.date.year, source.date.month, source.date.day),
      createdAt: now,
      updatedAt: now,
    );
    await _guardWrite(
      () => _store.saveEntry(copy),
      'Could not duplicate this entry.',
    );
    _entries[copy.id] = copy;
    entryId = copy.id;
    editingEntry = true;
    notifyListeners();
    return copy;
  }

  Set<String> _liveMediaPaths() => <String>{
    for (final Entry e in _entries.values)
      for (final MediaRef m in e.media) m.path,
  };

  /// Runs a write, turning failures into a visible notice instead of a crash.
  Future<void> _guardWrite(
    Future<void> Function() action,
    String message,
  ) async {
    try {
      await action();
    } on StoreFailure catch (error) {
      say(error.message);
      rethrow;
    } catch (error) {
      say('$message ($error)');
      rethrow;
    }
  }

  // ------------------------------------------------------------------- media

  /// Bytes for a stored file, cached so repeated builds stay cheap.
  Future<Uint8List?> mediaBytes(String path) async {
    final Uint8List? cached = _mediaCache[path];
    if (cached != null) return cached;
    final Uint8List? bytes = await _store.loadMediaBytes(path);
    if (bytes == null) return null;
    if (_mediaCache.length >= _mediaCacheLimit) {
      _mediaCache.remove(_mediaCache.keys.first);
    }
    _mediaCache[path] = bytes;
    return bytes;
  }

  /// Stores a file and returns its reference, or null if it could not be saved.
  Future<MediaRef?> addMedia({
    required Uint8List bytes,
    required String name,
    required String mime,
    required MediaKind kind,
    double duration = 0,
  }) async {
    final String path = mediaPath(kind, mime, _liveMediaPaths());
    final MediaRef ref = MediaRef(
      id: newId('m'),
      kind: kind,
      name: name.isEmpty ? path.split('/').last : name,
      path: path,
      mime: mime,
      size: bytes.length,
      duration: duration,
    );
    try {
      await _store.saveMedia(ref, bytes);
    } on StoreFailure catch (error) {
      say(error.message);
      return null;
    }
    _mediaCache[path] = bytes;
    return ref;
  }

  /// The markdown that represents [ref] inside an entry body.
  String mediaMarkdown(MediaRef ref) => ref.kind == MediaKind.voice
      ? '[${ref.name}](${ref.path})'
      : '![${ref.name}](${ref.path})';

  /// Detaches a file from an entry. Callers confirm before this runs.
  Future<void> removeMedia(Entry entry, MediaRef ref) async {
    final List<MediaRef> remaining = <MediaRef>[
      for (final MediaRef m in entry.media)
        if (m.path != ref.path) m,
    ];
    if (!_sharedWithOtherEntry(entry, ref)) {
      await _guardWrite(
        () => _store.deleteMedia(ref.path),
        'Could not delete the file.',
      );
    }
    _mediaCache.remove(ref.path);
    await saveEntry(
      entry.copyWith(
        media: remaining,
        content: _stripMedia(entry.content, ref.path),
      ),
    );
    await _checkMedia();
    notifyListeners();
  }

  /// True when another entry still points at the same file.
  bool _sharedWithOtherEntry(Entry except, MediaRef ref) {
    for (final Entry e in _entries.values) {
      if (e.id == except.id) continue;
      if (e.media.any((MediaRef m) => m.path == ref.path)) return true;
    }
    return false;
  }

  static String _stripMedia(String content, String path) {
    final String quoted = RegExp.escape(path);
    return content
        .replaceAll(RegExp('!\\[[^\\]]*\\]\\($quoted\\)'), '')
        .replaceAll(RegExp('\\[[^\\]]*\\]\\($quoted\\)'), '')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n');
  }

  // ------------------------------------------------------------------ search

  /// Looks through journal names, titles, bodies and tags.
  ///
  /// Words match with OR semantics and are ranked, so a title hit outranks a
  /// body hit. A `#tag` token restricts results to that tag.
  List<SearchHit> search(String rawQuery) {
    final List<String> tokens = rawQuery
        .trim()
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((String t) => t.isNotEmpty)
        .toList();
    if (tokens.isEmpty) return const <SearchHit>[];

    final List<String> tagTokens = <String>[];
    final List<String> words = <String>[];
    for (final String token in tokens) {
      if (token.startsWith('#')) {
        final String tag = normalizeTag(token);
        if (tag.isNotEmpty) tagTokens.add(tag);
      } else {
        words.add(token);
      }
    }

    final List<SearchHit> hits = <SearchHit>[];
    for (final Entry entry in _entries.values) {
      if (!tagTokens.every(
        (String t) => entry.tags.any((String tag) => tag.contains(t)),
      )) {
        continue;
      }

      final Journal? owner = journal(entry.journalId);
      final String title = entry.title.toLowerCase();
      final String body = entry.content.toLowerCase();
      final String journalName = (owner?.name ?? '').toLowerCase();
      final Set<String> where = <String>{};
      int score = tagTokens.length * 5;
      if (tagTokens.isNotEmpty) where.add('tags');

      for (final String word in words) {
        if (title.contains(word)) {
          score += 8;
          where.add('title');
        }
        if (entry.tags.any((String tag) => tag.contains(word))) {
          score += 5;
          where.add('tags');
        }
        if (journalName.contains(word)) {
          score += 3;
          where.add('journal');
        }
        if (body.contains(word)) {
          score += 2;
          where.add('content');
        }
      }

      if (score == 0) continue;
      if (words.isNotEmpty && where.isEmpty) continue;
      if (DateTime.now().difference(entry.date).inDays < 30) score += 1;

      hits.add(
        SearchHit(
          entry: entry,
          journal: owner,
          score: score,
          snippet: _snippet(entry, words),
          where: where,
        ),
      );
    }

    hits.sort((SearchHit a, SearchHit b) {
      final int byScore = b.score.compareTo(a.score);
      return byScore != 0 ? byScore : b.entry.date.compareTo(a.entry.date);
    });
    return hits;
  }

  /// A short excerpt around the first matching word, or the entry preview.
  static String _snippet(Entry entry, List<String> words) {
    final String flat = entry.content
        .replaceAll(RegExp(r'```[\s\S]*?```'), ' ⏎ ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (flat.isEmpty) return 'No content yet.';
    final String lower = flat.toLowerCase();
    int at = -1;
    for (final String word in words) {
      final int found = lower.indexOf(word);
      if (found != -1 && (at == -1 || found < at)) at = found;
    }
    if (at == -1) {
      return flat.length <= 160
          ? flat
          : '${flat.substring(0, 160).trimRight()}…';
    }
    final int start = (at - 50).clamp(0, flat.length);
    final int end = (at + 130).clamp(0, flat.length);
    return '${start > 0 ? '…' : ''}${flat.substring(start, end).trim()}'
        '${end < flat.length ? '…' : ''}';
  }

  // ------------------------------------------------------------- import/export

  /// Collects a journal, its entries and their files into a portable folder.
  ///
  /// Returns null when the journal does not exist. Missing files are skipped
  /// and reported, so an export never fails because of one bad reference.
  Future<Bundle?> buildExport(String journalId) async {
    final Journal? owner = journal(journalId);
    if (owner == null) return null;
    final List<Entry> entries = entriesOf(journalId);
    final List<MediaRecord> stored = await _store.loadAllMedia();
    final Map<String, Uint8List> bytesByPath = <String, Uint8List>{
      for (final MediaRecord r in stored) r.ref.path: r.bytes,
    };

    final List<MediaRecord> media = <MediaRecord>[];
    final Set<String> seen = <String>{};
    for (final Entry entry in entries) {
      for (final MediaRef ref in entry.media) {
        if (!seen.add(ref.path)) continue;
        final Uint8List? bytes = bytesByPath[ref.path];
        if (bytes == null) continue;
        // The entry's own ref carries the kind, name and duration.
        media.add(MediaRecord(ref, bytes));
      }
    }

    return exportJournal(journal: owner, entries: entries, media: media);
  }

  /// Every journal in one portable folder, one sub-folder per journal.
  /// Missing media is skipped per journal, never fatal.
  Future<Bundle> buildExportAll() async {
    final List<MediaRecord> stored = await _store.loadAllMedia();
    final Map<String, Uint8List> bytesByPath = <String, Uint8List>{
      for (final MediaRecord r in stored) r.ref.path: r.bytes,
    };

    final Map<String, List<int>> merged = <String, List<int>>{};
    String folderName = 'journal-md';
    for (final Journal owner in _journals) {
      final List<Entry> entries = entriesOf(owner.id);
      final List<MediaRecord> media = <MediaRecord>[];
      final Set<String> seen = <String>{};
      for (final Entry entry in entries) {
        for (final MediaRef ref in entry.media) {
          if (!seen.add(ref.path)) continue;
          final Uint8List? bytes = bytesByPath[ref.path];
          if (bytes == null) continue;
          media.add(MediaRecord(ref, bytes));
        }
      }
      final Bundle one = exportJournal(
        journal: owner,
        entries: entries,
        media: media,
      );
      if (_journals.length == 1) {
        merged.addAll(one.files);
        folderName = one.folder;
        continue;
      }
      for (final MapEntry<String, List<int>> file in one.files.entries) {
        merged['${one.folder}/${file.key}'] = file.value;
      }
    }
    return Bundle(folder: folderName, files: merged);
  }

  /// Writes an imported folder into this library and shows it.
  Future<ImportResult> importPortable(
    Bundle bundle, {
    String? fallbackName,
  }) async {
    final ImportResult result = importBundle(
      bundle,
      fallbackName: fallbackName,
    );
    await _guardWrite(
      () => _store.importAll(
        journals: <Journal>[result.journal],
        entries: result.entries,
        media: result.media,
      ),
      'Could not import this folder.',
    );
    _journals
      ..add(result.journal)
      ..sort(_byName);
    for (final Entry entry in result.entries) {
      _entries[entry.id] = entry;
    }
    _mediaCache.clear();
    await _checkMedia();
    journalId = result.journal.id;
    entryId = null;
    editingEntry = false;
    section = Section.journals;
    notifyListeners();
    return result;
  }

  /// Deletes everything stored locally. Callers must confirm first.
  Future<void> eraseEverything() async {
    await _guardWrite(_store.wipe, 'Could not clear local storage.');
    _journals.clear();
    _entries.clear();
    _mediaCache.clear();
    missingMedia.clear();
    journalId = null;
    entryId = null;
    editingEntry = false;
    section = Section.journals;
    notifyListeners();
  }

  /// A small written-in journal, offered on the empty state so the first run
  /// is not a blank page. Real content, not a placeholder screen.
  Future<void> createStarterJournal() async {
    final Journal journal = await createJournal(
      'Welcome',
      description:
          'A short tour of journal.md. Delete it whenever you like — nothing '
          'here is special.',
    );
    final DateTime now = DateTime.now();
    final Entry entry = Entry(
      id: newId('e'),
      journalId: journal.id,
      title: 'Start here',
      content: _starterEntry,
      tags: const <String>['welcome', 'markdown'],
      date: now,
      createdAt: now,
      updatedAt: now,
    );
    await _guardWrite(
      () => _store.saveEntry(entry),
      'Could not create the starter entry.',
    );
    _entries[entry.id] = entry;
    entryId = null;
    editingEntry = false;
    notifyListeners();
  }

  static const String _starterEntry = r'''
journal.md keeps every journal in this browser. Nothing is uploaded, nothing
needs an account, and the whole library can be exported to plain Markdown at
any time.

## Writing

**Bold**, *italic*, `inline code` and [links](https://commonmark.org) behave the
way you expect.

- Bullet lists
- With nested items
  - like this one

1. Numbered lists
2. Behave too

> Keep the ideas worth returning to in a quote.

---

### Code

```dart
Future<void> main() async {
  final store = await JournalStore.open();
  final journals = await store.loadJournals();
  print(journals.length);
}
```

### Tables

| Task | State |
| --- | --- |
| Sketch the board | done |
| Route the power plane | in progress |

## Files

Attach an image or record a voice note from the toolbar above an entry. Both are
stored locally, referenced with relative paths, and travel with an export.

Search finds this entry by title, by body text, or by tag: try `#welcome`.
''';

  @override
  void dispose() {
    _messages.close();
    super.dispose();
  }
}