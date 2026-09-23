/// All journal.md pages: journals overview, journal view, timeline, search
/// and tags — plus the shared entry row and dialogs.
library;

import 'package:flutter/material.dart';

import 'format_util.dart';
import 'markdown_render.dart';
import 'models.dart';
import 'store.dart';

// ------------------------------------------------------------------ dialogs

Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Delete',
}) {
  final scheme = Theme.of(context).colorScheme;
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
            backgroundColor: scheme.error,
            foregroundColor: scheme.onError,
          ),
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  ).then((v) => v ?? false);
}

Future<({String name, String description})?> showJournalDialog(
  BuildContext context, {
  required String title,
  String confirmLabel = 'Create',
  String initialName = '',
  String initialDescription = '',
}) {
  final name = TextEditingController(text: initialName);
  final description = TextEditingController(text: initialDescription);
  final formKey = GlobalKey<FormState>();

  return showDialog<({String name, String description})>(
    context: context,
    builder: (dialogContext) {
      void submit() {
        if (formKey.currentState!.validate()) {
          Navigator.of(dialogContext).pop(
            (name: name.text.trim(), description: description.text.trim()),
          );
        }
      }

      return AlertDialog(
        title: Text(title),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: name,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Name',
                  hintText: 'e.g. Daily',
                ),
                textInputAction: TextInputAction.next,
                validator: (v) =>
                    (v ?? '').trim().isEmpty ? 'Give it a name' : null,
                onFieldSubmitted: (_) =>
                    FocusScope.of(dialogContext).nextFocus(),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: description,
                decoration: const InputDecoration(
                  labelText: 'Description (optional)',
                  hintText: 'What is this journal for?',
                ),
                maxLines: 2,
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => submit(),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: submit,
            child: Text(confirmLabel),
          ),
        ],
      );
    },
  ).whenComplete(() {
    name.dispose();
    description.dispose();
  });
}

void toast(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: scheme.onSurfaceVariant.withValues(alpha: 0.6)),
            const SizedBox(height: 18),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: Text(
                message,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            if (action != null) ...[const SizedBox(height: 20), action!],
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- entry row

class EntryRow extends StatelessWidget {
  const EntryRow({
    super.key,
    required this.store,
    required this.entry,
    required this.onOpen,
    this.showJournal = false,
  });

  final Store store;
  final Entry entry;
  final VoidCallback onOpen;
  final bool showJournal;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final journal = store.journal(entry.journalId);
    final title = entry.title.trim().isEmpty ? 'Untitled' : entry.title.trim();
    final preview = markdownToPlain(entry.content)
        .replaceAll('\n', ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    return InkWell(
      onTap: onOpen,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        formatDateTime(entry.date),
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              fontFamily: 'RobotoMono',
                              fontSize: 11,
                            ),
                      ),
                      if (showJournal && journal != null) ...[
                        Text(
                          '  ·  ${journal.name}',
                          style:
                              Theme.of(context).textTheme.labelSmall?.copyWith(
                                    fontStyle: FontStyle.italic,
                                  ),
                        ),
                      ],
                    ],
                  ),
                  if (entry.tags.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      entry.tags.map((t) => '#$t').join('  '),
                      style: Theme.of(context)
                          .textTheme
                          .labelSmall
                          ?.copyWith(color: scheme.secondary),
                    ),
                  ],
                  if (preview.isNotEmpty) ...[
                    const SizedBox(height: 5),
                    Text(
                      preview,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                  if (entry.attachments.isNotEmpty) ...[
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        Icon(Icons.image_outlined,
                            size: 13, color: scheme.onSurfaceVariant),
                        const SizedBox(width: 4),
                        if (entry.images.length > 1)
                          Text('${entry.images.length} images',
                              style:
                                  Theme.of(context).textTheme.labelSmall),
                        if (entry.images.length == 1)
                          Text('1 image',
                              style: Theme.of(context).textTheme.labelSmall),
                        if (entry.audioNotes.isNotEmpty) ...[
                          const SizedBox(width: 10),
                          Icon(Icons.graphic_eq_rounded,
                              size: 13, color: scheme.onSurfaceVariant),
                          const SizedBox(width: 4),
                          Text(
                              '${entry.audioNotes.length} '
                              'voice note${entry.audioNotes.length == 1 ? '' : 's'}',
                              style: Theme.of(context).textTheme.labelSmall),
                        ],
                      ],
                    ),
                  ],
                ],
              ),
            ),
            IconButton(
              tooltip: 'Edit entry',
              visualDensity: VisualDensity.compact,
              iconSize: 18,
              color: scheme.onSurfaceVariant,
              onPressed: onOpen,
              icon: const Icon(Icons.edit_outlined),
            ),
            _entryMenu(context, scheme),
          ],
        ),
      ),
    );
  }

  Widget _entryMenu(BuildContext context, ColorScheme scheme) {
    return PopupMenuButton<String>(
      tooltip: 'Entry actions',
      color: scheme.surface,
      onSelected: (value) async {
        switch (value) {
          case 'open':
            onOpen();
          case 'duplicate':
            final copy = store.duplicateEntry(entry.id);
            if (copy != null && context.mounted) {
              toast(
                context,
                'Duplicated — "${copy.title.isEmpty ? 'Untitled' : copy.title}"',
              );
            }
          case 'delete':
            final confirmed = await confirmDialog(
              context,
              title: 'Delete this entry?',
              message:
                  '"${entry.title.isEmpty ? 'Untitled' : entry.title}" and its '
                  'attachments will be permanently deleted.',
            );
            if (confirmed) await store.deleteEntry(entry.id);
        }
      },
      itemBuilder: (context) => const [
        PopupMenuItem(
          value: 'open',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.edit_outlined),
            title: Text('Edit entry'),
          ),
        ),
        PopupMenuItem(
          value: 'duplicate',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.copy_all_rounded),
            title: Text('Duplicate'),
          ),
        ),
        PopupMenuItem(
          value: 'delete',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.delete_outline_rounded),
            title: Text('Delete'),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------- journals overview

