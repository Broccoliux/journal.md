/// Voice notes: a compact audio player for attachments and the recorder UI
/// used inside the entry editor. Uses `just_audio` for playback and `record`
/// (MediaRecorder under the hood on the web) for capture.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:record/record.dart';

import 'format_util.dart';
import 'models.dart';
import 'web_ext.dart';

/// A voice-note player styled like the real thing: a round play button, a
/// waveform you can scrub, and a running duration. The waveform is derived
/// from the clip's own bytes (see [waveformFromBytes]).
class AudioNoteCard extends StatefulWidget {
  const AudioNoteCard({
    super.key,
    required this.attachment,
    required this.bytes,
    this.onDelete,
    this.onInsert,
    this.compact = false,
  });

  final Attachment attachment;
  final Uint8List bytes;
  final VoidCallback? onDelete;
  final VoidCallback? onInsert;
  final bool compact;

  @override
  State<AudioNoteCard> createState() => _AudioNoteCardState();
}

class _AudioNoteCardState extends State<AudioNoteCard> {
  late final AudioPlayer _player = AudioPlayer();
  late final String _url = createBlobUrl(widget.bytes, widget.attachment.mime);
  late final List<double> _bars =
      waveformFromBytes(widget.bytes, barCount: widget.compact ? 32 : 44);
  final List<StreamSubscription<Object?>> _subs = [];

  bool _loaded = false;
  bool _playing = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  String? _error;

