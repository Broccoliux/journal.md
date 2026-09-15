import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart' hide Ink;

import 'models.dart';
import 'theme.dart';
import 'voice.dart';

/// Media presentation: images, missing files, voice notes and the recorder.
///
/// All of it is local. Bytes come from the app's storage cache, and anything
/// that cannot be resolved degrades into a readable placeholder rather than a
/// broken box.


/// A stored image, with graceful states for loading, missing and corrupt data.
class MediaImage extends StatelessWidget {
  const MediaImage({
    super.key,
    required this.path,
    required this.bytes,
    this.onTap,
    this.radius = Tokens.rMd,
    this.fit = BoxFit.cover,
    this.heroTag,
    this.maxHeight,
    this.alignment = Alignment.center,
  });

  final String path;
  final Future<Uint8List?> bytes;
  final VoidCallback? onTap;
  final double radius;
  final BoxFit fit;

  /// Set only where the tag is guaranteed unique on screen. Inline images in
  /// Markdown leave it null, because two references to one file would share a
  /// tag and Flutter rejects that.
  final String? heroTag;
  final double? maxHeight;

  /// Where the picture sits inside its frame.
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    final Ink ink = context.ink;
    final Widget frame = ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: ink.surfaceSunken,
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: ink.line),
        ),
        child: FutureBuilder<Uint8List?>(
          future: bytes,
          builder: (BuildContext context, AsyncSnapshot<Uint8List?> snap) {
            if (snap.connectionState != ConnectionState.done) {
              return _ImageSkeleton(height: maxHeight ?? 160);
            }
            final Uint8List? data = snap.data;
            if (data == null || data.isEmpty) {
              return MissingFileTile(path: path, onTap: onTap);
            }
            return ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: maxHeight ?? double.infinity,
              ),
              child: Image.memory(
                data,
                fit: fit,
                width: double.infinity,
                alignment: alignment,
                filterQuality: FilterQuality.medium,
                gaplessPlayback: true,
                errorBuilder: (_, _, _) => UnreadableFileTile(path: path),
              ),
            );
          },
        ),
      ),
    );

    final Widget tappable = onTap == null
        ? frame
        : MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: onTap,
              behavior: HitTestBehavior.opaque,
              child: Semantics(
                button: true,
                label: 'Open image $path',
                child: frame,
              ),
            ),
          );

    return heroTag == null ? tappable : Hero(tag: heroTag!, child: tappable);
  }
}

class _ImageSkeleton extends StatelessWidget {
  const _ImageSkeleton({required this.height});

  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: Center(
        child: SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(
            strokeWidth: 1.4,
            color: context.ink.textFaint,
          ),
        ),
      ),
    );
  }
}

/// A reference whose file is not in storage any more.
class MissingFileTile extends StatelessWidget {
  const MissingFileTile({super.key, required this.path, this.onTap});

  final String path;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final Ink ink = context.ink;
    return Semantics(
      label: 'Missing file $path',
      child: Padding(
        padding: const EdgeInsets.all(Tokens.s3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.image_not_supported_outlined, size: 18, color: ink.textFaint),
            const SizedBox(width: Tokens.s2),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    'File not found',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: ink.textSoft,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    path,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: AppFonts.mono,
                      fontSize: 11,
                      color: ink.textFaint,
                    ),
                  ),
                ],
              ),
            ),
            if (onTap != null)
              TextButton(onPressed: onTap, child: const Text('Remove')),
          ],
        ),
      ),
    );
  }
}

/// A file that exists but cannot be decoded.
class UnreadableFileTile extends StatelessWidget {
  const UnreadableFileTile({super.key, required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    final Ink ink = context.ink;
    return Padding(
      padding: const EdgeInsets.all(Tokens.s3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(Icons.broken_image_outlined, size: 18, color: ink.textFaint),
          const SizedBox(width: Tokens.s2),
          Expanded(
            child: Text(
              'This file could not be displayed',
              style: TextStyle(fontSize: 12.5, color: ink.textSoft),
            ),
          ),
        ],
      ),
    );
  }
}