class JournalsPage extends StatelessWidget {
  const JournalsPage({
    super.key,
    required this.store,
    required this.onOpenJournal,
  });

  final Store store;
  final void Function(String journalId) onOpenJournal;

  Future<void> _create(BuildContext context) async {
    final result = await showJournalDialog(context, title: 'New journal');
    if (result == null) return;
    final journal = store.createJournal(result.name, result.description);
    if (context.mounted) onOpenJournal(journal.id);
  }

  Future<void> _rename(
      BuildContext context, String id, String name, String description) async {
    final result = await showJournalDialog(
      context,
      title: 'Rename journal',
      confirmLabel: 'Save',
      initialName: name,
      initialDescription: description,
    );
    if (result == null) return;
    store.updateJournal(id, name: result.name, description: result.description);
  }

  Future<void> _delete(BuildContext context, Journal journal) async {
    final count = store.entryCount(journal.id);
    final confirmed = await confirmDialog(
      context,
      title: 'Delete "${journal.name}"?',
      message: count == 0
          ? 'This empty journal will be permanently deleted.'
          : '$count ${count == 1 ? 'entry' : 'entries'} and their attachments '
              'will be permanently deleted with it.',
    );
    if (!confirmed) return;
    await store.deleteJournal(journal.id);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final scheme = Theme.of(context).colorScheme;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 24, 24, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Journals',
                            style:
                                Theme.of(context).textTheme.displaySmall),
                        const SizedBox(height: 4),
                        Text(
                          store.journals.isEmpty
                              ? 'Your notebooks live here.'
                              : '${store.journals.length} '
                                  'journal${store.journals.length == 1 ? '' : 's'}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _create(context),
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('New journal'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: store.journals.isEmpty
                  ? EmptyState(
                      icon: Icons.auto_stories_outlined,
                      title: 'Create your first journal',
                      message:
                          'A journal is a notebook — one for daily notes, one '
                          'per project, one for research. Everything stays in '
                          'this browser, saved automatically.',
                      action: FilledButton.icon(
                        onPressed: () => _create(context),
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: const Text('New journal'),
                      ),
                    )
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        final columns =
                            (constraints.maxWidth / 380).ceil().clamp(1, 3);
                        return GridView.builder(
                          padding: const EdgeInsets.fromLTRB(
                              24, 12, 24, 32),
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: columns,
                            mainAxisSpacing: 12,
                            crossAxisSpacing: 12,
                            childAspectRatio: 1.45,
                          ),
                          itemCount: store.journals.length,
                          itemBuilder: (context, index) {
                            final journal = store.journals[index];
                            return _JournalCard(
                              journal: journal,
                              entryCount: store.entryCount(journal.id),
                              lastActivity: store.lastActivity(journal.id),
                              scheme: scheme,
                              onOpen: () => onOpenJournal(journal.id),
                              onRename: () => _rename(
                                context,
                                journal.id,
                                journal.name,
                                journal.description,
                              ),
                              onDelete: () => _delete(context, journal),
                            );
                          },
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _JournalCard extends StatelessWidget {
  const _JournalCard({
    required this.journal,
    required this.entryCount,
    required this.lastActivity,
    required this.scheme,
    required this.onOpen,
    required this.onRename,
    required this.onDelete,
  });

  final Journal journal;
  final int entryCount;
  final int lastActivity;
  final ColorScheme scheme;
  final VoidCallback onOpen;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: scheme.surface,
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: scheme.outlineVariant),
          ),
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      journal.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: 'Lora',
                        fontWeight: FontWeight.w600,
                        fontSize: 18,
                        height: 1.3,
                      ),
                    ),
                  ),
                  PopupMenuButton<String>(
                    tooltip: 'Journal actions',
                    onSelected: (value) {
                      switch (value) {
                        case 'rename':
                          onRename();
                        case 'delete':
                          onDelete();
                      }
                    },
                    itemBuilder: (context) => const [
                      PopupMenuItem(
                        value: 'rename',
                        child: ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.edit_outlined),
                          title: Text('Rename / edit'),
                        ),
                      ),
                      PopupMenuItem(
                        value: 'delete',
                        child: ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.delete_outline_rounded),
                          title: Text('Delete journal'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Expanded(
                child: Text(
                  journal.description.isEmpty
                      ? 'No description.'
                      : journal.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(fontStyle: FontStyle.italic),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Text(
                    '$entryCount ${entryCount == 1 ? 'entry' : 'entries'}',
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                  if (lastActivity > 0) ...[
                    Text(
                      '  ·  ',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                    Expanded(
                      child: Text(
                        formatUpdatedLabel(lastActivity),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------- journal view

class JournalView extends StatelessWidget {
  const JournalView({
    super.key,
    required this.store,
    required this.journalId,
    required this.onOpenEntry,
  });

  final Store store;
  final String journalId;
  final void Function(String entryId) onOpenEntry;

  Future<void> _rename(BuildContext context, Journal journal) async {
    final result = await showJournalDialog(
      context,
      title: 'Rename journal',
      confirmLabel: 'Save',
      initialName: journal.name,
      initialDescription: journal.description,
    );
    if (result == null) return;
    store.updateJournal(journal.id,
        name: result.name, description: result.description);
  }

  Future<void> _delete(BuildContext context, Journal journal) async {
    final count = store.entryCount(journal.id);
    final confirmed = await confirmDialog(
      context,
      title: 'Delete "${journal.name}"?',
      message: count == 0
          ? 'This empty journal will be permanently deleted.'
          : '$count ${count == 1 ? 'entry' : 'entries'} and their attachments '
              'will be permanently deleted with it.',
    );
    if (!confirmed) return;
    await store.deleteJournal(journal.id);
  }

  void _newEntry() {
    final entry = store.createEntry(journalId);
    onOpenEntry(entry.id);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final scheme = Theme.of(context).colorScheme;
        final journal = store.journal(journalId);

        if (journal == null) {
          return EmptyState(
            icon: Icons.book_outlined,
            title: 'This journal is gone',
            message: 'It may have been deleted. Pick another one from '
                'the Journals list.',
          );
        }

        final entries = store.entriesOf(journalId);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 24, 24, 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(journal.name,
                            style:
                                Theme.of(context).textTheme.displaySmall),
                        if (journal.description.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            journal.description,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(fontStyle: FontStyle.italic),
                          ),
                        ],
                        const SizedBox(height: 6),
                        Text(
                          entries.isEmpty
                              ? 'No entries yet.'
                              : '${entries.length} '
                                  '${entries.length == 1 ? 'entry' : 'entries'}'
                                  '${store.lastActivity(journalId) > 0 ? '  ·  ${formatUpdatedLabel(store.lastActivity(journalId))}' : ''}',
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Edit journal',
                    visualDensity: VisualDensity.compact,
                    iconSize: 19,
                    color: scheme.onSurfaceVariant,
                    onPressed: () => _rename(context, journal),
                    icon: const Icon(Icons.edit_outlined),
                  ),
                  PopupMenuButton<String>(
                    tooltip: 'Journal actions',
                    onSelected: (value) {
                      switch (value) {
                        case 'rename':
                          _rename(context, journal);
                        case 'delete':
                          _delete(context, journal);
                      }
                    },
                    itemBuilder: (context) => const [
                      PopupMenuItem(
                        value: 'rename',
                        child: ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.edit_outlined),
                          title: Text('Rename / edit'),
                        ),
                      ),
                      PopupMenuItem(
                        value: 'delete',
                        child: ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.delete_outline_rounded),
                          title: Text('Delete journal'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _newEntry,
                    icon: const Icon(Icons.edit_note_rounded, size: 19),
                    label: const Text('New entry'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: entries.isEmpty
                  ? EmptyState(
                      icon: Icons.edit_note_rounded,
                      title: 'No entries yet',
                      message:
                          'Start writing — markdown, images and voice notes '
                          'all work, and everything saves automatically.',
                      action: FilledButton.icon(
                        onPressed: _newEntry,
                        icon: const Icon(Icons.edit_note_rounded, size: 19),
                        label: const Text('Write the first entry'),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.only(top: 8, bottom: 32),
                      itemCount: entries.length,
                      itemBuilder: (context, index) {
                        final entry = entries[index];
                        return Column(
                          children: [
                            EntryRow(
                              store: store,
                              entry: entry,
                              onOpen: () => onOpenEntry(entry.id),
                            ),
                            if (index != entries.length - 1)
                              Divider(indent: 20, endIndent: 20,
                                  color: scheme.outlineVariant),
                          ],
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------- timeline

class TimelinePage extends StatelessWidget {
  const TimelinePage({
    super.key,
    required this.store,
    required this.onOpenEntry,
  });

  final Store store;
  final void Function(String entryId) onOpenEntry;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final entries = store.allEntries();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 24, 24, 4),
              child: Text('Timeline',
                  style: Theme.of(context).textTheme.displaySmall),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 4, 24, 8),
              child: Text(
                entries.isEmpty
                    ? 'Everything you write, in order.'
                    : '${entries.length} entr${entries.length == 1 ? 'y' : 'ies'} across '
                        '${store.journals.length} journal${store.journals.length == 1 ? '' : 's'}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            Expanded(
              child: entries.isEmpty
                  ? EmptyState(
                      icon: Icons.timeline_outlined,
                      title: 'Your timeline is empty',
                      message:
                          'Entries from every journal appear here, newest '
                          'first.',
                    )
                  : _timelineList(context, entries),
            ),
          ],
        );
      },
    );
  }

  Widget _timelineList(BuildContext context, List<Entry> entries) {
    final scheme = Theme.of(context).colorScheme;

    // Group by month while the list is already sorted newest → oldest.
    final groups = <(String, List<Entry>)>[];
    for (final entry in entries) {
      final label = formatMonthYear(entry.date);
      if (groups.isEmpty || groups.last.$1 != label) {
        groups.add((label, [entry]));
      } else {
        groups.last.$2.add(entry);
      }
    }

    return ListView.builder(
      padding: const EdgeInsets.only(top: 4, bottom: 32),
      itemCount: groups.length,
      itemBuilder: (context, groupIndex) {
        final (label, groupEntries) = groups[groupIndex];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 18, 24, 6),
              child: Row(
                children: [
                  Text(
                    label.toUpperCase(),
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          letterSpacing: 1.2,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(child: Divider()),
                ],
              ),
            ),
            for (final entry in groupEntries)
              _timelineRow(context, scheme, entry),
          ],
        );
      },
    );
  }

  Widget _timelineRow(BuildContext context, ColorScheme scheme, Entry entry) {
    final journal = store.journal(entry.journalId);
    final title = entry.title.trim().isEmpty ? 'Untitled' : entry.title.trim();
    final preview = markdownToPlain(entry.content)
        .replaceAll('\n', ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final d = DateTime.fromMillisecondsSinceEpoch(entry.date);

    return InkWell(
      onTap: () => onOpenEntry(entry.id),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 52,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    '${d.day}',
                    style: const TextStyle(
                      fontFamily: 'Lora',
                      fontWeight: FontWeight.w600,
                      fontSize: 20,
                      height: 1.1,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    formatWeekday(entry.date),
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w500),
                        ),
                      ),
                      if (journal != null)
                        Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: Text(
                            journal.name,
                            style:
                                Theme.of(context).textTheme.labelSmall?.copyWith(
                                      fontStyle: FontStyle.italic,
                                    ),
                          ),
                        ),
                    ],
                  ),
                  if (preview.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      preview,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                  if (entry.tags.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      entry.tags.map((t) => '#$t').join('  '),
                      style: Theme.of(context)
                          .textTheme
                          .labelSmall
                          ?.copyWith(color: scheme.secondary),
                    ),
                  ],
                ],
              ),
            ),
            IconButton(
              tooltip: 'Edit entry',
              visualDensity: VisualDensity.compact,
              iconSize: 18,
              color: scheme.onSurfaceVariant,
              onPressed: () => onOpenEntry(entry.id),
              icon: const Icon(Icons.edit_outlined),
            ),
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ search

class SearchPage extends StatefulWidget {
  const SearchPage({
    super.key,
    required this.store,
    required this.onOpenJournal,
    required this.onOpenEntry,
  });

  final Store store;
  final void Function(String journalId) onOpenJournal;
  final void Function(String entryId) onOpenEntry;

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final _controller = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final q = _query.trim().toLowerCase();

    return AnimatedBuilder(
      animation: widget.store,
      builder: (context, _) {
        final store = widget.store;

        List<Journal> journals = [];
        List<(Entry, String snippet)> entries = [];

        if (q.isNotEmpty) {
          for (final j in store.journals) {
            if (j.name.toLowerCase().contains(q) ||
                j.description.toLowerCase().contains(q)) {
              journals.add(j);
            }
          }
          for (final e in store.entries.values) {
            final inTitle = e.title.toLowerCase().contains(q);
            final inTags = e.tags.any((t) => t.contains(q));
            String? snippet;
            if (inTitle || inTags) {
              final plain = markdownToPlain(e.content)
                  .replaceAll('\n', ' ')
                  .replaceAll(RegExp(r'\s+'), ' ')
                  .trim();
              snippet = plain.isEmpty ? '' : _clip(plain, 120);
            } else {
              final plain = markdownToPlain(e.content)
                  .replaceAll('\n', ' ')
                  .replaceAll(RegExp(r'\s+'), ' ')
                  .trim();
              final i = plain.toLowerCase().indexOf(q);
              if (i >= 0) {
                snippet = _around(plain, i, q.length);
              }
            }
            if (inTitle || inTags || snippet != null) {
              entries.add((e, snippet ?? ''));
            }
          }
          entries.sort((a, b) => b.$1.date.compareTo(a.$1.date));
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 24, 24, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Search',
                      style: Theme.of(context).textTheme.displaySmall),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _controller,
                    autofocus: true,
                    onChanged: (v) => setState(() => _query = v),
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search_rounded, size: 19),
                      suffixIcon: _query.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Clear',
                              icon: const Icon(Icons.close_rounded, size: 17),
                              onPressed: () {
                                _controller.clear();
                                setState(() => _query = '');
                              },
                            ),
                      hintText: 'Journals, entries, content, tags…',
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: q.isEmpty
                  ? EmptyState(
                      icon: Icons.search_rounded,
                      title: 'Search everything',
                      message:
                          'Journal names, entry titles, full entry text and '
                          'tags — all searched instantly, all locally.',
                    )
                  : _results(context, scheme, journals, entries, q),
            ),
          ],
        );
      },
    );
  }

  Widget _results(
    BuildContext context,
    ColorScheme scheme,
    List<Journal> journals,
    List<(Entry, String snippet)> entries,
    String q,
  ) {
    if (journals.isEmpty && entries.isEmpty) {
      return EmptyState(
        icon: Icons.search_off_rounded,
        title: 'No matches for “$_query”',
        message: 'Try a shorter word, or check the spelling.',
      );
    }

    return ListView(
      padding: const EdgeInsets.only(top: 4, bottom: 32),
      children: [
        if (journals.isNotEmpty) ...[
          _sectionHeader(context, 'Journals'),
          for (final j in journals)
            ListTile(
              leading: const Icon(Icons.book_outlined, size: 19),
              title: Text(j.name),
              subtitle: j.description.isEmpty
                  ? null
                  : Text(
                      j.description,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
              dense: true,
              onTap: () => widget.onOpenJournal(j.id),
            ),
        ],
        if (entries.isNotEmpty) ...[
          _sectionHeader(
              context, 'Entries · ${entries.length}'),
          for (final (entry, snippet) in entries)
            _entryResult(context, scheme, entry, snippet, q),
        ],
      ],
    );
  }

  Widget _sectionHeader(BuildContext context, String label) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 18, 24, 6),
      child: Row(
        children: [
          Text(
            label.toUpperCase(),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(width: 12),
          const Expanded(child: Divider()),
        ],
      ),
    );
  }

  Widget _entryResult(
    BuildContext context,
    ColorScheme scheme,
    Entry entry,
    String snippet,
    String q,
  ) {
    final journal = widget.store.journal(entry.journalId);
    final title = entry.title.trim().isEmpty ? 'Untitled' : entry.title.trim();

    return InkWell(
      onTap: () => widget.onOpenEntry(entry.id),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: _highlight(context, title, q,
                      Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w500)),
                ),
                if (journal != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Text(
                      journal.name,
                      style:
                          Theme.of(context).textTheme.labelSmall?.copyWith(
                                fontStyle: FontStyle.italic,
                              ),
                    ),
                  ),
                IconButton(
                  tooltip: 'Edit entry',
                  visualDensity: VisualDensity.compact,
                  iconSize: 18,
                  color: scheme.onSurfaceVariant,
                  onPressed: () => widget.onOpenEntry(entry.id),
                  icon: const Icon(Icons.edit_outlined),
                ),
              ],
            ),
            const SizedBox(height: 3),
            Text(
              formatDateTime(entry.date),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontFamily: 'RobotoMono',
                    fontSize: 11,
                  ),
            ),
            if (snippet.isNotEmpty) ...[
              const SizedBox(height: 4),
              _highlight(
                context,
                snippet,
                q,
                Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                maxLines: 2,
              ),
            ],
            if (entry.tags.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                entry.tags.map((t) => '#$t').join('  '),
                style: Theme.of(context)
                    .textTheme
                    .labelSmall
                    ?.copyWith(color: scheme.secondary),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Renders [text] with case-insensitive matches of [q] emphasized.
  Widget _highlight(
    BuildContext context,
    String text,
    String q,
    TextStyle? style, {
    int maxLines = 1,
  }) {
    if (q.isEmpty) {
      return Text(text,
          style: style, maxLines: maxLines, overflow: TextOverflow.ellipsis);
    }
    final scheme = Theme.of(context).colorScheme;
    final spans = <TextSpan>[];
    var start = 0;
    final lower = text.toLowerCase();
    while (true) {
      final i = lower.indexOf(q, start);
      if (i < 0) {
        if (start < text.length) {
          spans.add(TextSpan(text: text.substring(start)));
        }
        break;
      }
      if (i > start) {
        spans.add(TextSpan(text: text.substring(start, i)));
      }
      spans.add(TextSpan(
        text: text.substring(i, i + q.length),
        style: TextStyle(
          backgroundColor: scheme.secondary.withValues(alpha: 0.18),
          fontWeight: FontWeight.w600,
        ),
      ));
      start = i + q.length;
    }
    return Text.rich(
      TextSpan(children: spans, style: style),
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
    );
  }

  String _clip(String text, int n) =>
      text.length <= n ? text : '${text.substring(0, n)}…';

  /// A window of [text] centred around the match at [index].
  String _around(String text, int index, int length) {
    const pad = 44;
    final start = (index - pad).clamp(0, text.length);
    final end = (index + length + pad).clamp(0, text.length);
    final prefix = start > 0 ? '…' : '';
    final suffix = end < text.length ? '…' : '';
    return '$prefix${text.substring(start, end)}$suffix';
  }
}

