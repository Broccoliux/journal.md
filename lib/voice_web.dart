/// Microphone recording and audio playback, straight from browser APIs.
///
/// No transcription, no upload: recorded bytes go into local storage and are
/// played back through a blob URL. Only this file knows about the DOM audio
/// APIs; the UI works through the interfaces in `voice_stub.dart`.
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'voice_stub.dart';
import 'web_io.dart';

/// The types are shared with the stub; only the three entry points differ.
export 'voice_stub.dart'
    hide audioSupported, createVoiceRecorder, createVoicePlayer;

bool get audioSupported => _mediaDevicesAvailable();

bool _mediaDevicesAvailable() {
  try {
    return web.window.navigator.mediaDevices != null;
  } catch (_) {
    return false;
  }
}

VoiceRecorder createVoiceRecorder() => WebVoiceRecorder();

VoicePlayer createVoicePlayer() => WebVoicePlayer();

// ------------------------------------------------------------- raw bindings

@JS('navigator.mediaDevices')
external _MediaDevices get _mediaDeviceQuery;

extension type _MediaDevices._(JSObject _) implements JSObject {
  external JSPromise<JSObject> getUserMedia(JSObject constraints);
}

@JS('MediaRecorder')
extension type _MediaRecorder._(JSObject _) implements JSObject {
  external factory _MediaRecorder(JSObject stream, [JSObject? options]);
  external void start();
  external void stop();
  external void pause();
  external void resume();
  external set ondataavailable(JSFunction handler);
  external set onstop(JSFunction handler);
  external set onerror(JSFunction handler);
}

extension type _BlobEvent._(JSObject _) implements JSObject {
  external web.Blob get data;
}

extension type _MediaStream._(JSObject _) implements JSObject {
  external JSArray<JSObject> getTracks();
}

extension type _MediaStreamTrack._(JSObject _) implements JSObject {
  external void stop();
}

// --------------------------------------------------------------- recorder

/// Records from the microphone.
class WebVoiceRecorder implements VoiceRecorder {
  _MediaRecorder? _recorder;
  _MediaStream? _stream;
  final List<web.Blob> _chunks = <web.Blob>[];
  final Stopwatch _clock = Stopwatch();
  final StreamController<Duration> _ticks =
      StreamController<Duration>.broadcast();
  Timer? _timer;
  bool _stopping = false;
  bool _paused = false;

  @override
  bool get isRecording => _recorder != null;

  @override
  bool get isPaused => _paused;

  @override
  Duration get elapsed => _clock.elapsed;

  @override
  Stream<Duration> get ticks => _ticks.stream;

  @override
  Future<void> start() async {
    if (_recorder != null) return;
    final JSObject stream;
    try {
      stream = await _mediaDeviceQuery
          .getUserMedia(<String, Object?>{'audio': true}.jsify()! as JSObject)
          .toDart;
    } on Object catch (error) {
      throw RecordingFailure(_friendlyMicError(error));
    }
    _stream = _MediaStream._(stream);
    _recorder = _MediaRecorder(stream);
    _chunks.clear();
    _stopping = false;
    _paused = false;
    _recorder!.ondataavailable = ((JSObject event) {
      final web.Blob blob = _BlobEvent._(event).data;
      if (blob.size > 0) _chunks.add(blob);
    }).toJS;
    _recorder!.onerror = ((JSObject _) => _release()).toJS;

    try {
      _recorder!.start();
    } catch (error) {
      _release();
      throw RecordingFailure(
        'This browser would not start a recording. Check that the microphone '
        'is free and try again. ($error)',
      );
    }
    _clock
      ..reset()
      ..start();
    _timer = Timer.periodic(
      const Duration(milliseconds: 250),
      (_) => _ticks.add(_clock.elapsed),
    );
  }

  @override
  Future<void> pause() async {
    if (_recorder == null || _paused) return;
    try {
      _recorder!.pause();
      _paused = true;
      _clock.stop();
    } catch (_) {
      // Not every browser supports pausing mid-recording.
    }
  }

  @override
  Future<void> resume() async {
    if (_recorder == null || !_paused) return;
    try {
      _recorder!.resume();
      _paused = false;
      _clock.start();
    } catch (_) {}
  }

  @override
  Future<RecordedClip> stop() async {
    final _MediaRecorder? recorder = _recorder;
    if (recorder == null || _stopping) {
      throw RecordingFailure('There is no recording in progress.');
    }
    _stopping = true;
    final double seconds = _clock.elapsed.inMilliseconds / 1000;
    _clock.stop();
    _timer?.cancel();
    _timer = null;

    final Completer<void> stopped = Completer<void>();
    recorder.onstop = ((JSObject _) {
      if (!stopped.isCompleted) stopped.complete();
    }).toJS;
    try {
      recorder.stop();
    } catch (_) {
      if (!stopped.isCompleted) stopped.complete();
    }
    await stopped.future.timeout(const Duration(seconds: 5), onTimeout: () {});

    final Uint8List bytes = await _collect();
    _release();
    if (bytes.isEmpty) {
      throw RecordingFailure('The recording came back empty. Nothing saved.');
    }
    return RecordedClip(bytes: bytes, mime: 'audio/webm', seconds: seconds);
  }

