/// Custom markdown renderer for journal.md.
///
/// Parses with the pure-Dart `markdown` package (GitHub flavoured) and walks
/// the AST with widgets styled for an editorial, minimal look: Lora for
/// headings, Inter for body text, Roboto Mono for code.
///
/// Images can reference stored attachments with `![alt](attachment:<id>)`;
/// audio attachments render as an inline player.
library;

import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:markdown/markdown.dart' as md;

import 'models.dart';
import 'voice_notes.dart';
import 'web_ext.dart';

/// Extracts plain text from markdown (previews, search snippets).
String markdownToPlain(String data) {
  if (data.trim().isEmpty) return '';
  final nodes =
      md.Document(extensionSet: md.ExtensionSet.gitHubWeb).parse(data);
  final buffer = StringBuffer();
  for (final node in nodes) {
    _collectText(node, buffer);
    buffer.write('\n');
  }
  return buffer.toString().trim();
}

void _collectText(md.Node node, StringBuffer out) {
  if (node is md.Text) {
    out.write(node.text);
  } else if (node is md.Element) {
    for (final child in node.children ?? const <md.Node>[]) {
      _collectText(child, out);
    }
  }
}

class MarkdownView extends StatefulWidget {
  const MarkdownView({
    super.key,
    required this.data,
    this.assetBytes,
    this.attachmentOf,
  });

  final String data;

  /// Resolves `attachment:<id>` references to raw bytes.
  final Uint8List? Function(String id)? assetBytes;

  /// Resolves `attachment:<id>` references to their metadata.
  final Attachment? Function(String id)? attachmentOf;

  @override
  State<MarkdownView> createState() => _MarkdownViewState();
}

