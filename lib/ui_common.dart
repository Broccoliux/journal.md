import 'package:flutter/material.dart' hide Ink;

import 'theme.dart';

/// Shared, small UI pieces. Everything here is used by more than one screen;
/// nothing here wraps a single control.


/// A tactile panel: hairline border, gentle radius, no heavy shadow.
class Panel extends StatelessWidget {
  const Panel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(Tokens.s4),
    this.radius = Tokens.rLg,
    this.raised = false,
    this.color,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;

  /// Slightly lighter surface, for hovered or selected states.
  final bool raised;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final Ink ink = context.ink;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color ?? (raised ? ink.surfaceRaised : ink.surface),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: raised ? ink.lineStrong : ink.line),
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

/// Small mono label used to head a group of content.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.trailing, this.padding});

  final String text;
  final Widget? trailing;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final Ink ink = context.ink;
    return Padding(
      padding: padding ?? const EdgeInsets.only(bottom: Tokens.s3),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              text.toUpperCase(),
              style: TextStyle(
                fontFamily: AppFonts.mono,
                fontSize: 10.5,
                letterSpacing: 1.6,
                fontWeight: FontWeight.w600,
                color: ink.textFaint,
              ),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// A tag, exactly as written: `#ai`.
class TagPill extends StatelessWidget {
  const TagPill({
    super.key,
    required this.tag,
    this.onTap,
    this.selected = false,
    this.onRemove,
    this.dense = false,
  });

  final String tag;
  final VoidCallback? onTap;
  final bool selected;
  final VoidCallback? onRemove;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final Ink ink = context.ink;
    final Color text = selected ? ink.accent : ink.textSoft;

    final Widget body = Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 7 : 9,
        vertical: dense ? 2.5 : 4,
      ),
      decoration: BoxDecoration(
        color: selected ? ink.accentWash : ink.surfaceSunken,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: selected ? ink.accent : ink.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            '#$tag',
            style: TextStyle(
              fontFamily: AppFonts.mono,
              fontSize: dense ? 10.5 : 11.5,
              letterSpacing: 0.2,
              color: text,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
          if (onRemove != null) ...<Widget>[
            const SizedBox(width: 4),
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: onRemove,
                child: Icon(
                  Icons.close_rounded,
                  size: dense ? 11 : 13,
                  color: text,
                ),
              ),
            ),
          ],
        ],
      ),
    );

    if (onTap == null) return body;
    return Semantics(
      button: true,
      selected: selected,
      label: 'Filter by tag $tag',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: body,
        ),
      ),
    );
  }
}
/// A quiet notice strip, for warnings that should not be modal.
class Notice extends StatelessWidget {
  const Notice({
    super.key,
    required this.message,
    this.icon = Icons.info_outline_rounded,
    this.tone = NoticeTone.neutral,
    this.action,
  });

  final String message;
  final IconData icon;
  final NoticeTone tone;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final Ink ink = context.ink;
    final Color accent = switch (tone) {
      NoticeTone.neutral => ink.textSoft,
      NoticeTone.warning => ink.brass,
      NoticeTone.danger => ink.danger,
    };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(Tokens.s3),
      decoration: BoxDecoration(
        color: ink.surface,
        borderRadius: BorderRadius.circular(Tokens.rMd),
        border: Border.all(color: accent.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, size: 17, color: accent),
          const SizedBox(width: Tokens.s2),
          Expanded(
            child: Text(
              message,
              style: TextStyle(fontSize: 13, height: 1.5, color: ink.textSoft),
            ),
          ),
          if (action != null) ...<Widget>[
            const SizedBox(width: Tokens.s2),
            action!,
          ],
        ],
      ),
    );
  }
}

enum NoticeTone { neutral, warning, danger }

