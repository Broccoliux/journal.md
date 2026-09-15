/// Local voice notes.
///
/// Recording and playback use the browser's own microphone and audio APIs.
/// Nothing is transcribed, uploaded or sent anywhere. Off the web these
/// implementations report failure and [audioSupported] is false, so callers can
/// hide the feature instead of crashing.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

/// False on platforms without microphone support.
bool get audioSupported => false;

/// A finished recording.
class RecordedClip {
  const RecordedClip({
    required this.bytes,
    required this.mime,
    required this.seconds,
  });

  final Uint8List bytes;
  final String mime;
  final double seconds;
}

/// A recording problem worth showing the user, with a readable reason.
class RecordingFailure implements Exception {
  RecordingFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Records from the microphone. Create one with [createVoiceRecorder].
abstract class VoiceRecorder {
  bool get isRecording;

  bool get isPaused;

  Duration get elapsed;

  /// Fires a few times a second while recording, for the timer display.
  Stream<Duration> get ticks;

  Future<void> start();

  Future<void> pause();

  Future<void> resume();

  Future<RecordedClip> stop();

  /// Throws the current recording away.
  Future<void> cancel();

  void dispose();
}

/// Plays one recorded clip. Create one with [createVoicePlayer].
abstract class VoicePlayer extends ChangeNotifier {
  bool get ready;

  bool get playing;

  Duration get position;

  Duration get duration;

  Future<void> load(Uint8List bytes, String mime);

  Future<void> toggle();

  Future<void> seek(Duration to);

  Future<void> stop();
}

/// Nothing to record with, but the app still runs.
VoiceRecorder createVoiceRecorder() => _NoRecorder();

VoicePlayer createVoicePlayer() => _NoPlayer();

class _NoRecorder implements VoiceRecorder {
  @override
  bool get isRecording => false;

  @override
  bool get isPaused => false;

  @override
  Duration get elapsed => Duration.zero;

  @override
  Stream<Duration> get ticks => const Stream<Duration>.empty();

  @override
  Future<void> start() async =>
      throw RecordingFailure('Recording needs a browser microphone.');

  @override
  Future<void> pause() async {}

  @override
  Future<void> resume() async {}

  @override
  Future<RecordedClip> stop() async =>
      throw RecordingFailure('Recording needs a browser microphone.');

  @override
  Future<void> cancel() async {}

  @override
  void dispose() {}
}

class _NoPlayer extends VoicePlayer {
  @override
  bool get ready => false;

  @override
  bool get playing => false;

  @override
  Duration get position => Duration.zero;

  @override
  Duration get duration => Duration.zero;

  @override
  Future<void> load(Uint8List bytes, String mime) async =>
      throw UnsupportedError('Playback needs a browser audio element.');

  @override
  Future<void> toggle() async {}

  @override
  Future<void> seek(Duration to) async {}

  @override
  Future<void> stop() async {}
}