import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'markdown_view.dart';
import 'models.dart';
import 'theme.dart';
import 'ui_common.dart';
import 'voice.dart';

/// The writing surface.
///
/// Owns a draft of the entry, writes it back through [onSave] on a short
/// debounce, and flushes on focus loss and on the way out — so a reload never
/// loses what was typed. Markdown stays visible as text, and the preview is the
/// same renderer the reader uses.
class EntryEditor extends StatefulWidget {
  const EntryEditor({
    super.key,
    required this.entry,
    required this.onSave,
    required this.mediaOf,
    required this.bytesFor,
    required this.onAddImages,
    required this.onAddVoice,
    required this.onRecordVoice,
    this.onOpenImage,
    this.tall = false,
  });

  final Entry entry;
  final Future<void> Function(Entry draft) onSave;
  final MediaRef? Function(String path) mediaOf;
  final Future<Uint8List?> Function(String path) bytesFor;
  final Future<List<MediaRef>> Function() onAddImages;
  final Future<MediaRef?> Function(RecordedClip clip) onAddVoice;
  final Future<RecordedClip?> Function() onRecordVoice;
  final void Function(MediaRef ref)? onOpenImage;

  /// Gives the body the whole pane height, for the full entry screen.
  final bool tall;

  @override
  State<EntryEditor> createState() => _EntryEditorState();
}

class _EntryEditorState extends State<EntryEditor> {
  late Entry _draft = widget.entry;
  late final TextEditingController _title = TextEditingController(
    text: widget.entry.title,
  );
  late final TextEditingController _body = TextEditingController(
    text: widget.entry.content,
  );
  final TextEditingController _tagInput = TextEditingController();
  final FocusNode _bodyFocus = FocusNode();
  final FocusNode _tagFocus = FocusNode();

  Timer? _debounce;
  bool _dirty = false;
  bool _saving = false;
  bool _preview = false;
  bool _busyWithMedia = false;

