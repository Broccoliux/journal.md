import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart' hide Ink;
import 'package:flutter/services.dart';
import 'package:markdown/markdown.dart' as md;

import 'code_highlight.dart';
import 'models.dart';
import 'theme.dart';
import 'ui_common.dart';
import 'ui_media.dart';
import 'web_io.dart';

/// Renders entry Markdown.
///
/// Written by hand over the `markdown` package's syntax tree rather than a
/// ready-made renderer, because the presentation carries the product: prose
/// sits in a readable serif-scale hierarchy, code sits in a real code card with
/// highlighting and a copy button, and `assets/…` references resolve to files
/// stored locally — including voice notes, which appear as players.
class MarkdownView extends StatelessWidget {
  const MarkdownView({
    super.key,
    required this.source,
    required this.mediaOf,
    required this.bytesFor,
    this.onOpenImage,
    this.onOpenLink,
    this.compact = false,
  });

  final String source;

  /// Resolves an `assets/…` path to its metadata, or null when unknown.
  final MediaRef? Function(String path) mediaOf;

  /// Loads the bytes for an `assets/…` path.
  final Future<Uint8List?> Function(String path) bytesFor;

  final void Function(MediaRef ref)? onOpenImage;
  final void Function(String url)? onOpenLink;

  /// Tighter rhythm, for previews inside lists and cards.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final Ink ink = context.ink;
    final _Renderer renderer = _Renderer(
      context: context,
      mediaOf: mediaOf,
      bytesFor: bytesFor,
      onOpenImage: onOpenImage,
      onOpenLink: onOpenLink,
      ink: ink,
      compact: compact,
    );

    final List<md.Node> nodes;
    try {
      nodes = md.Document(
        extensionSet: md.ExtensionSet.gitHubFlavored,
        encodeHtml: false,
      ).parseLines(const LineSplitter().convert(source));
    } catch (_) {
      // Unparseable markdown is shown as written rather than hidden.
      return SelectableText(
        source,
        style: renderer.body,
      );
    }

    final List<Widget> blocks = renderer.blocks(nodes);
    if (blocks.isEmpty) {
      return Text(
        'Nothing written yet.',
        style: TextStyle(
          fontFamily: AppFonts.serif,
          fontSize: 17,
          fontStyle: FontStyle.italic,
          color: ink.textFaint,
        ),
      );
    }
    return SelectionArea(child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: blocks,
    ));
  }
}

/// Holds the styling and lookups for one render pass.
class _Renderer {
  _Renderer({
    required this.context,
    required this.mediaOf,
    required this.bytesFor,
    required this.onOpenImage,
    required this.onOpenLink,
    required this.ink,
    required this.compact,
  });

  /// Used for lightboxes and copy confirmations opened from inside markdown.
  final BuildContext context;
  final MediaRef? Function(String path) mediaOf;
  final Future<Uint8List?> Function(String path) bytesFor;
  final void Function(MediaRef ref)? onOpenImage;
  final void Function(String url)? onOpenLink;
  final Ink ink;
  final bool compact;

  double get _scale => compact ? 0.92 : 1;

  TextStyle get body => TextStyle(
    fontFamily: AppFonts.sans,
    fontSize: 15.5 * _scale,
    height: 1.72,
    color: ink.text,
    letterSpacing: 0.05,
  );

  TextStyle get _monoInline => TextStyle(
    fontFamily: AppFonts.mono,
    fontSize: 13 * _scale,
    height: 1.4,
    color: ink.text,
  );

  TextStyle get _quoteBody => TextStyle(
    fontFamily: AppFonts.serif,
    fontSize: 17 * _scale,
    height: 1.66,
    fontStyle: FontStyle.italic,
    color: ink.textSoft,
  );

  /// Builds every top level block, separated by rhythm rather than margins on
  /// each block, so nested structures stay tight.
  List<Widget> blocks(List<md.Node> nodes) {
    final List<Widget> out = <Widget>[];
    final List<md.Node> visible = <md.Node>[
      for (final md.Node n in nodes)
        if (!(n is md.Text && n.text.trim().isEmpty)) n,
    ];
    for (int i = 0; i < visible.length; i++) {
      final md.Node node = visible[i];
      final Widget widget = block(node, _Level(body));
      out.add(widget);
      if (i < visible.length - 1) {
        out.add(SizedBox(height: _gapAfter(node)));
      }
    }
    return out;
  }