/// Full-screen view of one image, opened by tapping a thumbnail.
Future<void> showImageLightbox(
  BuildContext context, {
  required MediaRef ref,
  required Future<Uint8List?> bytes,
  String? heroTag,
}) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close image',
    barrierColor: Colors.black.withValues(alpha: 0.86),
    transitionDuration: context.motion(const Duration(milliseconds: 240)),
    pageBuilder: (BuildContext context, _, _) =>
        _Lightbox(ref: ref, bytes: bytes, heroTag: heroTag),
    transitionBuilder:
        (
          BuildContext context,
          Animation<double> anim,
          _,
          Widget child,
        ) {
          final Animation<double> curved = CurvedAnimation(
            parent: anim,
            curve: Curves.easeOutCubic,
          );
          return FadeTransition(
            opacity: curved,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.96, end: 1).animate(curved),
              child: child,
            ),
          );
        },
  );
}

class _Lightbox extends StatelessWidget {
  const _Lightbox({required this.ref, required this.bytes, this.heroTag});

  final MediaRef ref;
  final Future<Uint8List?> bytes;
  final String? heroTag;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: <Widget>[
          Positioned.fill(
            child: GestureDetector(
              onTap: () => Navigator.of(context).maybePop(),
              behavior: HitTestBehavior.opaque,
              child: Center(
                child: FutureBuilder<Uint8List?>(
                  future: bytes,
                  builder: (_, AsyncSnapshot<Uint8List?> snap) {
                    if (snap.connectionState != ConnectionState.done) {
                      return const CircularProgressIndicator(
                        strokeWidth: 1.6,
                        color: Colors.white70,
                      );
                    }
                    final Uint8List? data = snap.data;
                    if (data == null || data.isEmpty) {
                      return const _OnDarkNotice(
                        message: 'This file is missing from local storage.',
                      );
                    }
                    final Widget image = InteractiveViewer(
                      maxScale: 5,
                      child: Image.memory(
                        data,
                        fit: BoxFit.contain,
                        errorBuilder: (_, _, _) => const _OnDarkNotice(
                          message: 'This image could not be displayed.',
                        ),
                      ),
                    );
                    final String? tag = heroTag;
                    return tag == null
                        ? image
                        : Hero(tag: tag, child: image);
                  },
                ),
              ),
            ),
          ),
          Positioned(
            top: Tokens.s4,
            right: Tokens.s4,
            child: IconButton(
              tooltip: 'Close',
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const Icon(Icons.close_rounded),
              color: Colors.white,
              style: IconButton.styleFrom(
                backgroundColor: Colors.black.withValues(alpha: 0.35),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: Tokens.s5,
            child: Center(
              child: Text(
                ref.name,
                style: const TextStyle(
                  color: Colors.white70,
                  fontFamily: AppFonts.mono,
                  fontSize: 12,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OnDarkNotice extends StatelessWidget {
  const _OnDarkNotice({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(Tokens.s6),
    child: Text(
      message,
      textAlign: TextAlign.center,
      style: const TextStyle(color: Colors.white70, fontSize: 14),
    ),
  );
}

/// An inline voice note: play, pause, scrub and (optionally) delete.
class VoiceClip extends StatefulWidget {
  const VoiceClip({
    super.key,
    required this.ref,
    required this.bytes,
    this.onDelete,
  });

  final MediaRef ref;
  final Future<Uint8List?> bytes;
  final Future<void> Function()? onDelete;

  @override
  State<VoiceClip> createState() => _VoiceClipState();
}

class _VoiceClipState extends State<VoiceClip> {
  final VoicePlayer _player = createVoicePlayer();
  String? _problem;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _player.addListener(_onChanged);
    unawaited(_prepare());
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _prepare() async {
    try {
      final Uint8List? data = await widget.bytes;
      if (!mounted) return;
      if (data == null || data.isEmpty) {
        setState(() {
          _loading = false;
          _problem = 'This recording is missing from local storage.';
        });
        return;
      }
      await _player.load(data, widget.ref.mime);
      if (!mounted) return;
      setState(() => _loading = false);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _problem = 'This recording could not be played. ($error)';
      });
    }
  }

  Future<void> _toggle() async {
    try {
      await _player.toggle();
    } catch (error) {
      if (!mounted) return;
      setState(() => _problem = '$error');
    }
  }

  Duration get _total => _player.duration > Duration.zero
      ? _player.duration
      : Duration(milliseconds: (widget.ref.duration * 1000).round());

  @override
  void dispose() {
    _player.removeListener(_onChanged);
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Ink ink = context.ink;
    final String? problem = _problem;
    if (problem != null) {
      return Container(
        padding: const EdgeInsets.all(Tokens.s3),
        decoration: BoxDecoration(
          color: ink.surfaceSunken,
          borderRadius: BorderRadius.circular(Tokens.rMd),
          border: Border.all(color: ink.line),
        ),
        child: Row(
          children: <Widget>[
            Icon(Icons.mic_off_outlined, size: 18, color: ink.textFaint),
            const SizedBox(width: Tokens.s2),
            Expanded(
              child: Text(
                problem,
                style: TextStyle(fontSize: 12.5, color: ink.textSoft),
              ),
            ),
          ],
        ),
      );
    }

    return Semantics(
      label: 'Voice note ${widget.ref.name}',
      child: Container(
        padding: const EdgeInsets.all(Tokens.s2),
        decoration: BoxDecoration(
          color: ink.surfaceSunken,
          borderRadius: BorderRadius.circular(Tokens.rMd),
          border: Border.all(color: ink.line),
        ),
        child: Row(
          children: <Widget>[
            _RoundControl(
              busy: _loading,
              playing: _player.playing,
              enabled: _player.ready,
              onPressed: _toggle,
            ),
            const SizedBox(width: Tokens.s3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    widget.ref.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: ink.text,
                    ),
                  ),
                  const SizedBox(height: 6),
                  _Scrubber(
                    position: _player.position,
                    total: _total,
                    onSeek: (Duration to) => unawaited(_player.seek(to)),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${durationLabel(_player.position.inMilliseconds / 1000)}'
                    ' / ${durationLabel(_total.inMilliseconds / 1000)}',
                    style: TextStyle(
                      fontFamily: AppFonts.mono,
                      fontSize: 10.5,
                      color: ink.textFaint,
                    ),
                  ),
                ],
              ),
            ),
            if (widget.onDelete != null)
              IconButton(
                tooltip: 'Delete recording',
                onPressed: () => unawaited(widget.onDelete!()),
                icon: const Icon(Icons.delete_outline_rounded, size: 18),
                color: ink.textSoft,
              ),
          ],
        ),
      ),
    );
  }
}

/// A thin, draggable progress line.
class _Scrubber extends StatelessWidget {
  const _Scrubber({
    required this.position,
    required this.total,
    required this.onSeek,
  });

  final Duration position;
  final Duration total;
  final ValueChanged<Duration> onSeek;

  @override
  Widget build(BuildContext context) {
    final Ink ink = context.ink;
    final double progress = total.inMilliseconds == 0
        ? 0
        : (position.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        void seekAt(double dx) {
          if (total.inMilliseconds == 0 || constraints.maxWidth <= 0) return;
          final double ratio = (dx / constraints.maxWidth).clamp(0.0, 1.0);
          onSeek(
            Duration(milliseconds: (total.inMilliseconds * ratio).round()),
          );
        }

        return MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (TapDownDetails d) => seekAt(d.localPosition.dx),
            onHorizontalDragUpdate: (DragUpdateDetails d) =>
                seekAt(d.localPosition.dx),
            child: SizedBox(
              height: 16,
              child: Center(
                child: Stack(
                  children: <Widget>[
                    Container(
                      height: 3,
                      decoration: BoxDecoration(
                        color: ink.line,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    FractionallySizedBox(
                      widthFactor: progress,
                      child: Container(
                        height: 3,
                        decoration: BoxDecoration(
                          color: ink.accent,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Round play/pause control used by voice notes and the recorder.
class _RoundControl extends StatelessWidget {
  const _RoundControl({
    required this.playing,
    required this.busy,
    required this.enabled,
    required this.onPressed,
  });

  final bool playing;
  final bool busy;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final Ink ink = context.ink;
    return Semantics(
      button: true,
      label: playing ? 'Pause voice note' : 'Play voice note',
      child: Tooltip(
        message: playing ? 'Pause' : 'Play',
        child: SizedBox(
          width: 38,
          height: 38,
          child: Material(
            color: enabled || busy ? ink.accent : ink.line,
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: enabled ? onPressed : null,
              child: Center(
                child: busy
                    ? SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.6,
                          color: ink.accentInk,
                        ),
                      )
                    : Icon(
                        playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                        size: 20,
                        color: enabled ? ink.accentInk : ink.textFaint,
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}