  @override
  void initState() {
    super.initState();
    _bodyFocus.addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(covariant EntryEditor old) {
    super.didUpdateWidget(old);
    if (widget.entry.id != old.entry.id) {
      _adopt(widget.entry);
      return;
    }
    // Pick up changes made elsewhere (a deleted file, for instance), but never
    // overwrite what is being typed right now.
    if (!_dirty &&
        widget.entry.updatedAt != old.entry.updatedAt &&
        widget.entry.updatedAt != _draft.updatedAt) {
      _adopt(widget.entry);
    }
  }

  void _adopt(Entry entry) {
    _draft = entry;
    _title.text = entry.title;
    _body.text = entry.content;
    setState(() {});
  }

  void _onFocusChange() {
    if (!_bodyFocus.hasFocus) _flush();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    // Well inside the app's lifetime, so the write still lands.
    if (_dirty) unawaited(_save());
    _bodyFocus.removeListener(_onFocusChange);
    _bodyFocus.dispose();
    _tagFocus.dispose();
    _title.dispose();
    _body.dispose();
    _tagInput.dispose();
    super.dispose();
  }

  // -------------------------------------------------------------- saving

  void _edited() {
    _dirty = true;
    if (mounted) setState(() {});
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), _flush);
  }

  /// Writes pending changes now. Called on focus loss and on the way out.
  void _flush() {
    _debounce?.cancel();
    if (!_dirty || _saving) return;
    unawaited(_save());
  }

  Future<void> _save() async {
    if (_saving) return;
    _saving = true;
    final Entry payload = _draft.copyWith(
      title: _title.text,
      content: _body.text,
    );
    try {
      await widget.onSave(payload);
      _draft = payload;
      if (_body.text == payload.content && _title.text == payload.title) {
        _dirty = false;
      }
    } catch (_) {
      // AppState has already explained the failure; stay dirty so the next
      // edit retries instead of pretending everything saved.
    } finally {
      _saving = false;
      if (mounted) setState(() {});
    }
  }

  String get _statusLabel {
    if (_saving) return 'Saving…';
    if (_dirty) return 'Unsaved changes';
    return 'Saved ${relativeTime(_draft.updatedAt)}';
  }

  // -------------------------------------------------------------- editing

  RicherTextSelection get _selection {
    final TextSelection sel = _body.selection;
    final int length = _body.text.length;
    final int base = sel.baseOffset < 0 ? length : sel.baseOffset;
    final int extent = sel.extentOffset < 0 ? length : sel.extentOffset;
    return RicherTextSelection(
      start: base < extent ? base : extent,
      end: base < extent ? extent : base,
      collapsed: sel.isCollapsed,
    );
  }

  void _apply(String text, int selectionStart, int selectionEnd) {
    _body.value = TextEditingValue(
      text: text,
      selection: TextSelection(
        baseOffset: selectionStart,
        extentOffset: selectionEnd,
      ),
    );
    _edited();
  }

  /// Wraps the selection, or inserts the markers with the caret between them.
  void _surround(String before, String after) {
    final RicherTextSelection sel = _selection;
    final String text = _body.text;
    if (sel.collapsed) {
      final String insert = '$before$after';
      _apply(
        text.replaceRange(sel.start, sel.end, insert),
        sel.start + before.length,
        sel.start + before.length,
      );
      return;
    }
    final String selected = text.substring(sel.start, sel.end);
    final String replaced = '$before$selected$after';
    _apply(
      text.replaceRange(sel.start, sel.end, replaced),
      sel.start,
      sel.start + replaced.length,
    );
  }

  /// Applies a prefix to every selected line (lists, headings, quotes).
  void _prefixLines(String prefix) {
    final String text = _body.text;
    final RicherTextSelection sel = _selection;

    int lineStart = text.lastIndexOf('\n', sel.start == 0 ? 0 : sel.start - 1);
    lineStart = lineStart == -1 ? 0 : lineStart + 1;
    int lineEnd = text.indexOf('\n', sel.end);
    lineEnd = lineEnd == -1 ? text.length : lineEnd;

    final String block = text.substring(lineStart, lineEnd);
    final String updated = block
        .split('\n')
        .map((String line) => line.startsWith(prefix) ? line : '$prefix$line')
        .join('\n');
    _apply(
      text.replaceRange(lineStart, lineEnd, updated),
      lineStart,
      lineStart + updated.length,
    );
  }

  /// Inserts a standalone block, giving it blank lines around it.
  void _insertBlock(String block) {
    final String text = _body.text;
    final RicherTextSelection sel = _selection;
    final String before = text.substring(0, sel.start);
    final bool needsLeading = before.isNotEmpty && !before.endsWith('\n\n');
    final String insert = '${needsLeading ? '\n\n' : ''}$block\n';
    _apply(
      text.replaceRange(sel.start, sel.end, insert),
      sel.start + insert.length,
      sel.start + insert.length,
    );
  }

  // ----------------------------------------------------------- attachments

  Future<void> _attachImages() async {
    setState(() => _busyWithMedia = true);
    try {
      final List<MediaRef> refs = await widget.onAddImages();
      if (!mounted || refs.isEmpty) return;
      final List<MediaRef> fresh = <MediaRef>[
        for (final MediaRef r in refs)
          if (!_draft.media.any((MediaRef m) => m.path == r.path)) r,
      ];
      if (fresh.isEmpty) return;
      _draft = _draft.copyWith(media: <MediaRef>[..._draft.media, ...fresh]);
      _insertBlock(
        fresh.map((MediaRef r) => '![${r.name}](${r.path})').join('\n\n'),
      );
    } finally {
      if (mounted) setState(() => _busyWithMedia = false);
    }
  }

  Future<void> _attachVoice() async {
    final RecordedClip? clip = await widget.onRecordVoice();
    if (clip == null || !mounted) return;
    setState(() => _busyWithMedia = true);
    try {
      final MediaRef? ref = await widget.onAddVoice(clip);
      if (!mounted || ref == null) return;
      _draft = _draft.copyWith(media: <MediaRef>[..._draft.media, ref]);
      _insertBlock('[${ref.name}](${ref.path})');
    } finally {
      if (mounted) setState(() => _busyWithMedia = false);
    }
  }

  // ------------------------------------------------------------------ tags

  void _addTag(String raw) {
    final String tag = normalizeTag(raw);
    _tagInput.clear();
    if (tag.isEmpty || _draft.tags.contains(tag)) return;
    _draft = _draft.copyWith(tags: <String>[..._draft.tags, tag]);
    _edited();
  }

  void _removeTag(String tag) {
    _draft = _draft.copyWith(
      tags: <String>[
        for (final String t in _draft.tags)
          if (t != tag) t,
      ],
    );
    _edited();
  }

  Future<void> _pickDate() async {
    final DateTime? day = await showDatePicker(
      context: context,
      initialDate: _draft.date,
      firstDate: DateTime(1970),
      lastDate: DateTime(2999),
      helpText: 'Entry date',
    );
    if (day == null || !mounted) return;
    final TimeOfDay? time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_draft.date),
      helpText: 'Entry time',
    );
    final TimeOfDay chosen = time ?? TimeOfDay.fromDateTime(_draft.date);
    _draft = _draft.copyWith(
      date: DateTime(day.year, day.month, day.day, chosen.hour, chosen.minute),
    );
    _edited();
  }

  @override
  Widget build(BuildContext context) {
    final Ink ink = context.ink;
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool sideBySide =
            constraints.maxWidth >= 940 && widget.tall && _preview;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _header(ink),
            const SizedBox(height: Tokens.s2),
            _tagRow(ink),
            const SizedBox(height: Tokens.s3),
            _toolbar(ink, sideBySide),
            const SizedBox(height: Tokens.s3),
            Expanded(
              child: sideBySide
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Expanded(child: _writePane(ink)),
                        const SizedBox(width: Tokens.s4),
                        Expanded(child: _previewPane(ink)),
                      ],
                    )
                  : _preview
                  ? _previewPane(ink)
                  : _writePane(ink),
            ),
          ],
        );
      },
    );
  }

  // ----------------------------------------------------------------- header

  Widget _header(Ink ink) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(
          child: TextField(
            controller: _title,
            onChanged: (_) => _edited(),
            style: TextStyle(
              fontFamily: AppFonts.serif,
              fontSize: 26,
              height: 1.25,
              letterSpacing: -0.4,
              fontWeight: FontWeight.w600,
              color: ink.text,
            ),
            decoration: InputDecoration(
              hintText: 'Entry title',
              hintStyle: TextStyle(
                fontFamily: AppFonts.serif,
                fontSize: 26,
                height: 1.25,
                letterSpacing: -0.4,
                fontWeight: FontWeight.w600,
                color: ink.lineStrong,
              ),
              filled: false,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              isDense: true,
              contentPadding: EdgeInsets.zero,
            ),
            textInputAction: TextInputAction.next,
          ),
        ),
        const SizedBox(width: Tokens.s3),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              TextButton.icon(
                onPressed: _pickDate,
                icon: const Icon(Icons.event_outlined, size: 15),
                label: Text(
                  dateTimeLabel(_draft.date),
                  style: const TextStyle(
                    fontFamily: AppFonts.mono,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                style: TextButton.styleFrom(
                  foregroundColor: ink.textSoft,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  visualDensity: VisualDensity.compact,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                _statusLabel,
                style: TextStyle(
                  fontFamily: AppFonts.mono,
                  fontSize: 10.5,
                  letterSpacing: 0.4,
                  color: _dirty ? ink.brass : ink.textFaint,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _tagRow(Ink ink) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        for (final String tag in _draft.tags)
          TagPill(tag: tag, onRemove: () => _removeTag(tag)),
        SizedBox(
          width: 132,
          child: TextField(
            controller: _tagInput,
            focusNode: _tagFocus,
            onSubmitted: _addTag,
            style: TextStyle(
              fontFamily: AppFonts.mono,
              fontSize: 12,
              color: ink.text,
            ),
            decoration: InputDecoration(
              hintText: 'add #tag',
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 8,
              ),
              hintStyle: TextStyle(
                fontFamily: AppFonts.mono,
                fontSize: 11.5,
                color: ink.textFaint,
              ),
            ),
            textInputAction: TextInputAction.done,
          ),
        ),
      ],
    );
  }

  Widget _toolbar(Ink ink, bool sideBySide) {
    return Container(
      decoration: BoxDecoration(
        color: ink.surface,
        borderRadius: BorderRadius.circular(Tokens.rMd),
        border: Border.all(color: ink.line),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
      child: Row(
        children: <Widget>[
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: <Widget>[
                  _tool(ink, Icons.format_bold_rounded, 'Bold', () {
                    _surround('**', '**');
                  }),
                  _tool(ink, Icons.format_italic_rounded, 'Italic', () {
                    _surround('*', '*');
                  }),
                  _tool(ink, Icons.strikethrough_s_rounded, 'Strikethrough', () {
                    _surround('~~', '~~');
                  }),
                  _sep(ink),
                  _tool(ink, Icons.title_rounded, 'Heading', () {
                    _prefixLines('## ');
                  }),
                  _tool(ink, Icons.format_quote_rounded, 'Quote', () {
                    _prefixLines('> ');
                  }),
                  _sep(ink),
                  _tool(ink, Icons.format_list_bulleted_rounded, 'Bullet list', () {
                    _prefixLines('- ');
                  }),
                  _tool(
                    ink,
                    Icons.format_list_numbered_rounded,
                    'Numbered list',
                    () {
                      _prefixLines('1. ');
                    },
                  ),
                  _sep(ink),
                  _tool(ink, Icons.code_rounded, 'Code block', () {
                    final RicherTextSelection sel = _selection;
                    final String selected = _body.text.substring(
                      sel.start,
                      sel.end,
                    );
                    _insertBlock('```\n$selected\n```');
                  }),
                  _tool(ink, Icons.data_object_rounded, 'Inline code', () {
                    _surround('`', '`');
                  }),
                  _tool(ink, Icons.horizontal_rule_rounded, 'Divider', () {
                    _insertBlock('---');
                  }),
                  _tool(ink, Icons.link_rounded, 'Link', () {
                    _surround('[', '](https://)');
                  }),
                  _tool(ink, Icons.grid_on_rounded, 'Table', () {
                    _insertBlock(
                      '| Heading | Heading |\n| --- | --- |\n| Cell | Cell |',
                    );
                  }),
                  _sep(ink),
                  _tool(
                    ink,
                    Icons.image_outlined,
                    'Attach images',
                    _busyWithMedia ? null : _attachImages,
                  ),
                  _tool(
                    ink,
                    Icons.mic_none_rounded,
                    'Record a voice note',
                    _busyWithMedia ? null : _attachVoice,
                  ),
                ],
              ),
            ),
          ),
          if (!sideBySide) ...<Widget>[
            _sep(ink),
            _previewToggle(ink),
          ],
        ],
      ),
    );
  }

  Widget _tool(Ink ink, IconData icon, String label, VoidCallback? onPressed) {
    return _ToolButton(
      icon: icon,
      label: label,
      onPressed: onPressed,
      ink: ink,
    );
  }

  Widget _sep(Ink ink) => Container(
    width: 1,
    height: 20,
    margin: const EdgeInsets.symmetric(horizontal: 5),
    color: ink.line,
  );

  Widget _previewToggle(Ink ink) {
    Widget half(String label, bool active, IconData icon) {
      return InkWell(
        onTap: () => setState(() => _preview = label == 'Preview'),
        borderRadius: BorderRadius.circular(Tokens.rSm),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                icon,
                size: 14,
                color: active ? ink.accent : ink.textFaint,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: active ? ink.accent : ink.textSoft,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: ink.surfaceSunken,
        borderRadius: BorderRadius.circular(Tokens.rMd - 2),
        border: Border.all(color: ink.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          half('Write', !_preview, Icons.edit_outlined),
          half('Preview', _preview, Icons.visibility_outlined),
        ],
      ),
    );
  }

  Widget _writePane(Ink ink) {
    final TextField field = TextField(
      controller: _body,
      focusNode: _bodyFocus,
      onChanged: (_) => _edited(),
      expands: widget.tall,
      minLines: widget.tall ? null : 8,
      maxLines: null,
      keyboardType: TextInputType.multiline,
      textAlignVertical: TextAlignVertical.top,
      style: TextStyle(
        fontFamily: AppFonts.mono,
        fontSize: 14,
        height: 1.72,
        color: ink.text,
      ),
      cursorColor: ink.accent,
      decoration: InputDecoration(
        hintText:
            'Write in Markdown…\n\n'
            '## A heading\n'
            '- a list item\n'
            '> a quote\n\n'
            '```bash\nflutter run -d chrome\n```',
        hintStyle: TextStyle(
          fontFamily: AppFonts.mono,
          fontSize: 13.5,
          height: 1.72,
          color: ink.textFaint,
        ),
        filled: false,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        isDense: true,
        contentPadding: EdgeInsets.zero,
      ),
    );

    final Widget withShortcuts = CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.keyB, control: true): () =>
            _surround('**', '**'),
        const SingleActivator(LogicalKeyboardKey.keyB, meta: true): () =>
            _surround('**', '**'),
        const SingleActivator(LogicalKeyboardKey.keyI, control: true): () =>
            _surround('*', '*'),
        const SingleActivator(LogicalKeyboardKey.keyI, meta: true): () =>
            _surround('*', '*'),
        const SingleActivator(LogicalKeyboardKey.keyE, control: true): () =>
            _surround('`', '`'),
        const SingleActivator(LogicalKeyboardKey.keyE, meta: true): () =>
            _surround('`', '`'),
        const SingleActivator(LogicalKeyboardKey.keyK, control: true): () =>
            _surround('[', '](https://)'),
        const SingleActivator(LogicalKeyboardKey.keyK, meta: true): () =>
            _surround('[', '](https://)'),
      },
      child: field,
    );

    return Container(
      padding: const EdgeInsets.all(Tokens.s4),
      decoration: BoxDecoration(
        color: ink.surface,
        borderRadius: BorderRadius.circular(Tokens.rLg),
        border: Border.all(color: ink.line),
      ),
      child: FocusTraversalGroup(child: withShortcuts),
    );
  }

  Widget _previewPane(Ink ink) {
    return Container(
      padding: const EdgeInsets.all(Tokens.s5),
      decoration: BoxDecoration(
        color: ink.surface,
        borderRadius: BorderRadius.circular(Tokens.rLg),
        border: Border.all(color: ink.line),
      ),
      child: Scrollbar(
        child: SingleChildScrollView(
          primary: false,
          child: MarkdownView(
            source: _body.text,
            mediaOf: widget.mediaOf,
            bytesFor: widget.bytesFor,
            onOpenImage: widget.onOpenImage,
            compact: !widget.tall,
          ),
        ),
      ),
    );
  }
}

/// One toolbar button. Tooltips double as screen-reader labels.
class _ToolButton extends StatelessWidget {
  const _ToolButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    required this.ink,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final Ink ink;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(icon, size: 17),
        color: ink.textSoft,
        disabledColor: ink.lineStrong,
        visualDensity: VisualDensity.compact,
        constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
        padding: EdgeInsets.zero,
        style: IconButton.styleFrom(
          hoverColor: ink.accentWash,
          highlightColor: ink.accentWash,
        ),
      ),
    );
  }
}
}

/// A simple start/end pair; [TextSelection] keeps direction, which makes
/// editing operations awkward.
class RicherTextSelection {
  const RicherTextSelection({
    required this.start,
    required this.end,
    required this.collapsed,
  });

  final int start;
  final int end;
  final bool collapsed;
}