  double _gapAfter(md.Node node) {
    if (node is! md.Element) return 12 * _scale;
    return switch (node.tag) {
      'h1' => 18 * _scale,
      'h2' => 18 * _scale,
      'h3' || 'h4' || 'h5' || 'h6' => 14 * _scale,
      'pre' => 18 * _scale,
      'hr' => 20 * _scale,
      'table' => 18 * _scale,
      'blockquote' => 18 * _scale,
      'ul' || 'ol' => 16 * _scale,
      _ => 15 * _scale,
    };
  }

  Widget block(md.Node node, _Level level) {
    if (node is md.Text) {
      final String text = node.text.trim();
      if (text.isEmpty) return const SizedBox.shrink();
      return Text(text, style: level.body);
    }
    if (node is! md.Element) return const SizedBox.shrink();

    return switch (node.tag) {
      'h1' => _heading(node, level, 1),
      'h2' => _heading(node, level, 2),
      'h3' => _heading(node, level, 3),
      'h4' => _heading(node, level, 4),
      'h5' => _heading(node, level, 5),
      'h6' => _heading(node, level, 6),
      'p' => _paragraph(node, level),
      'ul' || 'ol' => _list(node, level, 0),
      'blockquote' => _quote(node, level),
      'pre' => _code(node),
      'hr' => _rule(),
      'table' => _table(node, level),
      'img' => _imageBlock(node, 260),
      'li' => _paragraph(node, level),
      _ => _paragraph(node, level),
    };
  }

  // -------------------------------------------------------------- headings

