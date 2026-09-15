import 'package:flutter/material.dart' hide Ink;

import 'app_state.dart';
import 'markdown_editor.dart';
import 'markdown_view.dart';
import 'models.dart';
import 'theme.dart';
import 'ui_attach.dart';
import 'ui_common.dart';
import 'ui_media.dart';
import 'voice.dart';

/// One entry: reading, editing, and everything that can happen to it.
///
/// The same pane serves every layout — the shell decides how much room it gets,
/// which is why there is no separate mobile screen.
class EntryPane extends StatelessWidget {
  const EntryPane({super.key, this.onBack});

  /// Shown on narrow layouts to step back to the list.
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final AppState state = AppScope.of(context);
    final Entry? entry = state.currentEntry;
    if (entry == null) {
      return const EmptyState(
        glyph: '✎',
        title: 'Nothing open',
        message: 'Pick an entry from the list, or start a new one.',
      );
    }

    final Journal? journal = state.journal(entry.journalId);
    final bool editing = state.editingEntry;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        EntryHeader(
          entry: entry,
          journal: journal,
          editing: editing,
          onBack: onBack,
          onToggleEdit: () {
            if (editing) {
              state.stopEditing();
            } else {
              state.selectEntry(entry.id, edit: true);
            }
          },
        ),
        const SizedBox(height: Tokens.s3),
        Expanded(
          child: editing
              ? EntryEditor(
                  key: ValueKey<String>('editor:${entry.id}'),
                  entry: entry,
                  tall: true,
                  onSave: state.saveEntry,
                  mediaOf: (String path) => mediaOf(entry, path),
                  bytesFor: state.mediaBytes,
                  onAddImages: () => pickImages(state),
                  onRecordVoice: () => recordVoiceNote(context),
                  onAddVoice: (RecordedClip clip) => state.addMedia(
                    bytes: clip.bytes,
                    name: '',
                    mime: clip.mime,
                    kind: MediaKind.voice,
                    duration: clip.seconds,
                  ),
                  onOpenImage: (MediaRef ref) => openMedia(
                    context,
                    state,
                    ref,
                    heroTag: 'attachment:${ref.id}',
                  ),
                )
              : _Reader(entry: entry, state: state),
        ),
      ],
    );
  }
}

/// Finds the reference an `assets/…` path belongs to.
MediaRef? mediaOf(Entry entry, String path) {
  for (final MediaRef ref in entry.media) {
    if (ref.path == path) return ref;
  }
  return null;
}

/// Opens one stored picture full screen.
Future<void> openMedia(
  BuildContext context,
  AppState state,
  MediaRef ref, {
  String? heroTag,
}) {
  return showImageLightbox(
    context,
    ref: ref,
    bytes: state.mediaBytes(ref.path),
    heroTag: heroTag,
  );
}

/// The actions menu for one entry: duplicate, export-adjacent info, delete.
class EntryMenu extends StatelessWidget {
  const EntryMenu({super.key, required this.entry});

  final Entry entry;

  @override
  Widget build(BuildContext context) {
    final Ink ink = context.ink;
    final AppState state = AppScope.of(context);

    return PopupMenuButton<String>(
      tooltip: 'Entry actions',
      icon: Icon(Icons.more_horiz_rounded, size: 18, color: ink.textSoft),
      color: ink.surface,
      elevation: 0,
      position: PopupMenuPosition.under,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Tokens.rMd),
        side: BorderSide(color: ink.line),
      ),
      onSelected: (String action) async {
        switch (action) {
          case 'duplicate':
            await state.duplicateEntry(entry.id);
            state.say('Entry duplicated.');
          case 'copy':
            await _copyMarkdown(context, state, entry);
          case 'delete':
            final bool ok = await confirm(
              context,
              title: 'Delete this entry?',
              message:
                  '"${entry.displayTitle}" and its attachments will be '
                  'removed from this browser. This cannot be undone.',
              confirmLabel: 'Delete entry',
              destructive: true,
            );
            if (!ok) return;
            final String name = entry.displayTitle;
            await state.deleteEntry(entry.id);
            state.say('Deleted "$name".');
        }
      },
      itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
        _item(context, 'duplicate', Icons.copy_all_outlined, 'Duplicate'),
        _item(context, 'copy', Icons.content_copy_outlined, 'Copy Markdown'),
        const PopupMenuDivider(),
        _item(
          context,
          'delete',
          Icons.delete_outline_rounded,
          'Delete',
          danger: true,
        ),
      ],
    );
  }

  static PopupMenuItem<String> _item(
    BuildContext context,
    String value,
    IconData icon,
    String label, {
    bool danger = false,
  }) {
    final Ink ink = context.ink;
    return PopupMenuItem<String>(
      value: value,
      height: 42,
      child: Row(
        children: <Widget>[
          Icon(icon, size: 16, color: danger ? ink.danger : ink.textSoft),
          const SizedBox(width: Tokens.s3),
          Text(
            label,
            style: TextStyle(
              fontSize: 13.5,
              color: danger ? ink.danger : ink.text,
            ),
          ),
        ],
      ),
    );
  }
}

/// Puts the entry into the clipboard as portable markdown, front matter and
/// all, so it can be pasted into any other editor or tool.
Future<void> _copyMarkdown(
  BuildContext context,
  AppState state,
  Entry entry,
) async {
  final Bundle bundle = exportJournal(
    journal:
        state.journal(entry.journalId) ??
        Journal(
          id: 'x',
          name: 'Journal',
          createdAt: entry.createdAt,
          updatedAt: entry.updatedAt,
        ),
    entries: <Entry>[entry],
    media: const <MediaRecord>[],
  );
  final String file = bundle.files.keys.firstWhere(
    (String k) => k.startsWith('journal/'),
    orElse: () => '',
  );
  final String markdown = file.isEmpty
      ? entry.content
      : String.fromCharCodes(bundle.files[file]!);
  await Clipboard.setData(ClipboardData(text: markdown));
  if (!context.mounted) return;
  state.say('Entry copied as Markdown.');
}

/// Small text-and-icon action used in pane headers.
class _GhostAction extends StatelessWidget {
  const _GhostAction({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.accent = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final Ink ink = context.ink;
    return TextButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 15),
      label: Text(label),
      style: TextButton.styleFrom(
        foregroundColor: accent ? ink.accent : ink.textSoft,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}

//__HEADER__