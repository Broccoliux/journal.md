import 'package:flutter/material.dart' hide Ink;

import 'app_state.dart';
import 'models.dart';
import 'theme.dart';
import 'ui_common.dart';
import 'voice.dart';
import 'web_io.dart';

/// Attaching files to an entry: picking images and recording voice notes.
///
/// Both paths end in the same place — bytes stored locally plus a markdown
/// reference in the entry body — which is what keeps exports portable.
library;

/// Opens the file chooser, keeps the images and returns their references.
///
/// Returns an empty list when the user cancels, and reports skipped files
/// through [AppState.say] rather than failing silently.
Future<List<MediaRef>> pickImages(AppState state) async {
  final List<PickedFile> picked;
  try {
    picked = await pickFiles(accept: 'image/*', multiple: true);
  } catch (error) {
    state.say('Images cannot be attached here. ($error)');
    return const <MediaRef>[];
  }
  if (picked.isEmpty) return const <MediaRef>[];

  final List<MediaRef> added = <MediaRef>[];
  int rejected = 0;
  for (final PickedFile file in picked) {
    if (!file.mime.startsWith('image/')) {
      rejected++;
      continue;
    }
    final MediaRef? ref = await state.addMedia(
      bytes: file.bytes,
      name: file.name,
      mime: file.mime,
      kind: MediaKind.image,
    );
    if (ref == null) {
      rejected++;
      continue;
    }
    added.add(ref);
  }
  if (rejected > 0) {
    state.say(
      rejected == 1
          ? 'One file was skipped because it is not an image.'
          : '$rejected files were skipped because they are not images.',
    );
  }
  return added;
}

/// Records a voice note in a dialog. Returns null when dismissed.
Future<RecordedClip?> recordVoiceNote(BuildContext context) =>
    showDialog<RecordedClip>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) => const _RecorderDialog(),
    );

class _RecorderDialog extends StatefulWidget {
  const _RecorderDialog();

  @override
  State<_RecorderDialog> createState() => _RecorderDialogState();
}

class _RecorderDialogState extends State<_RecorderDialog> {
  late final VoiceRecorder _recorder = createVoiceRecorder();
  Duration _elapsed = Duration.zero;
  String? _error;
  bool _working = false;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _recorder.ticks.listen((Duration d) {
      if (mounted) setState(() => _elapsed = d);
    });
  }

  @override
  void dispose() {
    _recorder.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      await _recorder.start();
      if (mounted) setState(() => _started = true);
    } on RecordingFailure catch (failure) {
      if (mounted) setState(() => _error = failure.message);
    } catch (error) {
      if (mounted) {
        setState(() => _error = 'The microphone could not be started. ($error)');
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _pauseResume() async {
    if (_recorder.isPaused) {
      await _recorder.resume();
    } else {
      await _recorder.pause();
    }
    if (mounted) setState(() {});
  }

  Future<void> _finish() async {
    setState(() => _working = true);
    try {
      final RecordedClip clip = await _recorder.stop();
      if (mounted) Navigator.of(context).pop(clip);
    } on RecordingFailure catch (failure) {
      if (mounted) {
        setState(() {
          _error = failure.message;
          _started = false;
          _working = false;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = 'The recording could not be saved. ($error)';
          _started = false;
          _working = false;
        });
      }
    }
  }

  Future<void> _discard() async {
    await _recorder.cancel();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final Ink ink = context.ink;
    final bool supported = audioSupported;

    return AlertDialog(
      title: const Text('Voice note'),
      content: SizedBox(
        width: 340,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (!supported)
              const Notice(
                tone: NoticeTone.warning,
                icon: Icons.mic_off_outlined,
                message:
                    'This device has no microphone support, so voice notes '
                    'cannot be recorded here. Everything else still works.',
              )
            else ...<Widget>[
              Text(
                'Recorded in your browser and stored locally. Nothing is '
                'uploaded and nothing is transcribed.',
                style: TextStyle(
                  fontSize: 13,
                  height: 1.55,
                  color: ink.textSoft,
                ),
              ),
              const SizedBox(height: Tokens.s4),
              Row(
                children: <Widget>[
                  _PulseDot(active: _started && !_recorder.isPaused),
                  const SizedBox(width: Tokens.s3),
                  Text(
                    durationLabel(_elapsed.inMilliseconds / 1000),
                    style: TextStyle(
                      fontFamily: AppFonts.mono,
                      fontSize: 26,
                      letterSpacing: 1,
                      color: ink.text,
                    ),
                  ),
                ],
              ),
            ],
            if (_error != null) ...<Widget>[
              const SizedBox(height: Tokens.s4),
              Notice(
                tone: NoticeTone.danger,
                icon: Icons.error_outline_rounded,
                message: _error!,
              ),
            ],
          ],
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(
        Tokens.s4,
        0,
        Tokens.s4,
        Tokens.s3,
      ),
      actions: <Widget>[
        TextButton(
          onPressed: _working ? null : _discard,
          child: Text(_started ? 'Discard' : 'Cancel'),
        ),
        if (supported && _started)
          TextButton(
            onPressed: _working ? null : _pauseResume,
            child: Text(_recorder.isPaused ? 'Resume' : 'Pause'),
          ),
        if (supported && !_started)
          FilledButton(
            onPressed: _working ? null : _start,
            child: const Text('Start recording'),
          )
        else if (supported)
          FilledButton(
            onPressed: _working ? null : _finish,
            child: const Text('Stop and keep'),
          ),
      ],
    );
  }
}

/// A small dot that breathes while recording — and holds still when the
/// platform asks for reduced motion.
class _PulseDot extends StatefulWidget {
  const _PulseDot({required this.active});

  final bool active;

  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
    lowerBound: 0.35,
    upperBound: 1,
    value: 0.35,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(covariant _PulseDot old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    if (widget.active && !context.reducedMotion) {
      if (!_controller.isAnimating) _controller.repeat(reverse: true);
    } else {
      _controller
        ..stop()
        ..value = widget.active ? 1 : 0.35;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Ink ink = context.ink;
    return FadeTransition(
      opacity: _controller,
      child: Container(
        width: 13,
        height: 13,
        decoration: BoxDecoration(
          color: widget.active ? ink.danger : ink.lineStrong,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}