  @override
  Future<void> cancel() async {
    try {
      _recorder?.stop();
    } catch (_) {}
    _release();
  }

  @override
  void dispose() {
    _release();
    _ticks.close();
  }

  Future<Uint8List> _collect() async {
    if (_chunks.isEmpty) return Uint8List(0);
    final List<JSAny> parts = <JSAny>[];
    for (final web.Blob blob in _chunks) {
      parts.add(blob);
    }
    final web.Blob blob = web.Blob(
      parts.toJS,
      web.BlobPropertyBag(type: 'audio/webm'),
    );
    final JSArrayBuffer buffer = await blob.arrayBuffer().toDart;
    return buffer.toDart.asUint8List();
  }

  void _release() {
    _timer?.cancel();
    _timer = null;
    _clock.stop();
    final _MediaStream? stream = _stream;
    if (stream != null) {
      try {
        for (final JSObject track in stream.getTracks().toDart) {
          _MediaStreamTrack._(track).stop();
        }
      } catch (_) {}
    }
    _recorder = null;
    _stream = null;
    _stopping = false;
    _paused = false;
  }
}

/// Turns a DOM exception into something a person can act on.
String _friendlyMicError(Object error) {
  final String raw = '$error';
  if (raw.contains('NotAllowedError') ||
      raw.toLowerCase().contains('permission')) {
    return 'Microphone access was blocked. Allow the microphone for this site '
        'in your browser settings, then try again.';
  }
  if (raw.contains('NotFoundError') || raw.contains('DevicesNotFound')) {
    return 'No microphone was found on this device.';
  }
  if (raw.contains('NotReadableError')) {
    return 'The microphone is already in use by another application.';
  }
  return 'The microphone could not be started. ($raw)';
}

// ------------------------------------------------------------------- player

/// Plays a stored clip through a hidden audio element.
class WebVoicePlayer extends VoicePlayer {
  web.HTMLAudioElement? _audio;
  String _url = '';
  JSFunction? _onTime;
  JSFunction? _onEnded;
  JSFunction? _onLoaded;
  bool _ready = false;
  bool _playing = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  @override
  bool get ready => _ready;

  @override
  bool get playing => _playing;

  @override
  Duration get position => _position;

  @override
  Duration get duration => _duration;

  @override
  Future<void> load(Uint8List bytes, String mime) async {
    _disposeElement();
    _url = createObjectUrl(bytes, mime);
    final web.HTMLAudioElement audio =
        web.document.createElement('audio') as web.HTMLAudioElement;
    audio.src = _url;
    audio.preload = 'metadata';

    _onLoaded = ((JSObject _) {
      final num seconds = audio.duration;
      _duration = seconds.isFinite
          ? Duration(milliseconds: (seconds * 1000).round())
          : Duration.zero;
      _ready = true;
      notifyListeners();
    }).toJS;
    _onTime = ((JSObject _) {
      _position = Duration(milliseconds: (audio.currentTime * 1000).round());
      notifyListeners();
    }).toJS;
    _onEnded = ((JSObject _) {
      _playing = false;
      _position = Duration.zero;
      try {
        audio.currentTime = 0;
      } catch (_) {}
      notifyListeners();
    }).toJS;

    audio.addEventListener('loadedmetadata', _onLoaded);
    audio.addEventListener('timeupdate', _onTime);
    audio.addEventListener('ended', _onEnded);
    _audio = audio;
    notifyListeners();
  }

  @override
  Future<void> toggle() async {
    final web.HTMLAudioElement? audio = _audio;
    if (audio == null) return;
    if (_playing) {
      audio.pause();
      _playing = false;
      notifyListeners();
      return;
    }
    try {
      await audio.play().toDart;
      _playing = true;
    } catch (error) {
      _playing = false;
      notifyListeners();
      throw UnsupportedError('This recording could not be played. ($error)');
    }
    notifyListeners();
  }

  @override
  Future<void> seek(Duration to) async {
    final web.HTMLAudioElement? audio = _audio;
    if (audio == null) return;
    audio.currentTime = to.inMilliseconds / 1000;
    _position = to;
    notifyListeners();
  }

  @override
  Future<void> stop() async {
    final web.HTMLAudioElement? audio = _audio;
    if (audio == null) return;
    audio.pause();
    try {
      audio.currentTime = 0;
    } catch (_) {}
    _playing = false;
    _position = Duration.zero;
    notifyListeners();
  }

  void _disposeElement() {
    final web.HTMLAudioElement? audio = _audio;
    if (audio != null) {
      final JSFunction? loaded = _onLoaded;
      final JSFunction? time = _onTime;
      final JSFunction? ended = _onEnded;
      if (loaded != null) audio.removeEventListener('loadedmetadata', loaded);
      if (time != null) audio.removeEventListener('timeupdate', time);
      if (ended != null) audio.removeEventListener('ended', ended);
      audio.pause();
      audio.src = '';
    }
    _audio = null;
    if (_url.isNotEmpty) revokeObjectUrl(_url);
    _url = '';
    _ready = false;
    _playing = false;
    _position = Duration.zero;
    _duration = Duration.zero;
  }

  @override
  void dispose() {
    _disposeElement();
    super.dispose();
  }
}