  @override
  void initState() {
    super.initState();
    _subs.add(_player.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        // Rewind a finished note so it replays with a single tap.
        _player.pause();
        _player.seek(Duration.zero);
      }
      final playing =
          state.playing && state.processingState != ProcessingState.completed;
      if (mounted && playing != _playing) {
        setState(() => _playing = playing);
      }
    }));
    _subs.add(_player.positionStream.listen((p) {
      if (mounted) setState(() => _position = p);
    }));
    _subs.add(_player.durationStream.listen((d) {
      if (mounted) setState(() => _duration = d ?? Duration.zero);
    }));
    _player.setUrl(_url).then(
      (_) {
        if (mounted) setState(() => _loaded = true);
      },
      onError: (Object e) {
        if (mounted) setState(() => _error = 'Could not load this recording.');
      },
    );
  }

  @override
  void dispose() {
    for (final sub in _subs) {
      sub.cancel();
    }
    _player.dispose();
    revokeBlobUrl(_url);
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_error != null || !_loaded) return;
    if (_playing) {
      await _player.pause();
    } else {
      await _player.play();
    }
  }

  /// Seeks to [fraction] (0..1) of the clip, moving the wipe immediately so
  /// scrubbing feels direct.
  void _scrubTo(double fraction) {
    if (_error != null || _duration.inMilliseconds <= 0) return;
    final target = Duration(
      milliseconds:
          (fraction.clamp(0.0, 1.0) * _duration.inMilliseconds).round(),
    );
    _player.seek(target);
    if (mounted) setState(() => _position = target);
  }

  double get _fraction => _duration.inMilliseconds <= 0
      ? 0.0
      : (_position.inMilliseconds / _duration.inMilliseconds).clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final mono = Theme.of(context).textTheme.bodySmall?.copyWith(
          fontFamily: 'RobotoMono',
          color: scheme.onSurfaceVariant,
          fontSize: widget.compact ? 11 : 11.5,
        );

    return Container(
      padding: EdgeInsets.all(widget.compact ? 8 : 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: scheme.outlineVariant),
        color: scheme.surfaceContainerLow,
      ),
      child: Row(
        children: [
          _playButton(scheme),
          const SizedBox(width: 10),
          Expanded(
            child: _error != null
                ? Text(_error!, style: mono)
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _waveform(scheme),
                      const SizedBox(height: 2),
                      Text(
                        _duration.inMilliseconds == 0
                            ? '—'
                            : '${formatDuration(_position)} / '
                                '${formatDuration(_duration)}',
                        style: mono,
                      ),
                    ],
                  ),
          ),
          if (widget.onInsert != null) ...[
            const SizedBox(width: 4),
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.subdirectory_arrow_right_rounded),
              iconSize: 18,
              tooltip: 'Insert into text',
              onPressed: widget.onInsert,
            ),
          ],
          if (widget.onDelete != null) ...[
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.delete_outline_rounded),
              iconSize: 18,
              tooltip: 'Delete recording',
              onPressed: widget.onDelete,
            ),
          ],
        ],
      ),
    );
  }

  Widget _playButton(ColorScheme scheme) {
    final size = widget.compact ? 34.0 : 38.0;
    return SizedBox(
      width: size,
      height: size,
      child: IconButton.filledTonal(
        padding: EdgeInsets.zero,
        iconSize: widget.compact ? 20 : 22,
        style: IconButton.styleFrom(shape: const CircleBorder()),
        onPressed: _error == null && _loaded ? _toggle : null,
        tooltip: _playing ? 'Pause' : 'Play',
        icon: Icon(_playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
      ),
    );
  }

  Widget _waveform(ColorScheme scheme) {
    return LayoutBuilder(
      builder: (context, constraints) {
        void scrub(Offset local) {
          if (constraints.maxWidth > 0) {
            _scrubTo(local.dx / constraints.maxWidth);
          }
        }

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => scrub(d.localPosition),
          onHorizontalDragStart: (d) => scrub(d.localPosition),
          onHorizontalDragUpdate: (d) => scrub(d.localPosition),
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: SizedBox(
              height: widget.compact ? 24 : 28,
              width: double.infinity,
              child: CustomPaint(
                painter: _WaveformPainter(
                  bars: _bars,
                  progress: _fraction,
                  played: scheme.secondary,
                  remaining: scheme.outlineVariant,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Draws a voice-note waveform: quiet rounded bars with the played portion
/// filled in, wiped left-to-right at [progress].
class _WaveformPainter extends CustomPainter {
  const _WaveformPainter({
    required this.bars,
    required this.progress,
    required this.played,
    required this.remaining,
  });

  final List<double> bars;
  final double progress;
  final Color played;
  final Color remaining;

  static const double _gap = 2;

  @override
  void paint(Canvas canvas, Size size) {
    if (bars.isEmpty || size.width <= 0 || size.height <= 0) return;

    // Drop the oldest bars when the space is too tight for all of them.
    var count = bars.length;
    var barWidth = (size.width - _gap * (count - 1)) / count;
    if (barWidth < 1.5) {
      count = ((size.width + _gap) / (1.5 + _gap)).floor().clamp(1, bars.length);
      barWidth = (size.width - _gap * (count - 1)) / count;
    }
    final firstIndex = bars.length - count;

    void draw(Paint paint) {
      for (var i = 0; i < count; i++) {
        final value = bars[firstIndex + i].clamp(0.0, 1.0);
        final barHeight = (value * size.height).clamp(barWidth, size.height);
        final rect = RRect.fromRectAndRadius(
          Rect.fromLTWH(
            i * (barWidth + _gap),
            (size.height - barHeight) / 2,
            barWidth,
            barHeight,
          ),
          Radius.circular(barWidth / 2),
        );
        canvas.drawRRect(rect, paint);
      }
    }

    draw(Paint()..color = remaining);
    final playedWidth = size.width * progress.clamp(0.0, 1.0);
    if (playedWidth > 0) {
      canvas.save();
      canvas.clipRect(Rect.fromLTWH(0, 0, playedWidth, size.height));
      draw(Paint()..color = played);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_WaveformPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.bars != bars ||
      oldDelegate.played != played ||
      oldDelegate.remaining != remaining;
}

/// Records one voice note at a time and passes the raw bytes to
/// [onRecorded]. Handles permission denial, unsupported browsers and empty
/// recordings by reporting a friendly message via [onError].
class VoiceRecorder extends StatefulWidget {
  const VoiceRecorder({
    super.key,
    required this.onRecorded,
    required this.onError,
  });

  final void Function(Uint8List bytes, String mime, int elapsedMs) onRecorded;
  final void Function(String message) onError;

  @override
  State<VoiceRecorder> createState() => _VoiceRecorderState();
}

class _VoiceRecorderState extends State<VoiceRecorder>
    with SingleTickerProviderStateMixin {
  static const int _levelCount = 30;

  AudioRecorder? _recorder;
  bool _recording = false;
  bool _paused = false;
  final Stopwatch _watch = Stopwatch();
  Timer? _tick;
  StreamSubscription<Amplitude>? _ampSub;

  /// Rolling window of recent microphone levels (0..1) for the live waveform.
  final List<double> _levels = List<double>.filled(_levelCount, 0.12);

  late final AnimationController _pulse =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
        ..repeat(reverse: true);

  @override
  void dispose() {
    _tick?.cancel();
    _stopAmplitude();
    _pulse.dispose();
    _finalizeRecorder();
    super.dispose();
  }

  /// Streams live microphone levels into the recording pill's waveform.
  void _watchAmplitude(AudioRecorder rec) {
    try {
      _ampSub = rec
          .onAmplitudeChanged(const Duration(milliseconds: 120))
          .listen(
        (amp) {
          if (!mounted) return;
          // dBFS → 0..1; anything quieter than about -50 dB is silence.
          final level = ((amp.current + 50) / 50).clamp(0.1, 1.0);
          setState(() {
            _levels
              ..removeAt(0)
              ..add(level);
          });
        },
        onError: (Object _) {},
      );
    } catch (_) {
      // Some browsers don't expose amplitude — the pill just stays quiet.
    }
  }

  void _stopAmplitude() {
    _ampSub?.cancel();
    _ampSub = null;
  }

  Future<void> _finalizeRecorder() async {
    final rec = _recorder;
    _recorder = null;
    if (rec == null) return;
    try {
      if (await rec.isRecording()) await rec.stop();
    } catch (_) {}
    await rec.dispose();
  }

  Future<void> _start() async {
    try {
      if (!microphoneSupported()) {
        widget.onError(
            'Voice notes need a browser with microphone support (Chrome, Edge or Firefox).');
        return;
      }
      _recorder ??= AudioRecorder();
      final rec = _recorder!;
      if (!await rec.hasPermission()) {
        widget.onError('Microphone permission was denied.');
        return;
      }
      final encoder = await rec.isEncoderSupported(AudioEncoder.opus)
          ? AudioEncoder.opus
          : AudioEncoder.aacLc;
      await rec.start(
        RecordConfig(
          encoder: encoder,
          bitRate: 96000,
          sampleRate: 48000,
          numChannels: 1,
        ),
        path: '', // ignored on the web
      );
      if (!await rec.isRecording()) {
        widget.onError('Recording could not be started.');
        return;
      }
      _watch
        ..reset()
        ..start();
      setState(() {
        _recording = true;
        _paused = false;
      });
      _levels.fillRange(0, _levelCount, 0.12);
      _watchAmplitude(rec);
      _tick = Timer.periodic(const Duration(milliseconds: 200), (_) {
        if (mounted) setState(() {});
      });
    } catch (e) {
      await _finalizeRecorder();
      widget.onError('Recording failed: $e');
    }
  }

  Future<void> _togglePause() async {
    final rec = _recorder;
    if (rec == null) return;
    try {
      if (_paused) {
        await rec.resume();
        _watch.start();
      } else {
        await rec.pause();
        _watch.stop();
      }
      setState(() => _paused = !_paused);
    } catch (_) {}
  }

  Future<void> _stop() async {
    final rec = _recorder;
    _tick?.cancel();
    _stopAmplitude();
    if (rec == null) return;
    _watch.stop();
    final elapsed = _watch.elapsedMilliseconds;
    setState(() => _recording = false);
    try {
      final url = await rec.stop();
      await rec.dispose();
      _recorder = null;
      if (url == null) {
        widget.onError('No audio was captured.');
        return;
      }
      final bytes = await fetchBlobBytes(url);
      revokeBlobUrl(url);
      if (bytes == null || bytes.isEmpty) {
        widget.onError('The recording could not be saved.');
        return;
      }
      if (elapsed < 400 || bytes.length < 512) {
        widget.onError('The recording was empty — hold record a little longer.');
        return;
      }
      widget.onRecorded(bytes, sniffAudioMime(bytes), elapsed);
    } catch (e) {
      widget.onError('Recording failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final reduced = MediaQuery.disableAnimationsOf(context);

    if (!_recording) {
      return OutlinedButton.icon(
        onPressed: _start,
        icon: const Icon(Icons.mic_none_rounded, size: 18),
        label: const Text('Record voice note'),
        style: OutlinedButton.styleFrom(
          visualDensity: VisualDensity.compact,
          foregroundColor: scheme.secondary,
          side: BorderSide(color: scheme.outline),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.outline),
        color: scheme.surfaceContainerLow,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FadeTransition(
            opacity: reduced
                ? const AlwaysStoppedAnimation(1.0)
                : Tween(begin: 0.35, end: 1.0).animate(_pulse),
            child: Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: scheme.error,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            _paused
                ? '${formatDuration(_watch.elapsed)} · paused'
                : formatDuration(_watch.elapsed),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontFamily: 'RobotoMono',
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: SizedBox(
              width: 120,
              height: 22,
              child: CustomPaint(
                painter: _WaveformPainter(
                  bars: _levels,
                  progress: 1,
                  played: scheme.secondary,
                  remaining: scheme.secondary,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: _paused ? 'Resume' : 'Pause',
            onPressed: _togglePause,
            icon: Icon(
              _paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
              size: 20,
            ),
          ),
          FilledButton(
            onPressed: _stop,
            style: FilledButton.styleFrom(
              visualDensity: VisualDensity.compact,
              backgroundColor: scheme.primary,
              foregroundColor: scheme.onPrimary,
            ),
            child: const Text('Stop'),
          ),
        ],
      ),
    );
  }
}
