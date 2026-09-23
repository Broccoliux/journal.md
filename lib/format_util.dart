/// Small formatting + media-sniffing helpers shared across the app.
library;

import 'dart:math' as math;
import 'dart:typed_data';

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];
const _monthsLong = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];

String _two(int n) => n.toString().padLeft(2, '0');

DateTime _dt(int ms) => DateTime.fromMillisecondsSinceEpoch(ms);

/// `Sep 23, 2026`
String formatDateShort(int ms) {
  final d = _dt(ms);
  return '${_months[d.month - 1]} ${d.day}, ${d.year}';
}

/// `September 23, 2026`
String formatDateLong(int ms) {
  final d = _dt(ms);
  return '${_monthsLong[d.month - 1]} ${d.day}, ${d.year}';
}

/// `Sep 23, 2026 · 09:41`
String formatDateTime(int ms) {
  final d = _dt(ms);
  return '${_months[d.month - 1]} ${d.day}, ${d.year} · '
      '${_two(d.hour)}:${_two(d.minute)}';
}

/// `09:41`
String formatTime(int ms) {
  final d = _dt(ms);
  return '${_two(d.hour)}:${_two(d.minute)}';
}

/// `September 2026` — timeline group headers.
String formatMonthYear(int ms) {
  final d = _dt(ms);
  return '${_monthsLong[d.month - 1]} ${d.year}';
}

/// Weekday for timeline rows, e.g. `Mon`.
String formatWeekday(int ms) {
  const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  final d = _dt(ms);
  return days[d.weekday - 1];
}

int _startOfDay(DateTime d) =>
    DateTime(d.year, d.month, d.day).millisecondsSinceEpoch;

/// `today`, `yesterday`, `2 days ago`, or a short date.
String formatRelativeDay(int ms) {
  final today = _startOfDay(DateTime.now());
  final day = _startOfDay(_dt(ms));
  final diff = (today - day) / Duration.millisecondsPerDay;
  if (diff == 0) return 'today';
  if (diff == 1) return 'yesterday';
  if (diff > 1 && diff < 7) return '$diff days ago';
  return formatDateShort(ms);
}

/// `Updated today`, `Updated Sep 12` — journal rows.
String formatUpdatedLabel(int ms) {
  if (ms <= 0) return '';
  return 'Updated ${formatRelativeDay(ms)}';
}

/// `1.4 MB`, `912 KB`
String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

/// `0:34`, `12:05` — voice note durations / recorder timer.
String formatDuration(Duration d) {
  final m = d.inMinutes;
  final s = d.inSeconds % 60;
  return '$m:${_two(s)}';
}

/// Lowercase slug suitable for filenames: `Keyboard Project → keyboard-project`.
String slugify(String input) {
  final slug = input
      .toLowerCase()
      .replaceAll(RegExp(r"[^a-z0-9\s-]"), '')
      .trim()
      .replaceAll(RegExp(r'\s+'), '-')
      .replaceAll(RegExp(r'-+'), '-');
  return slug.isEmpty ? 'untitled' : slug;
}

