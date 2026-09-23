/// Unit tests for the data model + whole-database codec.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:journal_md/models.dart';

void main() {
  group('newId', () {
    test('is unique and roughly sortable', () {
      final a = newId();
      final b = newId();
      expect(a, isNot(equals(b)));
      expect(a.length, greaterThanOrEqualTo(8));
    });
  });

  group('db codec', () {
    test('roundtrips journals and entries', () {
      final j = Journal(
        id: 'j1',
        name: 'Daily',
        description: 'small thoughts',
        createdAt: 1000,
        updatedAt: 2000,
      );
      final e = Entry(
        id: 'e1',
        journalId: 'j1',
        title: 'Morning',
        date: 1234,
        createdAt: 1234,
        updatedAt: 2345,
        tags: ['Coffee', 'calm'],
        content: '# Hello\n\nWorld',
        attachments: [
          Attachment(
            id: 'a1',
            kind: 'image',
            name: 'photo.png',
            mime: 'image/png',
            size: 10,
            createdAt: 1234,
          ),
        ],
      );

      final db = decodeDb(encodeDb([j], [e]));

      expect(db.journals, hasLength(1));
      final j2 = db.journals.single;
      expect(j2.id, 'j1');
      expect(j2.name, 'Daily');
      expect(j2.description, 'small thoughts');
      expect(j2.createdAt, 1000);
      expect(j2.updatedAt, 2000);

      final e2 = db.entries.single;
      expect(e2.id, 'e1');
      expect(e2.journalId, 'j1');
      expect(e2.title, 'Morning');
      expect(e2.date, 1234);
      expect(e2.content, '# Hello\n\nWorld');
      // Tags are normalized to lowercase on decode.
      expect(e2.tags, ['coffee', 'calm']);
      expect(e2.attachments, hasLength(1));
      expect(e2.attachments.single.id, 'a1');
      expect(e2.attachments.single.mime, 'image/png');
      expect(e2.images, isNotEmpty);
      expect(e2.audioNotes, isEmpty);
    });

    test('decodes an empty database', () {
      final db = decodeDb('{"version":1,"journals":[],"entries":[]}');
      expect(db.journals, isEmpty);
      expect(db.entries, isEmpty);
    });

    test('is resilient to missing optional fields', () {
      final e = Entry.fromJson({'id': 'x'});
      expect(e.journalId, '');
      expect(e.title, '');
      expect(e.date, 0);
      expect(e.tags, isEmpty);
      expect(e.content, '');
      expect(e.attachments, isEmpty);

      final a = Attachment.fromJson({'id': 'a'});
      expect(a.kind, 'image');
      expect(a.size, 0);
    });

    test('date falls back to createdAt when missing', () {
      final e = Entry.fromJson({'id': 'x', 'createdAt': 777});
      expect(e.date, 777);
    });
  });

  group('Entry.duplicate', () {
    test('copies content with a new id and "(copy)" title', () {
      final e = Entry(
        id: 'e1',
        journalId: 'j1',
        title: 'Trip',
        date: 1234,
        createdAt: 1234,
        updatedAt: 2345,
        tags: ['travel'],
        content: 'body',
        attachments: [
          Attachment(
            id: 'a1',
            kind: 'audio',
            name: 'note.webm',
            mime: 'audio/webm',
            size: 5,
            createdAt: 1234,
          ),
        ],
      );
      final copy = e.duplicate();

      expect(copy.id, isNot('e1'));
      expect(copy.journalId, 'j1');
      expect(copy.title, 'Trip (copy)');
      expect(copy.tags, ['travel']);
      expect(copy.content, 'body');
      expect(copy.attachments.single.id, 'a1');
      expect(copy.audioNotes, isNotEmpty);
    });

    test('uses "Copy" for untitled entries', () {
      final e = Entry(
          id: 'e1', journalId: 'j1', date: 1, createdAt: 1, updatedAt: 1);
      expect(e.duplicate().title, 'Copy');
    });
  });
}