// --------------------------------------------------------------------- tags

class TagsPage extends StatefulWidget {
  const TagsPage({
    super.key,
    required this.store,
    required this.onOpenEntry,
  });

  final Store store;
  final void Function(String entryId) onOpenEntry;

  @override
  State<TagsPage> createState() => _TagsPageState();
}

class _TagsPageState extends State<TagsPage> {
  final _controller = TextEditingController();
  String _filter = '';
  String? _selected;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return AnimatedBuilder(
      animation: widget.store,
      builder: (context, _) {
        final store = widget.store;
        final counts = store.tagCounts();
        final allTags = counts.keys.toList()..sort();
        final filtered = _filter.trim().isEmpty
            ? allTags
            : allTags
                .where((t) => t.contains(_filter.trim().toLowerCase()))
                .toList()
              ..sort((a, b) => (counts[b] ?? 0).compareTo(counts[a] ?? 0));
        if (_filter.trim().isNotEmpty) {
          filtered.sort((a, b) => (counts[b] ?? 0).compareTo(counts[a] ?? 0));
        }
        if (_selected != null && !allTags.contains(_selected)) {
          _selected = null;
        }
        final selectedEntries =
            _selected == null ? <Entry>[] : store.entriesWithTag(_selected!);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 24, 24, 4),
              child: Text('Tags',
                  style: Theme.of(context).textTheme.displaySmall),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 4, 24, 12),
              child: counts.isEmpty
                  ? Text(
                      'Tags you add to entries collect here.',
                      style: Theme.of(context).textTheme.bodySmall,
                    )
                  : TextField(
                      controller: _controller,
                      onChanged: (v) => setState(() => _filter = v),
                      decoration: InputDecoration(
                        prefixIcon:
                            const Icon(Icons.search_rounded, size: 19),
                        suffixIcon: _filter.isEmpty
                            ? null
                            : IconButton(
                                tooltip: 'Clear',
                                icon:
                                    const Icon(Icons.close_rounded, size: 17),
                                onPressed: () {
                                  _controller.clear();
                                  setState(() => _filter = '');
                                },
                              ),
                        hintText: 'Filter tags…',
                      ),
                    ),
            ),
            Expanded(
              child: counts.isEmpty
                  ? EmptyState(
                      icon: Icons.sell_outlined,
                      title: 'No tags yet',
                      message:
                          'Add tags to entries — like #research or #ideas — '
                          'and use them to filter what you wrote.',
                    )
                  : CustomScrollView(
                      slivers: [
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(
                                28, 4, 24, 12),
                            child: Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (final tag in filtered)
                                  _tagChip(
                                      context, scheme, tag, counts[tag] ?? 0),
                              ],
                            ),
                          ),
                        ),
                        if (_selected != null) ...[
                          SliverToBoxAdapter(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                      28, 8, 24, 6),
                                  child: Row(
                                    children: [
                                      Text(
                                        '#$_selected · '
                                        '${selectedEntries.length} '
                                        '${selectedEntries.length == 1 ? 'entry' : 'entries'}',
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelSmall
                                            ?.copyWith(
                                              fontWeight: FontWeight.w600,
                                            ),
                                      ),
                                      const SizedBox(width: 12),
                                      const Expanded(child: Divider()),
                                      TextButton(
                                        onPressed: () => setState(
                                            () => _selected = null),
                                        child: const Text('Clear'),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          SliverList.builder(
                            itemCount: selectedEntries.length,
                            itemBuilder: (context, index) {
                              final entry = selectedEntries[index];
                              return EntryRow(
                                store: store,
                                entry: entry,
                                onOpen: () =>
                                    widget.onOpenEntry(entry.id),
                                showJournal: true,
                              );
                            },
                          ),
                        ],
                      ],
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _tagChip(
      BuildContext context, ColorScheme scheme, String tag, int count) {
    final selected = _selected == tag;
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: () => setState(() => _selected = selected ? null : tag),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: selected ? scheme.secondary : scheme.outlineVariant,
          ),
          color: selected ? scheme.surfaceContainerLow : Colors.transparent,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '#$tag',
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 12.5,
                color: selected ? scheme.secondary : scheme.onSurface,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '$count',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontSize: 11,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
