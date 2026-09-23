/// The entry editor: title, date, tags, markdown writing with a small
/// toolbar, image + voice attachments, live preview, autosave.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import 'format_util.dart';
import 'markdown_render.dart';
import 'models.dart';
import 'store.dart';
import 'voice_notes.dart';

class EntryEditor extends StatefulWidget {
  const EntryEditor({
    super.key,
    required this.store,
    required this.entryId,
    required this.onClose,
  });

  final Store store;
  final String entryId;
  final VoidCallback onClose;

  @override
  State<EntryEditor> createState() => _EntryEditorState();
}

class _EntryEditorState extends State<EntryEditor> {
  late final TextEditingController _title = TextEditingController();
  late final TextEditingController _content = TextEditingController();
  final _contentFocus = FocusNode();

  bool _preview = false;
  bool _recorderOpen = false;
  bool _savingImage = false;

  Entry? _entry;

  Store get store => widget.store;

  @override
  void initState() {
    super.initState();
    _entry = store.entry(widget.entryId);
    _title.text = _entry?.title ?? '';
    _content.text = _entry?.content ?? '';
  }

  @override
  void dispose() {
    _title.dispose();
    _content.dispose();
    _contentFocus.dispose();
    super.dispose();
  }

  void _touch() {
    final e = _entry;
    if (e == null) return;
    e.title = _title.text;
    e.content = _content.text;
    store.touchEntry(e);
  }

  // ------------------------------------------------------------ text editing

  void _wrapSelection(String mark, {String placeholder = ''}) {
    final sel = _content.selection;
    if (!sel.isValid || sel.start < 0) return;
    final text = _content.text;
    final start = sel.start;
    final end = sel.end;
    final selected = start == end ? placeholder : text.substring(start, end);
    final replacement = '$mark$selected$mark';
    _content.value = _content.value.copyWith(
      text: text.replaceRange(start, end, replacement),
      selection: TextSelection.collapsed(
        offset: start + mark.length + selected.length,
      ),
    );
    _touch();
  }

  void _prefixLine(String prefix) {
    final sel = _content.selection;
    if (!sel.isValid || sel.start < 0) return;
    final text = _content.text;
    var lineStart = sel.start;
    while (lineStart > 0 && text[lineStart - 1] != '\n') {
      lineStart--;
    }
    _content.value = _content.value.copyWith(
      text: text.replaceRange(lineStart, lineStart, prefix),
      selection: TextSelection.collapsed(offset: sel.start + prefix.length),
    );
    _touch();
  }

  void _insertText(String snippet) {
    final sel = _content.selection;
    final text = _content.text;
    if (!sel.isValid || sel.start < 0) {
      _content.text = '$text\n$snippet';
    } else {
      var insert = snippet;
      if (sel.start > 0 && text[sel.start - 1] != '\n') insert = '\n$insert';
      _content.value = _content.value.copyWith(
        text: text.replaceRange(sel.start, sel.end, insert),
        selection: TextSelection.collapsed(offset: sel.start + insert.length),
      );
    }
    _touch();
    _contentFocus.requestFocus();
  }

  void _insertLink() {
    final sel = _content.selection;
    final selected = sel.isValid && sel.start >= 0 && sel.start != sel.end
        ? _content.text.substring(sel.start, sel.end)
        : '';
    final label = selected.isEmpty ? 'link text' : selected;
    _insertText('[$label](https://)');
  }

  // -------------------------------------------------------------- attachments

