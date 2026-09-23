/// Roundtrip tests for the export/import zip format.
///
/// The contract under test: what `buildExportZip` writes must be exactly
/// restorable by `parseImportZip` — same journals, same entries, same asset
/// bytes, and `attachment:<id>` references intact — while staying a
/// human-readable folder of markdown files.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:journal_md/import_export.dart';
import 'package:journal_md/models.dart';
import 'package:journal_md/store.dart';

/// A Store that keeps assets in memory instead of Hive, so the codec can be
/// exercised without a browser.
class _FakeStore extends Store {
  _FakeStore(this._assets);

  final Map<String, Uint8List> _assets;

  @override
  Uint8List? asset(String id) => _assets[id];

  @override
  bool hasAsset(String id) => _assets.containsKey(id);

  @override
  Future<void> putAsset(String id, Uint8List bytes) async {
    _assets[id] = bytes;
  }

  @override
  Future<void> deleteAsset(String id) async {
    _assets.remove(id);
  }
}

const _pngBytes = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 1, 2, 3, 4];
const _webmBytes = [0x1A, 0x45, 0xDF, 0xA3, 9, 9, 9, 9];

// Fixtures with zero seconds/millis (the export format stores minutes).
int _at(int y, int m, int d, int h, int min) =>
    DateTime(y, m, d, h, min).millisecondsSinceEpoch;

_StoreFixture _fixture() {
  final img = Attachment(
    id: 'IMG1',
    kind: 'image',
    name: 'photo.png',
    mime: 'image/png',
    size: _pngBytes.length,
    createdAt: _at(2026, 9, 20, 8, 0),
  );
  final vox = Attachment(
    id: 'VOX1',
    kind: 'audio',
    name: 'note.webm',
    mime: 'audio/webm',
    size: _webmBytes.length,
    createdAt: _at(2026, 9, 20, 8, 5),
  );

  final daily = Journal(
    id: 'J1',
    name: 'Daily Notes',
    description: 'small thoughts',
    createdAt: _at(2026, 1, 1, 0, 0),
    updatedAt: _at(2026, 9, 20, 8, 6),
  );
  final projects = Journal(
    id: 'J2',
    name: 'Projects',
    description: '',
    createdAt: _at(2026, 2, 1, 0, 0),
    updatedAt: _at(2026, 9, 21, 10, 0),
  );

  final morningContent = '# Morning pages\n'
      '\n'
      'Some **bold** text, a quote:\n'
      '\n'
      '> Keep it quiet.\n'
      '\n'
      '![photo](attachment:IMG1)\n'
      '\n'
      'A voice note: ![Voice note · 0:42](attachment:VOX1)\n';

  final store = _FakeStore({
    'IMG1': Uint8List.fromList(_pngBytes),
    'VOX1': Uint8List.fromList(_webmBytes),
  })
    ..journals.addAll([daily, projects])
    ..entries['E1'] = Entry(
      id: 'E1',
      journalId: 'J1',
      title: 'Morning pages',
      date: _at(2026, 9, 20, 8, 0),
      createdAt: _at(2026, 9, 20, 8, 0),
      updatedAt: _at(2026, 9, 20, 8, 6),
      tags: ['Writing', 'calm'],
      content: morningContent,
      attachments: [img, vox],
    )
    ..entries['E2'] = Entry(
      id: 'E2',
      journalId: 'J2',
      title: '',
      date: _at(2026, 9, 21, 10, 0),
      createdAt: _at(2026, 9, 21, 10, 0),
      updatedAt: _at(2026, 9, 21, 10, 0),
      tags: [],
      content: 'Keyboard rebuild notes.\n',
      attachments: [],
    );

  return _StoreFixture(store, morningContent);
}

class _StoreFixture {
  _StoreFixture(this.store, this.morningContent);
  final _FakeStore store;
  final String morningContent;
}