/// Asks before doing something irreversible. Returns true when confirmed.
Future<bool> confirm(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Confirm',
  String cancelLabel = 'Cancel',
  bool destructive = false,
}) async {
  final Ink ink = context.ink;
  final bool dark = context.isDark;
  final bool? answer = await showDialog<bool>(
    context: context,
    builder: (BuildContext context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actionsPadding: const EdgeInsets.fromLTRB(
        Tokens.s4,
        0,
        Tokens.s4,
        Tokens.s3,
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(cancelLabel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: destructive
              ? ButtonStyle(
                  backgroundColor: WidgetStatePropertyAll<Color>(ink.danger),
                  foregroundColor: WidgetStatePropertyAll<Color>(
                    dark ? const Color(0xFF2A0A08) : Colors.white,
                  ),
                )
              : null,
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return answer ?? false;
}

/// Paints the words of [query] inside [text] with an accent wash.
class HighlightedText extends StatelessWidget {
  const HighlightedText({
    super.key,
    required this.text,
    required this.query,
    this.style,
    this.maxLines,
  });

  final String text;
  final String query;
  final TextStyle? style;
  final int? maxLines;

  @override
  Widget build(BuildContext context) {
    final Ink ink = context.ink;
    final TextStyle base = style ?? DefaultTextStyle.of(context).style;
    final List<String> words = <String>[
      for (final String word in query.trim().split(RegExp(r'\s+')))
        if (word.replaceAll('#', '').length > 1)
          word.replaceAll(RegExp(r'^#'), ''),
    ];
    if (words.isEmpty) {
      return Text(
        text,
        style: base,
        maxLines: maxLines,
        overflow: maxLines == null ? null : TextOverflow.ellipsis,
      );
    }

    final RegExp pattern = RegExp(
      '(${words.map(RegExp.escape).join('|')})',
      caseSensitive: false,
    );
    final List<TextSpan> spans = <TextSpan>[];
    int last = 0;
    for (final RegExpMatch m in pattern.allMatches(text)) {
      if (m.start > last) {
        spans.add(TextSpan(text: text.substring(last, m.start)));
      }
      spans.add(
        TextSpan(
          text: text.substring(m.start, m.end),
          style: TextStyle(
            color: ink.accent,
            fontWeight: FontWeight.w700,
            backgroundColor: ink.accentWash,
          ),
        ),
      );
      last = m.end;
    }
    if (last < text.length) {
      spans.add(TextSpan(text: text.substring(last)));
    }
    return Text.rich(
      TextSpan(style: base, children: spans),
      maxLines: maxLines,
      overflow: maxLines == null ? TextOverflow.clip : TextOverflow.ellipsis,
    );
  }
}

/// Fades and lifts its child into place once, with an optional delay so lists
/// arrive in sequence. Reduced motion shows content immediately.
class AppearIn extends StatefulWidget {
  const AppearIn({
    super.key,
    required this.child,
    this.order = 0,
    this.offset = 10,
  });

  final Widget child;
  final int order;
  final double offset;

  @override
  State<AppearIn> createState() => _AppearInState();
}

class _AppearInState extends State<AppearIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (context.reducedMotion) {
      _controller.value = 1;
      return;
    }
    final int capped = widget.order.clamp(0, 8);
    Future<void>.delayed(Duration(milliseconds: 40 * capped), () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Animation<double> curved = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );
    return AnimatedBuilder(
      animation: curved,
      builder: (BuildContext context, Widget? child) => Opacity(
        opacity: curved.value,
        child: Transform.translate(
          offset: Offset(0, widget.offset * (1 - curved.value)),
          child: child,
        ),
      ),
      child: widget.child,
    );
  }
}

/// Animates a swap between panes: fade plus a short horizontal settle.
class PaneSwitch extends StatelessWidget {
  const PaneSwitch({super.key, required this.child, required this.duration});

  final Widget child;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    if (context.reducedMotion) return child;
    return AnimatedSwitcher(
      duration: duration,
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (Widget child, Animation<double> anim) {
        return FadeTransition(
          opacity: anim,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0.012, 0),
              end: Offset.zero,
            ).animate(anim),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}

/// A beautiful, specific empty state. Every screen that can be empty uses it.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.title,
    required this.message,
    this.glyph,
    this.icon,
    this.actions = const <Widget>[],
    this.compact = false,
  });

  final String title;
  final String message;

  /// A large character rendered in the serif face, instead of clip art.
  final String? glyph;
  final IconData? icon;
  final List<Widget> actions;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final Ink ink = context.ink;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 430),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: Tokens.s5,
            vertical: compact ? Tokens.s5 : Tokens.s7,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (glyph != null)
                Text(
                  glyph!,
                  style: TextStyle(
                    fontFamily: AppFonts.serif,
                    fontSize: compact ? 40 : 54,
                    height: 1,
                    color: ink.lineStrong,
                  ),
                )
              else if (icon != null)
                Icon(icon, size: compact ? 30 : 38, color: ink.lineStrong),
              SizedBox(height: compact ? Tokens.s3 : Tokens.s4),
              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: AppFonts.serif,
                  fontSize: compact ? 19 : 22,
                  height: 1.25,
                  letterSpacing: -0.2,
                  fontWeight: FontWeight.w600,
                  color: ink.text,
                ),
              ),
              const SizedBox(height: Tokens.s2),
              Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13.5,
                  height: 1.6,
                  color: ink.textSoft,
                ),
              ),
              if (actions.isNotEmpty) ...<Widget>[
                const SizedBox(height: Tokens.s5),
                Wrap(
                  spacing: Tokens.s2,
                  runSpacing: Tokens.s2,
                  alignment: WrapAlignment.center,
                  children: actions,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}