class _MarkdownViewState extends State<MarkdownView> {
  final List<TapGestureRecognizer> _recognizers = [];

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  void _disposeRecognizers() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
  }

  /// Concatenated text content of an AST node (code blocks, raw HTML…).
  String _textOf(md.Node node) {
    if (node is md.Text) return node.text;
    if (node is md.Element) {
      final buffer = StringBuffer();
      for (final child in node.children ?? const <md.Node>[]) {
        buffer.write(_textOf(child));
      }
      return buffer.toString();
    }
    return '';
  }

  TapGestureRecognizer _linkRecognizer(String href) {
    final r = TapGestureRecognizer()..onTap = () => openInNewTab(href);
    _recognizers.add(r);
    return r;
  }

  @override
  Widget build(BuildContext context) {
    _disposeRecognizers();
    if (widget.data.trim().isEmpty) return const SizedBox.shrink();
    final nodes =
        md.Document(extensionSet: md.ExtensionSet.gitHubWeb).parse(widget.data);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final node in nodes) _block(node, context, tight: false),
      ],
    );
  }

  // ------------------------------------------------------------ typography

  TextStyle _body(BuildContext context) =>
      Theme.of(context).textTheme.bodyLarge!.copyWith(
            height: 1.7,
            fontSize: 15.5,
            color: Theme.of(context).colorScheme.onSurface,
          );

  TextStyle _muted(BuildContext context) =>
      _body(context).copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant);

  // ------------------------------------------------------------- block nodes

  Widget _block(md.Node node, BuildContext context, {required bool tight}) {
    if (node is md.Text) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text(node.text, style: _body(context)),
      );
    }
    if (node is! md.Element) return const SizedBox.shrink();

    switch (node.tag) {
      case 'h1':
      case 'h2':
      case 'h3':
      case 'h4':
      case 'h5':
      case 'h6':
        return _heading(node, context);
      case 'p':
        return _paragraph(node, context, tight: tight);
      case 'blockquote':
        return _quote(node, context);
      case 'ul':
      case 'ol':
        return _list(node, context, ordered: node.tag == 'ol');
      case 'li':
        return _paragraph(node, context, tight: tight);
      case 'pre':
        return _codeBlock(node, context);
      case 'hr':
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Divider(
            height: 1,
            thickness: 1,
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        );
      case 'table':
        return _table(node, context);
      case 'checkbox':
        return const SizedBox.shrink();
      default:
        final children = node.children ?? const <md.Node>[];
        if (children.isEmpty) {
          final text = _textOf(node);
          if (text.trim().isEmpty) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(text, style: _body(context)),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final child in children)
              _block(child, context, tight: tight),
          ],
        );
    }
  }

  Widget _heading(md.Element el, BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final level = int.parse(el.tag[1]);
    const sizes = [26.0, 22.0, 18.0, 16.0, 15.0, 14.0];
    const topPadding = [28.0, 24.0, 20.0, 18.0, 16.0, 16.0];
    final size = sizes[level - 1];
    final style = TextStyle(
      fontFamily: 'Lora',
      fontWeight: FontWeight.w600,
      fontSize: size,
      height: 1.3,
      color: scheme.onSurface,
    );
    final span = _inlineSpan(el.children ?? const [], style, context);
    return Padding(
      padding: EdgeInsets.only(
        top: topPadding[level - 1],
        bottom: level <= 2 ? 10 : 8,
      ),
      child: Text.rich(span),
    );
  }

  Widget _paragraph(md.Element el, BuildContext context, {required bool tight}) {
    final children = el.children ?? const <md.Node>[];
    if (children.isEmpty) return const SizedBox.shrink();

    // Split inline runs and standalone images into block children so images
    // can take the full width and open the lightbox.
    final blocks = <Widget>[];
    final spans = <InlineSpan>[];

    void flushSpans() {
      if (spans.isNotEmpty) {
        blocks.add(Padding(
          padding: EdgeInsets.only(bottom: tight ? 4 : 12),
          child: Text.rich(
            TextSpan(children: List<InlineSpan>.of(spans)),
          ),
        ));
        spans.clear();
      }
    }

    for (final child in children) {
      if (child is md.Element && child.tag == 'img') {
        flushSpans();
        blocks.add(_blockImage(child, context));
      } else {
        spans.add(_inline(child, _body(context), context));
      }
    }
    flushSpans();

    if (blocks.length == 1) return blocks.first;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: blocks,
    );
  }

  Widget _quote(md.Element el, BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final children = el.children ?? const <md.Node>[];
    final quoteStyle = TextStyle(
      fontFamily: 'Lora',
      fontStyle: FontStyle.italic,
      fontSize: 15.5,
      height: 1.7,
      color: scheme.onSurfaceVariant,
    );
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.only(left: 16, top: 2, bottom: 2),
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(width: 2.5, color: scheme.outline),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final child in children)
            if (child is md.Element && child.tag == 'p')
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text.rich(
                  _inlineSpan(child.children ?? const [], quoteStyle, context),
                ),
              )
            else
              _block(child, context, tight: true),
        ],
      ),
    );
  }

  Widget _list(md.Element el, BuildContext context, {required bool ordered}) {
    final items = [
      for (final child in el.children ?? const <md.Node>[])
        if (child is md.Element && child.tag == 'li') child
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < items.length; i++)
            _listItem(items[i], i, context, ordered: ordered),
        ],
      ),
    );

    // Marker styling keeps lists quiet and scannable.
  }

  Widget _listItem(md.Element li, int index, BuildContext context,
      {required bool ordered}) {
    final scheme = Theme.of(context).colorScheme;
    final children = li.children ?? const <md.Node>[];

    // GitHub task list: first child is an <input type=checkbox>.
    final isTask = children.isNotEmpty &&
        children.first is md.Element &&
        (children.first as md.Element).tag == 'input';
    final checked = isTask &&
        (children.first as md.Element).attributes.containsKey('checked');

    Widget marker;
    if (isTask) {
      marker = Icon(
        checked ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
        size: 16,
        color: checked ? scheme.secondary : scheme.onSurfaceVariant,
      );
    } else {
      marker = SizedBox(
        width: ordered ? 24 : 16,
        child: Text(
          ordered ? '${index + 1}.' : '•',
          style: _muted(context).copyWith(fontSize: 14, height: 1.6),
        ),
      );
    }

    final contentChildren = [
      for (final child in (isTask ? children.skip(1) : children))
        _block(child, context, tight: true)
    ];

    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 24, child: Center(child: marker)),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: contentChildren,
            ),
          ),
        ],
      ),
    );
  }

  Widget _codeBlock(md.Element pre, BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    var text = _textOf(pre);
    String? language;
    // Strip a trailing newline that fenced blocks commonly carry.
    if (text.endsWith('\n')) text = text.substring(0, text.length - 1);

    final codeChild = pre.children?.firstOrNull;
    if (codeChild is md.Element && codeChild.tag == 'code') {
      final cls = codeChild.attributes['class'] ?? '';
      final match = RegExp(r'language-([\w+-]+)').firstMatch(cls);
      if (match != null) language = match.group(1);
      text = _textOf(codeChild);
      if (text.endsWith('\n')) text = text.substring(0, text.length - 1);
    }

    final mono = TextStyle(
      fontFamily: 'RobotoMono',
      fontSize: 13.5,
      height: 1.65,
      color: scheme.onSurface,
    );

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (language != null) ...[
            Text(
              language,
              style: mono.copyWith(
                fontSize: 11,
                letterSpacing: 0.6,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
          ],
          SelectableText(
            text,
            style: mono,
          ),
        ],
      ),
    );
  }

  Widget _table(md.Element el, BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final rows = <(List<md.Element> cells, bool header)>[];

    void collectRows(md.Node parent, {bool header = false}) {
      if (parent is! md.Element) return;
      for (final child in parent.children ?? const <md.Node>[]) {
        if (child is md.Element && child.tag == 'tr') {
          final cells = <md.Element>[
            for (final c in child.children ?? const <md.Node>[])
              if (c is md.Element && (c.tag == 'th' || c.tag == 'td')) c
          ];
          if (cells.isNotEmpty) {
            rows.add((cells, header || cells.first.tag == 'th'));
          }
        } else if (child is md.Element &&
            (child.tag == 'thead' || child.tag == 'tbody' || child.tag == 'tfoot')) {
          collectRows(child, header: child.tag == 'thead');
        }
      }
    }

    collectRows(el);

    if (rows.isEmpty) return const SizedBox.shrink();

    final cellStyle = TextStyle(
      fontFamily: 'Inter',
      fontSize: 13.5,
      height: 1.5,
      color: scheme.onSurface,
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Table(
            border: TableBorder.all(
              color: scheme.outlineVariant,
              width: 1,
              borderRadius: BorderRadius.circular(8),
            ),
            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
            children: [
              for (final (cells, header) in rows)
                TableRow(
                  decoration: header
                      ? BoxDecoration(color: scheme.surfaceContainerLow)
                      : null,
                  children: [
                    for (final cell in cells)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 9),
                        child: Text.rich(
                          _inlineSpan(
                            cell.children ?? const [],
                            cellStyle.copyWith(
                              fontWeight: header ? FontWeight.w600 : null,
                            ),
                            context,
                          ),
                        ),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------ inline nodes

  InlineSpan _inlineSpan(
      List<md.Node> nodes, TextStyle style, BuildContext context) {
    return TextSpan(
      children: [
        for (final node in nodes) _inline(node, style, context),
      ],
    );
  }

  InlineSpan _inline(md.Node node, TextStyle style, BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (node is md.Text) {
      return TextSpan(text: node.text, style: style);
    }
    if (node is! md.Element) return const TextSpan(text: '');

    switch (node.tag) {
      case 'strong':
        return _inlineSpan(
            node.children ?? const [], style.copyWith(fontWeight: FontWeight.w600), context);
      case 'em':
        return _inlineSpan(
            node.children ?? const [], style.copyWith(fontStyle: FontStyle.italic), context);
      case 'del':
      case 'strike':
        return _inlineSpan(
            node.children ?? const [],
            style.copyWith(
              decoration: TextDecoration.lineThrough,
              color: scheme.onSurfaceVariant,
            ),
            context);
      case 'code':
        return WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: Text(
              _textOf(node),
              style: TextStyle(
                fontFamily: 'RobotoMono',
                fontSize: style.fontSize != null ? style.fontSize! - 1.5 : 13,
                height: 1.5,
                color: scheme.onSurface,
              ),
            ),
          ),
        );
      case 'a':
        final href = node.attributes['href'] ?? '';
        final content = _inlineSpan(
          node.children ?? const [],
          style.copyWith(
            color: scheme.secondary,
            decoration: TextDecoration.underline,
            decorationColor: scheme.outline,
            decorationThickness: 1.2,
          ),
          context,
        );
        if (href.startsWith('http://') || href.startsWith('https://')) {
          return TextSpan(
            children: [content],
            recognizer: _linkRecognizer(href),
          );
        }
        return content;
      case 'img':
        return WidgetSpan(
          alignment: PlaceholderAlignment.bottom,
          child: _blockImage(node, context),
        );
      case 'br':
        return const TextSpan(text: '\n');
      case 'input':
        final checked = node.attributes.containsKey('checked');
        return WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Icon(
            checked
                ? Icons.check_box_rounded
                : Icons.check_box_outline_blank_rounded,
            size: 14,
            color: checked ? scheme.secondary : scheme.onSurfaceVariant,
          ),
        );
      default:
        return _inlineSpan(node.children ?? const [], style, context);
    }
  }

  // ---------------------------------------------------------------- images

  Widget _blockImage(md.Element img, BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final src = img.attributes['src'] ?? '';
    final alt = img.attributes['alt'] ?? '';

    if (src.startsWith('attachment:')) {
      final id = src.substring('attachment:'.length);
      final attachment = widget.attachmentOf?.call(id);
      final bytes = widget.assetBytes?.call(id);

      if (attachment != null && attachment.isAudio) {
        if (bytes == null) {
          return _missingMedia(context, 'Missing recording');
        }
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: AudioNoteCard(attachment: attachment, bytes: bytes, compact: true),
        );
      }

      if (bytes == null) {
        return _missingMedia(context, alt.isEmpty ? 'Missing image' : alt);
      }
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Align(
          alignment: Alignment.centerLeft,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: GestureDetector(
              onTap: () => _showLightbox(context, bytes, alt),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: scheme.outlineVariant),
                ),
                clipBehavior: Clip.antiAlias,
                child: Image.memory(
                  bytes,
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) => _missingMedia(
                    context,
                    'Image could not be displayed',
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    if (src.startsWith('http://') || src.startsWith('https://')) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Align(
          alignment: Alignment.centerLeft,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: scheme.outlineVariant),
              ),
              clipBehavior: Clip.antiAlias,
              child: Image.network(
                src,
                fit: BoxFit.contain,
                loadingBuilder: (context, child, progress) => progress == null
                    ? child
                    : const SizedBox(
                        height: 140,
                        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                      ),
                errorBuilder: (_, _, _) => SizedBox(
                  height: 60,
                  child: Center(
                    child: Text(
                      'Image could not be loaded',
                      style: _muted(context).copyWith(fontSize: 13),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        alt.isEmpty ? src : alt,
        style: _muted(context).copyWith(
          fontSize: 13,
          fontStyle: FontStyle.italic,
        ),
      ),
    );
  }

  Widget _missingMedia(BuildContext context, String label) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.broken_image_outlined,
              size: 16, color: scheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Text(label, style: _muted(context).copyWith(fontSize: 13)),
        ],
      ),
    );
  }

  void _showLightbox(BuildContext context, Uint8List bytes, String alt) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.86),
      builder: (dialogContext) {
        return Scaffold(
          backgroundColor: Colors.transparent,
          body: Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  onTap: () => Navigator.of(dialogContext).pop(),
                  child: InteractiveViewer(
                    maxScale: 6,
                    child: Center(
                      child: Image.memory(bytes, fit: BoxFit.contain),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 14,
                right: 16,
                child: IconButton(
                  tooltip: 'Close',
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.black.withValues(alpha: 0.4),
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  icon: const Icon(Icons.close_rounded),
                ),
              ),
              if (alt.trim().isNotEmpty)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 24,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        alt,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontFamily: 'Inter',
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