  Future<void> _attachImages() async {
    if (_savingImage) return;
    setState(() => _savingImage = true);
    try {
      final files = await openFiles(
        acceptedTypeGroups: const [
          XTypeGroup(label: 'Images', extensions: [
            'png', 'jpg', 'jpeg', 'gif', 'webp',
          ]),
        ],
      );
      if (files.isEmpty) return;
      final now = DateTime.now().millisecondsSinceEpoch;
      final inserts = <String>[];
      var skipped = 0;
      for (final f in files) {
        Uint8List bytes;
        try {
          bytes = await f.readAsBytes();
        } catch (_) {
          skipped++;
          continue;
        }
        final mime = sniffImageMime(bytes);
        if (mime == null || bytes.isEmpty) {
          skipped++;
          continue;
        }
        final attachment = Attachment(
          id: newId(),
          kind: 'image',
          name: f.name.isEmpty ? 'image' : f.name,
          mime: mime,
          size: bytes.length,
          createdAt: now,
        );
        _entry?.attachments.add(attachment);
        await store.putAsset(attachment.id, bytes);
        inserts.add(
          '![${_altFor(attachment)}](attachment:${attachment.id})',
        );
      }
      if (inserts.isNotEmpty) {
        for (final ref in inserts) {
          _insertText(ref);
        }
        _touch();
      }
      if (skipped > 0 && mounted) {
        _toast('$skipped file${skipped == 1 ? '' : 's'} skipped — '
            'only PNG, JPG, GIF and WebP images are supported.');
      }
      if (mounted) setState(() {});
    } finally {
      if (mounted) setState(() => _savingImage = false);
    }
  }

  String _altFor(Attachment a) {
    var base = a.name;
    final dot = base.lastIndexOf('.');
    if (dot > 0) base = base.substring(0, dot);
    return base.isEmpty ? 'Image' : base;
  }