void main() {
  test('export → import restores the same data', () {
    final f = _fixture();
    final zip = buildExportZip(f.store);
    final parsed = parseImportZip(zip);

    // Journals: ids, names, descriptions, timestamps.
    expect(parsed.journals, hasLength(2));
    final j1 = parsed.journals.firstWhere((j) => j.id == 'J1');
    expect(j1.name, 'Daily Notes');
    expect(j1.description, 'small thoughts');
    expect(j1.createdAt, _at(2026, 1, 1, 0, 0));
    final j2 = parsed.journals.firstWhere((j) => j.id == 'J2');
    expect(j2.name, 'Projects');

    // Entries: ids, journal links, titles, dates, tags.
    expect(parsed.entries, hasLength(2));
    final e1 = parsed.entries.firstWhere((e) => e.id == 'E1');
    expect(e1.journalId, 'J1');
    expect(e1.title, 'Morning pages');
    expect(e1.date, _at(2026, 9, 20, 8, 0));
    expect(e1.tags, ['writing', 'calm']);
    final e2 = parsed.entries.firstWhere((e) => e.id == 'E2');
    expect(e2.journalId, 'J2');
    expect(e2.title, '');
    expect(e2.content, 'Keyboard rebuild notes.\n');

    // Content: attachment refs survive the export-path rewrite roundtrip.
    expect(e1.content, f.morningContent);
    expect(e1.content.contains('attachment:IMG1'), isTrue);
    expect(e1.content.contains('attachment:VOX1'), isTrue);

    // Attachments: metadata restored.
    expect(e1.attachments, hasLength(2));
    final img = e1.attachments.firstWhere((a) => a.id == 'IMG1');
    expect(img.kind, 'image');
    expect(img.mime, 'image/png');
    expect(img.size, _pngBytes.length);
    expect(img.isImage, isTrue);
    final vox = e1.attachments.firstWhere((a) => a.id == 'VOX1');
    expect(vox.kind, 'audio');
    expect(vox.isAudio, isTrue);

    // Assets: exact bytes restored.
    expect(parsed.assets, hasLength(2));
    expect(parsed.assets['IMG1'], Uint8List.fromList(_pngBytes));
    expect(parsed.assets['VOX1'], Uint8List.fromList(_webmBytes));
  });

  test('the zip is a human-readable folder of markdown files', () {
    final f = _fixture();
    final archive = ZipDecoder().decodeBytes(buildExportZip(f.store));
    final names = [for (final file in archive.files) if (file.isFile) file.name];

    expect(names, contains('manifest.json'));
    expect(names, contains('Daily Notes/morning-pages.md'));
    expect(names, contains('Projects/2026-09-21.md'));
    expect(names, contains('assets/image-001.png'));
    expect(names, contains('assets/voice-001.webm'));

    // The markdown file carries front matter a human can read.
    final md = utf8.decode(
        archive.files.firstWhere((f) => f.name == 'Daily Notes/morning-pages.md').content);
    expect(md.startsWith('---\n'), isTrue);
    expect(md, contains('title: Morning pages'));
    expect(md, contains('date: 2026-09-20T08:00'));
    expect(md, contains('tags: Writing, calm'));
    expect(md, contains('id: E1'));
    // Attachment refs point at the readable asset paths.
    expect(md, contains('![photo](assets/image-001.png)'));

    // The manifest carries the internal ids for idempotent import.
    final manifest =
        jsonDecode(utf8.decode(archive.files.firstWhere((f) => f.name == 'manifest.json').content))
            as Map<String, dynamic>;
    expect(manifest['app'], 'journal.md');
    expect((manifest['journals'] as List).length, 2);
  });

  test('importing the same backup twice is a no-op the second time', () async {
    final f = _fixture();
    final zip = buildExportZip(f.store);
    final parsed = parseImportZip(zip);

    final target = _FakeStore({});
    final first = await target.mergeImport(
      newJournals: parsed.journals,
      newEntries: parsed.entries,
      newAssets: parsed.assets,
      dedupeJournalName: (n) => n,
    );
    expect(first.journals, 2);
    expect(first.entries, 2);
    expect(first.assets, 2);

    final second = await target.mergeImport(
      newJournals: parsed.journals,
      newEntries: parsed.entries,
      newAssets: parsed.assets,
      dedupeJournalName: (n) => n,
    );
    expect(second.journals, 0);
    expect(second.entries, 0);
    expect(second.assets, 0);
    expect(second.skipped, greaterThanOrEqualTo(4));

    // Nothing was duplicated in the store itself.
    expect(target.journals, hasLength(2));
    expect(target.entries, hasLength(2));
    target.dispose();
    f.store.dispose();
  });

  test('rejects garbage bytes with a friendly failure', () {
    // archive's decoder is lenient with garbage, so garbage lands at the
    // manifest lookup — either way the user sees a friendly failure.
    expect(
      () => parseImportZip(Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8])),
      throwsA(isA<ImportFailure>().having(
        (e) => e.message,
        'message',
        anyOf(
          contains('not a readable journal.md backup'),
          contains('No manifest.json'),
        ),
      )),
    );
  });

  test('rejects a zip without a manifest', () {
    final archive = Archive()..addFile(ArchiveFile.string('hello.txt', 'hi'));
    final bytes = ZipEncoder().encodeBytes(archive);
    expect(
      () => parseImportZip(bytes),
      throwsA(isA<ImportFailure>().having(
        (e) => e.message,
        'message',
        contains('No manifest.json'),
      )),
    );
  });

  test('corrupt manifest json fails cleanly', () {
    final archive = Archive()
      ..addFile(ArchiveFile.string('manifest.json', '{not json'));
    final bytes = ZipEncoder().encodeBytes(archive);
    expect(
      () => parseImportZip(bytes),
      throwsA(isA<ImportFailure>()),
    );
  });
}