/// Folder-safe name (no slashes, control chars, no leading dot).
String sanitizeFolderName(String name) {
  var clean = name
      .replaceAll(RegExp(r'[\\/\x00-\x1f]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (clean.isEmpty) clean = 'Untitled';
  if (clean.startsWith('.')) clean = '_$clean';
  if (clean.length > 60) clean = clean.substring(0, 60).trim();
  return clean;
}

/// Detect an audio container from magic bytes: WebM/MP4.
String sniffAudioMime(Uint8List bytes) {
  if (bytes.length >= 4) {
    // EBML header — WebM.
    if (bytes[0] == 0x1A && bytes[1] == 0x45 && bytes[2] == 0xDF && bytes[3] == 0xA3) {
      return 'audio/webm';
    }
  }
  if (bytes.length >= 12) {
    // 'ftyp' at offset 4 — ISO/MP4 container.
    if (bytes[4] == 0x66 && bytes[5] == 0x74 && bytes[6] == 0x79 && bytes[7] == 0x70) {
      return 'audio/mp4';
    }
  }
  return 'audio/webm';
}

/// Detect an image format from magic bytes.
String? sniffImageMime(Uint8List bytes) {
  if (bytes.length >= 8) {
    if (bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47) {
      return 'image/png';
    }
    if (bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) {
      return 'image/jpeg';
    }
    if (bytes[0] == 0x47 && bytes[1] == 0x49 && bytes[2] == 0x46) {
      return 'image/gif';
    }
  }
  if (bytes.length >= 12) {
    if (bytes[0] == 0x52 && bytes[1] == 0x49 && bytes[2] == 0x46 && bytes[3] == 0x46 &&
        bytes[8] == 0x57 && bytes[9] == 0x45 && bytes[10] == 0x42 && bytes[11] == 0x50) {
      return 'image/webp';
    }
  }
  return null;
}

String extensionForMime(String? mime) {
  switch (mime) {
    case 'image/png':
      return 'png';
    case 'image/jpeg':
      return 'jpg';
    case 'image/gif':
      return 'gif';
    case 'image/webp':
      return 'webp';
    case 'audio/webm':
      return 'webm';
    case 'audio/mp4':
      return 'm4a';
    case 'audio/mpeg':
      return 'mp3';
    default:
      return 'bin';
  }
}

/// A deterministic, presentation-only waveform for a voice-note player.
///
/// Dart never sees raw PCM in the browser, so this derives a stable
/// pseudo-envelope from the compressed bytes: windowed energy, light
/// smoothing, and a content-seeded jitter so that even tightly packed
/// containers read as a lively voice. The same recording always draws the
/// same shape, and values land in a visible `0.15 … 1.0` band.
List<double> waveformFromBytes(Uint8List bytes, {int barCount = 40}) {
  if (barCount <= 0) return const <double>[];

  // A small xorshift PRNG seeded from the bytes. Bit-ops only, so VM and web
  // produce identical values.
  var seed = 0x2545f491;
  for (var i = 0; i < bytes.length; i += 8) {
    seed ^= bytes[i] + (i & 0xff);
    seed &= 0x7fffffff;
    seed ^= (seed << 13) & 0x7fffffff;
    seed ^= seed >> 17;
    seed &= 0x7fffffff;
  }
  if (seed == 0) seed = 0x9e37;

  double nextUnit() {
    seed ^= (seed << 13) & 0x7fffffff;
    seed ^= seed >> 17;
    seed ^= (seed << 5) & 0x7fffffff;
    seed &= 0x7fffffff;
    return (seed & 0xffff) / 65535.0;
  }

  // Windowed byte energy — container structure still pokes through.
  final energy = List<double>.filled(barCount, 0.5);
  for (var i = 0; i < barCount; i++) {
    final start = bytes.length * i ~/ barCount;
    final end = bytes.length * (i + 1) ~/ barCount;
    if (end <= start) continue;
    var sum = 0;
    for (var j = start; j < end; j++) {
      sum += (bytes[j] - 128).abs();
    }
    energy[i] = (sum / (end - start) / 128.0).clamp(0.0, 1.0);
  }

  // Light smoothing so neighbouring bars flow into each other.
  final smoothed = List<double>.generate(barCount, (i) {
    final prev = energy[i == 0 ? 0 : i - 1];
    final next = energy[i == barCount - 1 ? barCount - 1 : i + 1];
    return (prev + 2 * energy[i] + next) / 4;
  });

  // Blend energy with the jitter, then normalise into a visible band.
  final blended = List<double>.generate(
    barCount,
    (i) => (0.55 * smoothed[i] + 0.45 * nextUnit()).clamp(0.0, 1.0),
    growable: false,
  );
  final peak = blended.reduce(math.max);
  return List<double>.generate(
    barCount,
    (i) => (0.15 + 0.85 * (peak <= 0 ? 0.5 : blended[i] / peak)).clamp(0.0, 1.0),
    growable: false,
  );
}