  void _onVoiceRecorded(Uint8List bytes, String mime, int elapsedMs) {
    final e = _entry;
    if (e == null) return;
    final attachment = Attachment(
      id: newId(),
      kind: 'audio',
      name: 'Voice note',
      mime: mime,
      size: bytes.length,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
    e.attachments.add(attachment);
    store.putAsset(attachment.id, bytes).then((_) {
      final label = formatDuration(Duration(milliseconds: elapsedMs));
      _insertText('![Voice note · $label](attachment:${attachment.id})');
      _touch();
      if (mounted) setState(() => _recorderOpen = false);
    });
  }

  Future<void> _deleteAttachment(Attachment a) async {
    final e = _entry;
    if (e == null) return;
    final confirmed = await _confirm(
      title: a.isAudio ? 'Delete this recording?' : 'Remove this image?',
      message: a.isAudio
          ? 'The recording will be removed from this entry. This cannot be undone.'
          : 'The image will be removed from this entry. This cannot be undone.',
    );
    if (!confirmed) return;

    // Remove its markdown reference so no "missing media" chip is left behind.
    final pattern = RegExp('!?\\[[^\\]]*\\]\\(attachment:${a.id}[^)]*\\)');
    e.content = e.content.replaceAll(pattern, '');
    _content.text = e.content;
    e.attachments.removeWhere((x) => x.id == a.id);
    await store.deleteAsset(a.id);
    _touch();
    if (mounted) setState(() {});
  }

  void _insertAttachmentRef(Attachment a) {
    if (a.isAudio) {
      _insertText('![Voice note](attachment:${a.id})');
    } else {
      _insertText('![${_altFor(a)}](attachment:${a.id})');
    }
  }

  // ------------------------------------------------------------------ tags

  Future<void> _addTag() async {
    final e = _entry;
    if (e == null) return;
    final suggestions = store.tagCounts().keys.toList()..sort();
    final controller = TextEditingController();
    final tag = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Add tag'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: controller,
                autofocus: true,
                textInputAction: TextInputAction.done,
                onSubmitted: (value) => Navigator.of(dialogContext).pop(value),
                decoration: const InputDecoration(hintText: 'e.g. research'),
              ),
              if (suggestions.isNotEmpty) ...[
                const SizedBox(height: 14),
                Text('Existing tags',
                    style: Theme.of(dialogContext).textTheme.labelSmall),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final s in suggestions.take(12))
                      ActionChip(
                        label: Text(s),
                        onPressed: () =>
                            Navigator.of(dialogContext).pop(s),
                      ),
                  ],
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(controller.text),
              child: const Text('Add'),
            ),
          ],
        );
      },
    );
    controller.dispose();
    if (tag == null) return;
    final clean = tag.toLowerCase().trim().replaceAll('#', '').trim();
    if (clean.isEmpty || e.tags.contains(clean)) return;
    e.tags.add(clean);
    _touch();
    if (mounted) setState(() {});
  }

  // ------------------------------------------------------------------ misc

  Future<void> _pickDate() async {
    final e = _entry;
    if (e == null) return;
    final current = DateTime.fromMillisecondsSinceEpoch(e.date);
    final date = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(1900),
      lastDate: DateTime(2200),
    );
    if (date == null) return;
    if (!mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current),
    );
    final newDate = DateTime(
      date.year,
      date.month,
      date.day,
      time?.hour ?? current.hour,
      time?.minute ?? current.minute,
    );
    e.date = newDate.millisecondsSinceEpoch;
    _touch();
    if (mounted) setState(() {});
  }

  /// Commits any pending edits and leaves the entry — the explicit "Enter"
  /// that closes the writing flow.
  void _finish() {
    _touch();
    _contentFocus.unfocus();
    widget.onClose();
  }

  Future<void> _duplicate() async {
    final copy = store.duplicateEntry(widget.entryId);
    if (copy != null && mounted) {
      _toast('Duplicated — "${copy.title.isEmpty ? 'Untitled' : copy.title}"');
    }
  }

  Future<void> _deleteEntry() async {
    final e = _entry;
    if (e == null) return;
    final confirmed = await _confirm(
      title: 'Delete this entry?',
      message:
          '"${e.title.isEmpty ? 'Untitled' : e.title}" and its attachments '
          'will be permanently deleted.',
    );
    if (!confirmed) return;
    await store.deleteEntry(e.id);
    if (mounted) widget.onClose();
  }

  Future<bool> _confirm({required String title, required String message}) {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor:
                  Theme.of(dialogContext).colorScheme.error,
              foregroundColor:
                  Theme.of(dialogContext).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    ).then((v) => v ?? false);
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  // ------------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final e = store.entry(widget.entryId);
        // Entry was deleted elsewhere (e.g. journal deleted) — leave quietly.
        if (e == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) widget.onClose();
          });
          return const SizedBox.shrink();
        }
        _entry = e;

        final scheme = Theme.of(context).colorScheme;
        final wide = MediaQuery.widthOf(context) >= 760;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(scheme, wide),
            Divider(color: scheme.outlineVariant),
            _tagsRow(scheme),
            Expanded(
              child: _preview
                  ? _previewArea(context, e)
                  : GestureDetector(
                      onTap: () => _contentFocus.requestFocus(),
                      child: _contentField(context, scheme),
                    ),
            ),
            if (_recorderOpen) _recorderBar(scheme),
            _bottomBar(scheme, wide),
            if (e.attachments.isNotEmpty) _attachmentsStrip(scheme, e),
          ],
        );
      },
    );
  }

  Widget _header(ColorScheme scheme, bool wide) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        wide ? 4 : 0,
        6,
        4,
        8,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          IconButton(
            tooltip: 'Back',
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: widget.onClose,
          ),
          const SizedBox(width: 4),
          Expanded(
            child: TextField(
              controller: _title,
              onChanged: (_) => _touch(),
              textInputAction: TextInputAction.next,
              // Enter in the title drops into the body — keep writing.
              onSubmitted: (_) => _contentFocus.requestFocus(),
              style: Theme.of(context).textTheme.titleLarge,
              decoration: InputDecoration(
                border: InputBorder.none,
                focusedBorder: InputBorder.none,
                enabledBorder: InputBorder.none,
                filled: false,
                isCollapsed: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                hintText: 'Untitled entry',
                hintStyle: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(color: scheme.onSurfaceVariant.withValues(alpha: 0.5)),
              ),
            ),
          ),
          const SizedBox(width: 8),
          TextButton.icon(
            onPressed: _pickDate,
            icon: const Icon(Icons.event_outlined, size: 16),
            label: Text(
              wide
                  ? formatDateTime(_entry?.date ?? 0)
                  : formatDateShort(_entry?.date ?? 0),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontFamily: 'RobotoMono',
                    fontSize: 11.5,
                  ),
            ),
          ),
          const SizedBox(width: 4),
          FilledButton.tonalIcon(
            onPressed: _finish,
            icon: const Icon(Icons.check_rounded, size: 17),
            label: const Text('Done'),
            style: FilledButton.styleFrom(
              visualDensity: VisualDensity.compact,
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'Entry actions',
            onSelected: (value) {
              switch (value) {
                case 'duplicate':
                  _duplicate();
                case 'delete':
                  _deleteEntry();
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'duplicate',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.copy_all_rounded),
                  title: Text('Duplicate entry'),
                ),
              ),
              PopupMenuItem(
                value: 'delete',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.delete_outline_rounded),
                  title: Text('Delete entry'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _tagsRow(ColorScheme scheme) {
    final e = _entry;
    if (e == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
      child: Wrap(
        spacing: 6,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (final tag in e.tags)
            InputChip(
              label: Text('#$tag'),
              onPressed: null,
              onDeleted: () {
                e.tags.remove(tag);
                _touch();
                setState(() {});
              },
              deleteIconColor: scheme.onSurfaceVariant,
            ),
          ActionChip(
            avatar: Icon(Icons.add_rounded,
                size: 15, color: scheme.onSurfaceVariant),
            label: const Text('Tag'),
            onPressed: _addTag,
          ),
        ],
      ),
    );
  }

  Widget _contentField(BuildContext context, ColorScheme scheme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: TextField(
        controller: _content,
        focusNode: _contentFocus,
        maxLines: null,
        expands: true,
        textAlignVertical: TextAlignVertical.top,
        style: Theme.of(context).textTheme.bodyLarge,
        onChanged: (_) => _touch(),
        cursorColor: scheme.primary,
        decoration: InputDecoration(
          border: InputBorder.none,
          focusedBorder: InputBorder.none,
          enabledBorder: InputBorder.none,
          filled: false,
          isCollapsed: true,
          contentPadding: const EdgeInsets.only(top: 12, bottom: 24),
          hintText: 'Start writing… markdown works: **bold**, # headings,'
              ' - lists, ``` code',
          hintStyle: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: scheme.onSurfaceVariant.withValues(alpha: 0.5),
              ),
        ),
      ),
    );
  }

  Widget _previewArea(BuildContext context, Entry e) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      child: e.content.trim().isEmpty
          ? Padding(
              padding: const EdgeInsets.only(top: 40),
              child: Center(
                child: Text(
                  'Nothing to preview yet.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            )
          : MarkdownView(
              data: e.content,
              assetBytes: store.asset,
              attachmentOf: store.attachmentById,
            ),
    );
  }

  Widget _recorderBar(ColorScheme scheme) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        children: [
          Expanded(
            child: VoiceRecorder(
              onRecorded: _onVoiceRecorded,
              onError: _toast,
            ),
          ),
          IconButton(
            tooltip: 'Close recorder',
            icon: const Icon(Icons.close_rounded, size: 18),
            onPressed: () => setState(() => _recorderOpen = false),
          ),
        ],
      ),
    );
  }

  Widget _bottomBar(ColorScheme scheme, bool wide) {
    if (_preview) {
      return Container(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: scheme.outlineVariant)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Row(
          children: [
            const Icon(Icons.visibility_outlined, size: 15),
            const SizedBox(width: 8),
            Text('Reviewing', style: Theme.of(context).textTheme.labelSmall),
            const Spacer(),
            FilledButton.tonalIcon(
              onPressed: () => setState(() => _preview = false),
              icon: const Icon(Icons.edit_outlined, size: 17),
              label: const Text('Edit entry'),
              style: FilledButton.styleFrom(
                visualDensity: VisualDensity.compact,
              ),
            ),
          ],
        ),
      );
    }

    final buttons = <(IconData, String, VoidCallback)>[
      (Icons.format_bold_rounded, 'Bold (**)', () => _wrapSelection('**')),
      (Icons.format_italic_rounded, 'Italic (*)', () => _wrapSelection('*')),
      (Icons.format_quote_rounded, 'Heading (##)', () => _prefixLine('## ')),
      (Icons.format_list_bulleted_rounded, 'List (-)', () => _prefixLine('- ')),
      (Icons.format_list_numbered_rounded, 'Numbered list (1.)',
          () => _prefixLine('1. ')),
      (Icons.format_quote_outlined, 'Quote (>)', () => _prefixLine('> ')),
      (Icons.code_rounded, 'Code (`)', () => _wrapSelection('`')),
      (Icons.data_object_rounded, 'Code block', () {
        final sel = _content.selection;
        final selected = sel.isValid && sel.start >= 0 && sel.start != sel.end
            ? _content.text.substring(sel.start, sel.end)
            : '';
        _insertText('```\n$selected\n```');
      }),
      (Icons.link_rounded, 'Link', _insertLink),
      (Icons.horizontal_rule_rounded, 'Divider', () => _insertText('---')),
      (Icons.image_rounded, 'Attach image', _attachImages),
      (Icons.mic_none_rounded, 'Record voice note', () {
        setState(() => _recorderOpen = !_recorderOpen);
      }),
    ];

    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              child: Row(
                children: [
                  for (final (icon, tooltip, onTap) in buttons)
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      tooltip: tooltip,
                      icon: Icon(icon, size: 18),
                      onPressed: onTap,
                    ),
                  if (_savingImage)
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8),
                      child: SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                ],
              ),
            ),
          ),
          VerticalDivider(
            width: 9,
            thickness: 1,
            indent: 12,
            endIndent: 12,
            color: scheme.outlineVariant,
          ),
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: TextButton.icon(
              onPressed: () {
                _contentFocus.unfocus();
                setState(() => _preview = true);
              },
              icon: const Icon(Icons.visibility_outlined, size: 18),
              label: const Text('Review'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _attachmentsStrip(ColorScheme scheme, Entry e) {
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      constraints: const BoxConstraints(maxHeight: 118),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Attached media',
            style: Theme.of(context).textTheme.labelSmall,
          ),
          const SizedBox(height: 6),
          Expanded(
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final a in e.attachments)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: a.isAudio
                        ? _audioAttachment(scheme, a)
                        : _imageAttachment(scheme, a),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _imageAttachment(ColorScheme scheme, Attachment a) {
    final bytes = store.asset(a.id);
    return SizedBox(
      width: 132,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Material(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(8),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => _insertAttachmentRef(a),
                child: SizedBox(
                  width: double.infinity,
                  child: bytes == null
                      ? const Center(
                          child: Icon(Icons.broken_image_outlined, size: 18),
                        )
                      : Image.memory(bytes, fit: BoxFit.cover),
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: Text(
                  _altFor(a),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context)
                      .textTheme
                      .labelSmall
                      ?.copyWith(fontSize: 10.5),
                ),
              ),
              _miniIcon(
                Icons.add_circle_outline_rounded,
                'Insert into text',
                scheme,
                () => _insertAttachmentRef(a),
              ),
              _miniIcon(
                Icons.delete_outline_rounded,
                'Remove',
                scheme,
                () => _deleteAttachment(a),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _audioAttachment(ColorScheme scheme, Attachment a) {
    final bytes = store.asset(a.id);
    return SizedBox(
      width: 320,
      child: Column(
        children: [
          Expanded(
            child: Center(
              child: bytes == null
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.music_off_rounded,
                            size: 16, color: scheme.onSurfaceVariant),
                        const SizedBox(width: 6),
                        Text('Recording unavailable',
                            style:
                                Theme.of(context).textTheme.labelSmall),
                      ],
                    )
                  : AudioNoteCard(
                      attachment: a,
                      bytes: bytes,
                      compact: true,
                      onInsert: () => _insertAttachmentRef(a),
                      onDelete: () => _deleteAttachment(a),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _miniIcon(
    IconData icon,
    String tooltip,
    ColorScheme scheme,
    VoidCallback onTap,
  ) {
    return IconButton(
      visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
      iconSize: 14,
      tooltip: tooltip,
      color: scheme.onSurfaceVariant,
      icon: Icon(icon),
      onPressed: onTap,
    );
  }
}