  Widget _heading(md.Element el, _Level level, int rank) {
    final TextStyle style = switch (rank) {
      1 => TextStyle(
        fontFamily: AppFonts.serif,
        fontSize: 30 * _scale,
        height: 1.2,
        letterSpacing: -0.6,
        fontWeight: FontWeight.w600,
        color: ink.text,
      ),
      2 => TextStyle(
        fontFamily: AppFonts.serif,
        fontSize: 23 * _scale,
        height: 1.26,
        letterSpacing: -0.4,
        fontWeight: FontWeight.w600,
        color: ink.text,
      ),
      3 => TextStyle(
        fontFamily: AppFonts.sans,
        fontSize: 17.5 * _scale,
        height: 1.35,
        letterSpacing: -0.1,
        fontWeight: FontWeight.w600,
        color: ink.text,
      ),
      4 => TextStyle(
        fontFamily: AppFonts.sans,
        fontSize: 15.5 * _scale,
        height: 1.4,
        fontWeight: FontWeight.w600,
        color: ink.text,
      ),
      5 => TextStyle(
        fontFamily: AppFonts.sans,
        fontSize: 12.5 * _scale,
        height: 1.4,
        letterSpacing: 1.2,
        fontWeight: FontWeight.w700,
        color: ink.textSoft,
      ),
      _ => TextStyle(
        fontFamily: AppFonts.mono,
        fontSize: 12 * _scale,
        height: 1.4,
        letterSpacing: 1,
        fontWeight: FontWeight.w600,
        color: ink.textFaint,
      ),
    };

    final Widget text = Text.rich(
      TextSpan(
        style: style,
        children: _inline(el.children, level, base: style),
      ),
    );

    // Only the second level gets a rule under it: enough structure to scan by,
    // not so much that the page looks like a form.
    if (rank != 2) return text;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        text,
        const SizedBox(height: 10),
        Container(height: 1, color: ink.line),
      ],
    );
  }

  // ------------------------------------------------------------ paragraphs

  Widget _paragraph(md.Element el, _Level level) {
    final List<md.Element> images = <md.Element>[
      for (final md.Node child in el.children)
        if (child is md.Element && child.tag == 'img') child,
    ];
    final bool onlyMedia =
        images.length == 1 &&
        el.children
            .where((md.Node n) => !(n is md.Text && n.text.trim().isEmpty))
            .every((md.Node n) => n is md.Element && n.tag == 'img');

    if (onlyMedia) return _imageBlock(images.first, 420);

    return Text.rich(
      TextSpan(
        style: level.body,
        children: _inline(el.children, level, base: level.body),
      ),
    );
  }

  List<InlineSpan> _inline(
    List<md.Node> nodes,
    _Level level, {
    required TextStyle base,
  }) {
    final List<InlineSpan> out = <InlineSpan>[];
    for (final md.Node node in nodes) {
      if (node is md.Text) {
        if (node.text.isEmpty) continue;
        out.add(TextSpan(text: node.text));
        continue;
      }
      if (node is! md.Element) continue;

      switch (node.tag) {
        case 'br':
          out.add(const TextSpan(text: '\n'));
        case 'em':
          final TextStyle s = base.copyWith(fontStyle: FontStyle.italic);
          out.add(
            TextSpan(style: s, children: _inline(node.children, level, base: s)),
          );
        case 'strong':
          final TextStyle s = base.copyWith(
            fontWeight: FontWeight.w700,
            color: ink.text,
          );
          out.add(
            TextSpan(style: s, children: _inline(node.children, level, base: s)),
          );
        case 'del':
          final TextStyle s = base.copyWith(
            decoration: TextDecoration.lineThrough,
            color: ink.textFaint,
          );
          out.add(
            TextSpan(style: s, children: _inline(node.children, level, base: s)),
          );
        case 'code':
          out.add(_inlineCode(node.textContent));
        case 'a':
          out.add(_link(node, level, base));
        case 'img':
          out.add(
            _mediaInline(
              src: node.attributes['src'] ?? '',
              alt: node.attributes['alt'] ?? '',
            ),
          );
        default:
          out.add(TextSpan(children: _inline(node.children, level, base: base)));
      }
    }
    return out;
  }

  InlineSpan _inlineCode(String text) {
    return WidgetSpan(
      alignment: PlaceholderAlignment.baseline,
      baseline: TextBaseline.alphabetic,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 1.5),
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
        decoration: BoxDecoration(
          color: ink.surfaceSunken,
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: ink.line),
        ),
        child: Text(text, style: _monoInline),
      ),
    );
  }

  /// An inline picture. Falls back to a labelled chip when the file is gone.
  InlineSpan _mediaInline({
    required String src,
    required String alt,
    double maxWidth = 340,
    double maxHeight = 220,
  }) {
    final String path = _resolve(src);
    final MediaRef? ref = mediaOf(path);
    if (ref == null) {
      return WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 4),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: ink.surfaceSunken,
            borderRadius: BorderRadius.circular(Tokens.rSm),
            border: Border.all(color: ink.line),
          ),
          child: Text(
            alt.isEmpty ? 'image missing' : alt,
            style: TextStyle(
              fontFamily: AppFonts.mono,
              fontSize: 11.5,
              color: ink.textFaint,
            ),
          ),
        ),
      );
    }
    return WidgetSpan(
      alignment: PlaceholderAlignment.middle,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: maxWidth,
            maxHeight: maxHeight,
          ),
          child: MediaImage(
            path: ref.path,
            bytes: bytesFor(ref.path),
            fit: BoxFit.contain,
            onTap: () => _openImage(ref),
          ),
        ),
      ),
    );
  }

  /// A link. Local media becomes a player or a picture; web links become
  /// tappable labels that open in a new tab.
  InlineSpan _link(md.Element el, _Level level, TextStyle base) {
    final String target = _resolve(el.attributes['href'] ?? '');
    final String label = el.textContent.trim();

    if (target.startsWith('assets/')) {
      final MediaRef? ref = mediaOf(target);
      if (ref == null) {
        return WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: MissingFileTile(path: target),
            ),
          ),
        );
      }
      if (ref.kind == MediaKind.voice) {
        return WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: VoiceClip(ref: ref, bytes: bytesFor(ref.path)),
            ),
          ),
        );
      }
      return _mediaInline(src: target, alt: label, maxHeight: 260);
    }

    final bool external = RegExp(
      r'^(https?:|mailto:|tel:)',
      caseSensitive: false,
    ).hasMatch(target);
    if (!external) {
      // A reference we cannot resolve outside the app is shown as written.
      final TextStyle s = base.copyWith(
        color: ink.textSoft,
        decoration: TextDecoration.underline,
        decorationColor: ink.lineStrong,
      );
      return TextSpan(style: s, children: <InlineSpan>[TextSpan(text: label)]);
    }

    return WidgetSpan(
      alignment: PlaceholderAlignment.baseline,
      baseline: TextBaseline.alphabetic,
      child: _LinkLabel(
        label: label,
        onTap: () => (onOpenLink ?? openExternal)(target),
      ),
    );
  }

  void _openImage(MediaRef ref) {
    final void Function(MediaRef ref)? handler = onOpenImage;
    if (handler != null) {
      handler(ref);
      return;
    }
    unawaited(
      showImageLightbox(context, ref: ref, bytes: bytesFor(ref.path)),
    );
  }

  /// Lays out a mixed run of block and inline nodes. Needed for list items and
