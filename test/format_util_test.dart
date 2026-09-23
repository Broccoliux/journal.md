/// Unit tests for formatting + sniffing helpers.
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:journal_md/format_util.dart';

void main() {
  group('date formatting', () {
    // 2026-09-23 09:41 local time.
    final ms = DateTime(2026, 9, 23, 9, 41).millisecondsSinceEpoch;

    test('formatDateShort', () => expect(formatDateShort(ms), 'Sep 23, 2026'));
    test('formatDateLong',
        () => expect(formatDateLong(ms), 'September 23, 2026'));
    test('formatDateTime',
        () => expect(formatDateTime(ms), 'Sep 23, 2026 · 09:41'));
    test('formatTime', () => expect(formatTime(ms), '09:41'));
    test('formatMonthYear', () => expect(formatMonthYear(ms), 'September 2026'));
    test('formatWeekday', () => expect(formatWeekday(ms), 'Wed'));
    test('formatRelativeDay for today', () {
      final now = DateTime.now().millisecondsSinceEpoch;
      expect(formatRelativeDay(now), 'today');
    });
    test('formatRelativeDay for yesterday', () {
      final y = DateTime.now()
          .subtract(const Duration(days: 1))
          .millisecondsSinceEpoch;
      expect(formatRelativeDay(y), 'yesterday');
    });
  });

  group('bytes and durations', () {
    test('formatBytes', () {
      expect(formatBytes(512), '512 B');
      expect(formatBytes(1024), '1 KB');
      expect(formatBytes(1024 * 1024), '1.0 MB');
      expect(formatBytes(1536 * 1024), '1.5 MB');
    });

    test('formatDuration', () {
      expect(formatDuration(const Duration(seconds: 34)), '0:34');
      expect(formatDuration(const Duration(minutes: 12, seconds: 5)), '12:05');
    });
  });

  group('slugify', () {
    test('keeps words, drops punctuation', () {
      expect(slugify('Keyboard Project!'), 'keyboard-project');
    });

    test('collapses repeated separators', () {
      expect(slugify('  a   b  '), 'a-b');
    });

    test('falls back to untitled', () {
      expect(slugify('***'), 'untitled');
    });
  });

  group('sanitizeFolderName', () {
    test('strips slashes and control characters', () {
      expect(sanitizeFolderName('a/b\\c'), 'a b c');
    });

    test('never empty', () {
      expect(sanitizeFolderName('   '), 'Untitled');
    });

    test('no leading dot', () {
      expect(sanitizeFolderName('.hidden'), '_.hidden');
    });

    test('caps length at 60', () {
      expect(sanitizeFolderName('a' * 80).length, 60);
    });

    test('reserves nothing weird for "assets"', () {
      // The export code renames "assets" folders itself; sanitize only
      // guarantees folder-safety.
      expect(sanitizeFolderName('assets'), 'assets');
    });
  });

  group('MIME sniffing', () {
    test('recognises png, jpeg, gif, webp', () {
      expect(
        sniffImageMime(
            Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])),
        'image/png',
      );
      expect(
        sniffImageMime(Uint8List.fromList(
            [0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46])),
        'image/jpeg',
      );
      expect(
        sniffImageMime(Uint8List.fromList(
            [0x47, 0x49, 0x46, 0x38, 0x39, 0x61, 0x00, 0x00])),
        'image/gif',
      );
      expect(
        sniffImageMime(Uint8List.fromList([
          0x52, 0x49, 0x46, 0x46, 0x00, 0x00, 0x00, 0x00, 0x57, 0x45, 0x42, 0x50
        ])),
        'image/webp',
      );
      expect(sniffImageMime(Uint8List.fromList([1, 2, 3])), isNull);
    });

    test('recognises webm and mp4 audio', () {
      expect(
        sniffAudioMime(Uint8List.fromList([0x1A, 0x45, 0xDF, 0xA3, 0x00])),
        'audio/webm',
      );
      expect(
        sniffAudioMime(Uint8List.fromList([
          0x00, 0x00, 0x00, 0x18, 0x66, 0x74, 0x79, 0x70, 0x4D, 0x34, 0x41, 0x00
        ])),
        'audio/mp4',
      );
    });

    test('extensionForMime', () {
      expect(extensionForMime('image/png'), 'png');
      expect(extensionForMime('image/jpeg'), 'jpg');
      expect(extensionForMime('audio/webm'), 'webm');
      expect(extensionForMime('audio/mp4'), 'm4a');
      expect(extensionForMime(null), 'bin');
    });
  });

  group('waveformFromBytes', () {
    Uint8List sample(int length) =>
        Uint8List.fromList(List<int>.generate(length, (i) => (i * 37) % 256));

    test('returns the requested number of bars', () {
      expect(waveformFromBytes(sample(4096)), hasLength(40));
      expect(waveformFromBytes(sample(4096), barCount: 12), hasLength(12));
    });

    test('bar values stay in the visible 0..1 band', () {
      for (final v in waveformFromBytes(sample(2048))) {
        expect(v, inInclusiveRange(0.0, 1.0));
      }
    });

    test('is deterministic for the same bytes', () {
      final a = waveformFromBytes(sample(3000), barCount: 24);
      final b = waveformFromBytes(sample(3000), barCount: 24);
      expect(a, equals(b));
    });

    test('different recordings draw different shapes', () {
      final a = waveformFromBytes(sample(1024));
      final b = waveformFromBytes(
          Uint8List.fromList(List<int>.generate(1024, (i) => (i * 91) % 256)));
      expect(a, isNot(equals(b)));
    });

    test('handles empty and tiny byte arrays', () {
      final empty = waveformFromBytes(Uint8List(0));
      expect(empty, hasLength(40));
      expect(empty.every((v) => v >= 0.15),
          isTrue,
          reason: 'even silent input should draw a quiet visible line');
      expect(waveformFromBytes(Uint8List.fromList([7])), hasLength(40));
    });

    test('barCount 0 yields no bars', () {
      expect(waveformFromBytes(sample(64), barCount: 0), isEmpty);
    });
  });
}