/// quotes, where markdown puts inline content next to nested blocks.
  List<Widget> _flow(List<md.Node> nodes, _Level level) {
    final List<Widget> out = <Widget>[];
    final List<md.Node> pending = <md.Node>[];

    void flush() {
      if (pending.isEmpty) return;
      out.add(
        Text.rich(
          TextSpan(
            style: level.body,
            children: _inline(List<md.Node>.of(pending), level, base: level.body),
          ),
        ),
      );
      pending.clear();
    }

    for (final md.Node node in nodes) {
      if (_isBlock(node)) {
        flush();
        out.add(block(node, level));
      } else {
        pending.add(node);
      }
    }
    flush();
    return out;
  }

  static const Set<String> _blockTags = <String>{
    'p',
    'ul',
    'ol',
    'pre',
    'blockquote',
    'h1',
    'h2',
    'h3',
    'h4',
    'h5',
    'h6',
    'hr',
    'table',
  };

  static bool _isBlock(md.Node node) =>
      node is md.Element && _blockTags.contains(node.tag);

  /// Stacks widgets with even rhythm.
  Widget _stack(List<Widget> children, {double gap = 10}) {
    if (children.isEmpty) return const SizedBox.shrink();
    if (children.length == 1) return children.first;
    final List<Widget> out = <Widget>[];
    for (int i = 0; i < children.length; i++) {
      out.add(children[i]);
      if (i < children.length - 1) out.add(SizedBox(height: gap));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: out,
    );
  }

  // ------------------------------------------------------------------ lists

  Widget _list(md.Element el, _Level level, int depth) {
    final bool ordered = el.tag == 'ol';
    final int start = int.tryParse(el.attributes['start'] ?? '') ?? 1;
    final List<Widget> items = <Widget>[];
    int index = start;

    for (final md.Node child in el.children) {
      if (child is! md.Element || child.tag != 'li') continue;
      final String marker = ordered
          ? '$index.'
          : (depth == 0 ? '•' : '◦');
      index++;

      final List<md.Node> content = <md.Node>[];
      final List<md.Element> nested = <md.Element>[];
      for (final md.Node item in child.children) {
        if (_isBlock(item) &&
            item is md.Element &&
            (item.tag == 'ul' || item.tag == 'ol')) {
          nested.add(item);
        } else {
          content.add(item);
        }
      }

      items.add(
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SizedBox(
              width: ordered ? 27 : 20,
              child: Padding(
                padding: const EdgeInsets.only(top: 1.5),
                child: Text(
                  marker,
                  style: TextStyle(
                    fontFamily: ordered ? AppFonts.sans : AppFonts.sans,
                    fontSize: 14.5 * _scale,
                    height: 1.72,
                    fontWeight: FontWeight.w600,
                    color: level.quote ? ink.textFaint : ink.accent,
                  ),
                ),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  _stack(_flow(content, level), gap: 8),
                  for (final md.Element sub in nested)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: _list(sub, level, depth + 1),
                    ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return _stack(items, gap: 8);
  }

  Widget _quote(md.Element el, _Level level) {
    final _Level inner = _Level(_quoteBody, quote: true, depth: level.depth + 1);
    return Container(
      padding: const EdgeInsets.only(left: 16),
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(
            color: ink.accent.withValues(alpha: 0.45),
            width: 2.5,
          ),
        ),
      ),
      child: _stack(_flow(el.children, inner), gap: 10),
    );
  }

  Widget _rule() => Container(height: 1, color: ink.line);

  // -------------------------------------------------------------- code card

  Widget _code(md.Element el) {
    md.Element? codeEl;
    for (final md.Node child in el.children) {
      if (child is md.Element && child.tag == 'code') {
        codeEl = child;
        break;
      }
    }
    final String raw = (codeEl?.textContent ?? el.textContent).replaceFirst(
      RegExp(r'\n+$'),
      '',
    );
    final String language = _languageOf(codeEl?.attributes['class']);

    // Highlighting is skipped for very large blocks to keep scrolling smooth.
    final List<CodeToken> tokens = raw.length <= 12000
        ? highlightCode(raw, language)
        : <CodeToken>[CodeToken(raw, TokenKind.plain)];

    return ClipRRect(
      borderRadius: BorderRadius.circular(Tokens.rMd),
      child: Container(
        decoration: BoxDecoration(
          color: ink.codeBg,
          borderRadius: BorderRadius.circular(Tokens.rMd),
          border: Border.all(color: ink.codeLine),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      languageLabel(language),
                      style: TextStyle(
                        fontFamily: AppFonts.mono,
                        fontSize: 10.5,
                        letterSpacing: 1.1,
                        color: CodeTheme.dark.headerText,
                      ),
                    ),
                  ),
                  _CodeCopyButton(source: raw),
                ],
              ),
            ),
            Container(height: 1, color: ink.codeLine),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(15, 12, 15, 14),
                child: RichText(
                  softWrap: false,
                  text: TextSpan(
                    style: CodeTheme.base.copyWith(color: CodeTheme.dark.plain),
                    children: <TextSpan>[
                      for (final CodeToken token in tokens)
                        TextSpan(
                          text: token.text,
                          style: TextStyle(
                            color: CodeTheme.dark.colorFor(token.kind),
                            fontStyle: token.kind == TokenKind.comment
                                ? FontStyle.italic
                                : null,
                            fontWeight: token.kind == TokenKind.keyword
                                ? FontWeight.w600
                                : null,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _languageOf(String? klass) {
    if (klass == null || klass.isEmpty) return '';
    final RegExpMatch? match = RegExp(
      r'language-([\w+#.-]+)',
    ).firstMatch(klass);
    return match?.group(1) ?? '';
  }

  // ----------------------------------------------------------------- tables

  Widget _table(md.Element el, _Level level) {
    final List<List<Widget>> rendered = <List<Widget>>[];
    final List<bool> header = <bool>[];
    int widest = 0;

    for (final md.Node sectionNode in el.children) {
      if (sectionNode is! md.Element) continue;
      final bool isHead = sectionNode.tag == 'thead';
      for (final md.Node rowNode in sectionNode.children) {
        if (rowNode is! md.Element || rowNode.tag != 'tr') continue;
        final List<Widget> cells = <Widget>[];
        for (final md.Node cellNode in rowNode.children) {
          if (cellNode is! md.Element) continue;
          if (cellNode.tag != 'th' && cellNode.tag != 'td') continue;
          cells.add(_cell(cellNode, level, isHead));
        }
        if (cells.isEmpty) continue;
        widest = cells.length > widest ? cells.length : widest;
        rendered.add(cells);
        header.add(isHead);
      }
    }
    if (rendered.isEmpty) return const SizedBox.shrink();

    final List<TableRow> rows = <TableRow>[];
    for (int i = 0; i < rendered.length; i++) {
      final List<Widget> cells = List<Widget>.of(rendered[i]);
      while (cells.length < widest) {
        cells.add(const SizedBox.shrink());
      }
      rows.add(
        TableRow(
          decoration: header[i]
              ? BoxDecoration(color: ink.surfaceSunken)
              : null,
          children: cells,
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Table(
        defaultColumnWidth: const IntrinsicColumnWidth(),
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        border: TableBorder(
          top: BorderSide(color: ink.line),
          bottom: BorderSide(color: ink.line),
          horizontalInside: BorderSide(color: ink.line),
        ),
        children: rows,
      ),
    );
  }

  Widget _cell(md.Element cell, _Level level, bool isHead) {
    final TextAlign align = switch (cell.attributes['align']) {
      'center' => TextAlign.center,
      'right' => TextAlign.right,
      _ => TextAlign.left,
    };
    final TextStyle style = isHead
        ? TextStyle(
            fontFamily: AppFonts.sans,
            fontSize: 12.5 * _scale,
            height: 1.5,
            letterSpacing: 0.3,
            fontWeight: FontWeight.w700,
            color: ink.textSoft,
          )
        : level.body;

    // GFM wraps cell content in a paragraph; unwrap it for tight cells.
    List<md.Node> children = cell.children;
    if (children.length == 1 && children.first is md.Element) {
      final md.Element only = children.first as md.Element;
      if (only.tag == 'p') children = only.children;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
      child: Text.rich(
        TextSpan(
          style: style,
          children: _inline(children, level, base: style),
        ),
        textAlign: align,
      ),
    );
  }

  // ----------------------------------------------------------------- images

  Widget _imageBlock(md.Element el, double maxHeight) {
    final String path = _resolve(el.attributes['src'] ?? '');
    final String alt = el.attributes['alt'] ?? '';
    if (path.isEmpty) return Text(alt, style: body);

    final MediaRef? ref = mediaOf(path);
    if (ref == null) {
      return ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: MissingFileTile(path: path),
      );
    }
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: MediaImage(
          path: ref.path,
          bytes: bytesFor(ref.path),
          fit: BoxFit.contain,
          alignment: Alignment.centerLeft,
          onTap: () => _openImage(ref),
        ),
      ),
    );
  }

  /// Strips `../` so exported and in-app paths resolve identically.
  static String _resolve(String href) {
    final String trimmed = href.split('#').first.trim();
    return trimmed
        .replaceAll(RegExp(r'^(\.\./)+'), '')
        .replaceAll(RegExp(r'^\./'), '');
  }
}

/// Copy-to-clipboard control used inside the code card.
class _CodeCopyButton extends StatelessWidget {
  const _CodeCopyButton({required this.source});

  final String source;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Copy code',
      child: Tooltip(
        message: 'Copy',
        child: IconButton(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: source));
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Code copied'),
                duration: Duration(milliseconds: 1400),
              ),
            );
          },
          icon: const Icon(Icons.copy_rounded, size: 15),
          color: CodeTheme.dark.headerText,
          visualDensity: VisualDensity.compact,
          style: IconButton.styleFrom(
            highlightColor: Colors.white.withValues(alpha: 0.08),
            hoverColor: Colors.white.withValues(alpha: 0.06),
          ),
        ),
      ),
    );
  }
}

/// A tappable inline link with a hover underline.
class _LinkLabel extends StatefulWidget {
  const _LinkLabel({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  State<_LinkLabel> createState() => _LinkLabelState();
}

class _LinkLabelState extends State<_LinkLabel> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final Ink ink = context.ink;
    return Semantics(
      link: true,
      label: widget.label,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: Text(
            widget.label,
            style: TextStyle(
              fontFamily: AppFonts.sans,
              fontSize: 15.5,
              height: 1.4,
              color: ink.accent,
              decoration: _hovered
                  ? TextDecoration.underline
                  : TextDecoration.none,
              decorationColor: ink.accent,
            ),
          ),
        ),
      ),
    );
  }
}
}

/// Carries the text style that nested blocks should inherit.
class _Level {
  const _Level(this.body, {this.quote = false, this.depth = 0});

  final TextStyle body;
  final bool quote;
  final int depth;

  _Level deeper({bool? quote}) =>
      _Level(body, quote: quote ?? this.quote, depth: depth + 1);
}