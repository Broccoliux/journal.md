import 'package:flutter/material.dart' hide Ink;

import 'app_state.dart';
import 'models.dart';
import 'theme.dart';
import 'ui_common.dart';
import 'ui_data.dart';
import 'ui_entry.dart';
import 'ui_media.dart';

/// The journals section: every journal as a card, plus the tools to create,
/// rename, re-describe and delete them.
class JournalsPane extends StatelessWidget {
  const JournalsPane({super.key});

  @override
  Widget build(BuildContext context) {
    final AppState state = AppScope.of(context);
    final List<Journal> journals = state.journals;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: Tokens.appMaxWidth),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(Tokens.s6),
          child: journals.isEmpty
              ? EmptyState(
                  glyph: '⌘',
                  title: 'No journals yet',
                  message:
                      'A journal is a place for one part of your work — daily '
                      'life, a project, a course. Everything you write stays '
                      'in this browser, and can be exported as Markdown.',
                  actions: <Widget>[
                    FilledButton.icon(
                      onPressed: () => showJournalDialog(context),
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: const Text('Create a journal'),
                    ),
                    TextButton(
                      onPressed: state.createStarterJournal,
                      child: const Text('Or start with the guided journal'),
                    ),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            'Journals',
                            style: context.textTheme.displaySmall,
                          ),
                        ),
                        FilledButton.icon(
                          onPressed: () => showJournalDialog(context),
                          icon: const Icon(Icons.add_rounded, size: 18),
                          label: const Text('New journal'),
                        ),
                      ],
                    ),
                    const SizedBox(height: Tokens.s5),
                    AppearIn(
                      order: 0,
                      child: LayoutBuilder(
                        builder:
                            (BuildContext context, BoxConstraints box) =>
                                Wrap(
                                  spacing: Tokens.s4,
                                  runSpacing: Tokens.s4,
                                  children: <Widget>[
                                    for (int i = 0; i < journals.length; i++)
                                      SizedBox(
                                        width: cardWidth(box.maxWidth),
                                        child: AppearIn(
                                          order: i + 1,
                                          child: JournalCard(
                                            journal: journals[i],
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  static double cardWidth(double available) {
    if (available >= 1100) return 340;
    if (available >= 760) return (available - Tokens.s4) / 2;
    return available;
  }
}

/// One journal as a tactile card: accent edge, name, description, metadata.
class JournalCard extends StatelessWidget {
  const JournalCard({super.key, required this.journal});

  final Journal journal;

  @override
  Widget build(BuildContext context) {
    final AppState state = AppScope.of(context);
    final Ink ink = context.ink;
    final Color accent = Color(journal.accent);
    final int count = state.entryCount(journal.id);
    final DateTime? updated = state.lastUpdated(journal.id);
    final bool selected = state.journalId == journal.id;

    final Widget body = Panel(
      raised: selected,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: accent,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: Tokens.s2),
              Expanded(
                child: Text(
                  journal.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.textTheme.headlineSmall,
                ),
              ),
              JournalMenu(journal: journal),
            ],
          ),
          if (journal.description.isNotEmpty) ...<Widget>[
            const SizedBox(height: Tokens.s2),
            Text(
              journal.description,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: context.textTheme.bodyMedium,
            ),
          ],
          const SizedBox(height: Tokens.s4),
          Text(
            '$count ${count == 1 ? 'entry' : 'entries'}'
            '${updated == null ? '' : ' · updated ${relativeTime(updated)}'}',
            style: TextStyle(
              fontFamily: AppFonts.mono,
              fontSize: 11,
              letterSpacing: 0.5,
              color: ink.textFaint,
            ),
          ),
        ],
      ),
    );

    return Semantics(
      button: true,
      label: 'Open journal ${journal.name}',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => state.selectJournal(journal.id),
          child: body,
        ),
      ),
    );
  }
}

/// The create / rename / describe dialog. Also picks the accent colour.
Future<void> showJournalDialog(
  BuildContext context, {
  Journal? existing,
}) {
  return showDialog<void>(
    context: context,
    builder: (BuildContext context) => _JournalDialog(existing: existing),
  );
}

class _JournalDialog extends StatefulWidget {
  const _JournalDialog({this.existing});

  final Journal? existing;

  @override
  State<_JournalDialog> createState() => _JournalDialogState();
}

class _JournalDialogState extends State<_JournalDialog> {
  late final TextEditingController _name = TextEditingController(
    text: widget.existing?.name ?? '',
  );
  late final TextEditingController _description = TextEditingController(
    text: widget.existing?.description ?? '',
  );
  late int _accent = widget.existing?.accent ?? journalAccents[0];

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final String name = _name.text.trim();
    if (name.isEmpty) {
      setState(() {});
      return;
    }
    final AppState state = AppScope.of(context);
    final NavigatorState nav = Navigator.of(context);
    if (widget.existing == null) {
      final Journal created = await state.createJournal(
        name,
        description: _description.text.trim(),
      );
      state.say('Created "${created.name}".');
    } else {
      await state.updateJournal(
        widget.existing!.copyWith(
          name: name,
          description: _description.text.trim(),
          accent: _accent,
        ),
      );
      state.say('Journal updated.');
    }
    nav.pop();
  }

  @override
  Widget build(BuildContext context) {
    final Ink ink = context.ink;
    final bool editing = widget.existing != null;
    final bool invalid = _name.text.trim().isEmpty;
    return AlertDialog(
      title: Text(editing ? 'Edit journal' : 'New journal'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            TextField(
              controller: _name,
              autofocus: true,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(labelText: 'Name'),
              onSubmitted: (_) => _save(),
            ),
            const SizedBox(height: Tokens.s3),
            TextField(
              controller: _description,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Description (optional)',
              ),
            ),
            const SizedBox(height: Tokens.s4),
            Wrap(
              spacing: Tokens.s2,
              children: <Widget>[
                for (final int accent in journalAccents)
                  Semantics(
                    button: true,
                    selected: _accent == accent,
                    label: 'Accent colour',
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: GestureDetector(
                        onTap: () => setState(() => _accent = accent),
                        child: Container(
                          width: 26,
                          height: 26,
                          decoration: BoxDecoration(
                            color: Color(accent),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: _accent == accent
                                  ? ink.text
                                  : ink.lineStrong,
                              width: _accent == accent ? 2.4 : 1,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: invalid ? null : _save,
          child: Text(editing ? 'Save' : 'Create'),
        ),
      ],
    );
  }
}

/// Menu on a journal card: edit details, export, delete (with confirmation).
class JournalMenu extends StatelessWidget {
  const JournalMenu({super.key, required this.journal});

  final Journal journal;

  @override
  Widget build(BuildContext context) {
    final Ink ink = context.ink;
    final AppState state = AppScope.of(context);
    return PopupMenuButton<String>(
      tooltip: 'Journal actions',
      icon: Icon(Icons.more_vert_rounded, size: 18, color: ink.textSoft),
      color: ink.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Tokens.rMd),
        side: BorderSide(color: ink.line),
      ),
      onSelected: (String action) async {
        switch (action) {
          case 'edit':
            await showJournalDialog(context, existing: journal);
          case 'export':
            await exportJournalAsZip(context, journal);
          case 'delete':
            final int count = state.entryCount(journal.id);
            final bool ok = await confirm(
              context,
              title: 'Delete "${journal.name}"?',
              message:
                  'This removes the journal, its $count '
                  '${count == 1 ? 'entry' : 'entries'} and all attached images '
                  'and recordings from this browser. This cannot be undone.',
              confirmLabel: 'Delete journal',
              destructive: true,
            );
            if (!ok) return;
            await state.deleteJournal(journal.id);
            state.say('Deleted "${journal.name}".');
        }
      },
      itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
        const PopupMenuItem<String>(
          value: 'edit',
          height: 42,
          child: Row(
            children: <Widget>[
              Icon(Icons.edit_outlined, size: 16),
              SizedBox(width: Tokens.s3),
              Text('Edit details', style: TextStyle(fontSize: 13.5)),
            ],
          ),
        ),
        const PopupMenuItem<String>(
          value: 'export',
          height: 42,
          child: Row(
            children: <Widget>[
              Icon(Icons.ios_share_rounded, size: 16),
              SizedBox(width: Tokens.s3),
              Text('Export as Markdown', style: TextStyle(fontSize: 13.5)),
            ],
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem<String>(
          value: 'delete',
          height: 42,
          child: Row(
            children: <Widget>[
              Icon(
                Icons.delete_outline_rounded,
                size: 16,
                color: context.ink.danger,
              ),
              const SizedBox(width: Tokens.s3),
              Text(
                'Delete',
                style: TextStyle(fontSize: 13.5, color: context.ink.danger),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The compact journal navigation column of the desktop layout.
class JournalRail extends StatelessWidget {
  const JournalRail({super.key});

  @override
  Widget build(BuildContext context) {
    final AppState state = AppScope.of(context);
    final Ink ink = context.ink;
    final List<Journal> journals = state.journals;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(Tokens.s4, Tokens.s5, Tokens.s3, 0),
          child: SectionLabel(
            'Journals',
            trailing: IconButton(
              tooltip: 'New journal',
              onPressed: () => showJournalDialog(context),
              icon: const Icon(Icons.add_rounded, size: 19),
              visualDensity: VisualDensity.compact,
            ),
          ),
        ),
        Expanded(
          child: journals.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(Tokens.s4),
                  child: Text(
                    'Nothing here yet.',
                    style: TextStyle(fontSize: 12.5, color: ink.textFaint),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(
                    Tokens.s3,
                    Tokens.s1,
                    Tokens.s3,
                    Tokens.s5,
                  ),
                  itemCount: journals.length,
                  itemBuilder: (BuildContext context, int index) {
                    final Journal journal = journals[index];
                    final bool selected = state.journalId == journal.id;
                    return _RailRow(
                      journal: journal,
                      selected: selected,
                      onTap: () => state.selectJournal(journal.id),
                      onEdit: () =>
                          showJournalDialog(context, existing: journal),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _RailRow extends StatelessWidget {
  const _RailRow({
    required this.journal,
    required this.selected,
    required this.onTap,
    required this.onEdit,
  });

  final Journal journal;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final AppState state = AppScope.of(context);
    final Ink ink = context.ink;
    final int count = state.entryCount(journal.id);
    return AppearIn(
      order: 0,
      child: Semantics(
        button: true,
        selected: selected,
        label: 'Open journal ${journal.name}',
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: onTap,
            behavior: HitTestBehavior.opaque,
            child: Container(
              margin: const EdgeInsets.only(bottom: 2),
              padding: const EdgeInsets.symmetric(
                horizontal: Tokens.s3,
                vertical: 9,
              ),
              decoration: BoxDecoration(
                color: selected ? ink.accentWash : Colors.transparent,
                borderRadius: BorderRadius.circular(Tokens.rSm),
                border: Border.all(
                  color: selected ? ink.accent : Colors.transparent,
                ),
              ),
              child: Row(
                children: <Widget>[
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: Color(journal.accent),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: Tokens.s2),
                  Expanded(
                    child: Text(
                      journal.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                        color: selected ? ink.accent : ink.text,
                      ),
                    ),
                  ),
                  Text(
                    '$count',
                    style: TextStyle(
                      fontFamily: AppFonts.mono,
                      fontSize: 10.5,
                      color: ink.textFaint,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Edit journal',
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit_outlined, size: 13),
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.all(6),
                    constraints: const BoxConstraints(
                      minWidth: 24,
                      minHeight: 24,
                    ),
                    style: IconButton.styleFrom(
                      foregroundColor: ink.textFaint,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The entries of the open journal: header, tag filter, "new entry", list.
class EntryListPane extends StatelessWidget {
  const EntryListPane({super.key, this.compact = false});

  /// Narrow screens drop the description to keep rows tight.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final AppState state = AppScope.of(context);
    final Journal? journal = state.currentJournal;
    if (journal == null) {
      return const EmptyState(
        glyph: '⌘',
        title: 'No journal open',
        message: 'Create a journal to start writing.',
      );
    }

    final List<Entry> entries = filteredEntries(state, journal.id);
    final List<String> journalTags = <String>{
      for (final Entry e in state.entriesOf(journal.id)) ...e.tags,
    }.toList()
      ..sort();

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: EdgeInsets.fromLTRB(
                Tokens.s5,
                Tokens.s5,
                Tokens.s5,
                compact ? 0 : Tokens.s2,
              ),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          journal.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.textTheme.headlineMedium,
                        ),
                        if (!compact && journal.description.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: Tokens.s1),
                            child: Text(
                              journal.description,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: context.textTheme.bodyMedium,
                            ),
                          ),
                      ],
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: () => state.createEntry(journal.id),
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('New entry'),
                  ),
                ],
              ),
            ),
            if (journalTags.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Tokens.s5,
                  Tokens.s2,
                  Tokens.s5,
                  Tokens.s3,
                ),
                child: Wrap(
                  spacing: Tokens.s1,
                  runSpacing: Tokens.s1,
                  children: <Widget>[
                    for (final String tag in journalTags)
                      TagPill(
                        tag: tag,
                        selected: state.tagFilter == tag,
                        dense: true,
                        onTap: () => state.setTagFilter(
                          state.tagFilter == tag ? null : tag,
                        ),
                      ),
                  ],
                ),
              ),
            Expanded(
              child: entries.isEmpty
                  ? EmptyState(
                      compact: true,
                      glyph: '✎',
                      title: state.tagFilter == null
                          ? 'No entries yet'
                          : 'No entries with #${state.tagFilter}',
                      message: state.tagFilter == null
                          ? 'Write the first note in this journal — markdown, '
                                'images and voice notes all welcome.'
                          : 'Try a different tag, or clear the filter.',
                      actions: <Widget>[
                        if (state.tagFilter != null)
                          TextButton(
                            onPressed: () => state.setTagFilter(null),
                            child: const Text('Clear tag filter'),
                          )
                        else
                          FilledButton.icon(
                            onPressed: () => state.createEntry(journal.id),
                            icon: const Icon(Icons.add_rounded, size: 18),
                            label: const Text('New entry'),
                          ),
                      ],
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(
                        Tokens.s4,
                        0,
                        Tokens.s4,
                        Tokens.s7,
                      ),
                      itemCount: entries.length,
                      itemBuilder: (BuildContext context, int index) =>
                          AppearIn(
                            order: index.clamp(0, 8),
                            child: EntryTile(entry: entries[index]),
                          ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  /// Entries of one journal, honouring the global tag filter.
  static List<Entry> filteredEntries(AppState state, String journalId) {
    final List<Entry> all = state.entriesOf(journalId);
    final String? tag = state.tagFilter;
    if (tag == null) return all;
    return <Entry>[
      for (final Entry e in all)
        if (e.tags.contains(tag)) e,
    ];
  }
}

/// One entry in a list: title, date, tags, preview, attachment hints.
///
/// Shared by the journal view, the timeline and search results.
class EntryTile extends StatelessWidget {
  const EntryTile({
    super.key,
    required this.entry,
    this.showJournal = false,
  });

  final Entry entry;

  /// Show the owning journal's name — used on timeline and search.
  final bool showJournal;

  @override
  Widget build(BuildContext context) {
    final AppState state = AppScope.of(context);
    final Ink ink = context.ink;
    final Journal? owner = state.journal(entry.journalId);
    final bool selected =
        state.section == Section.journals && state.entryId == entry.id;
    final List<MediaRef> images = <MediaRef>[
      for (final MediaRef m in entry.media)
        if (m.kind == MediaKind.image) m,
    ];
    final List<MediaRef> voices = <MediaRef>[
      for (final MediaRef m in entry.media)
        if (m.kind == MediaKind.voice) m,
    ];

    final Widget tile = Container(
      margin: const EdgeInsets.only(bottom: Tokens.s2),
      decoration: BoxDecoration(
        color: selected ? ink.accentWash : ink.surface,
        borderRadius: BorderRadius.circular(Tokens.rLg),
        border: Border.all(color: selected ? ink.accent : ink.line),
      ),
      child: Padding(
        padding: const EdgeInsets.all(Tokens.s4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (images.isNotEmpty) ...<Widget>[
              SizedBox(
                width: 64,
                height: 64,
                child: MediaImage(
                  path: images.first.path,
                  bytes: state.mediaBytes(images.first.path),
                  radius: Tokens.rSm,
                ),
              ),
              const SizedBox(width: Tokens.s3),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          entry.displayTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: AppFonts.serif,
                            fontSize: 16.5,
                            height: 1.3,
                            fontWeight: FontWeight.w600,
                            color: ink.text,
                          ),
                        ),
                      ),
                      EntryMenu(entry: entry),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    <String>[
                      dateTimeLabel(entry.date),
                      if (showJournal && owner != null) owner.name,
                    ].join('  ·  '),
                    style: TextStyle(
                      fontFamily: AppFonts.mono,
                      fontSize: 10.5,
                      letterSpacing: 0.5,
                      color: ink.textFaint,
                    ),
                  ),
                  if (entry.preview().isNotEmpty) ...<Widget>[
                    const SizedBox(height: Tokens.s2),
                    Text(
                      entry.preview(max: 160),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.5,
                        color: ink.textSoft,
                      ),
                    ),
                  ],
                  if (entry.tags.isNotEmpty || voices.isNotEmpty) ...<Widget>[
                    const SizedBox(height: Tokens.s2),
                    Wrap(
                      spacing: Tokens.s1,
                      runSpacing: Tokens.s1,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: <Widget>[
                        for (final String tag in entry.tags)
                          TagPill(
                            tag: tag,
                            dense: true,
                            onTap: () => state.setTagFilter(tag),
                          ),
                        if (voices.isNotEmpty)
                          Icon(
                            Icons.graphic_eq_rounded,
                            size: 13,
                            color: ink.textFaint,
                          ),
                        if (voices.isNotEmpty)
                          Text(
                            '${voices.length} voice note'
                            '${voices.length == 1 ? '' : 's'}',
                            style: TextStyle(
                              fontFamily: AppFonts.mono,
                              fontSize: 10.5,
                              color: ink.textFaint,
                            ),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );

    return Semantics(
      button: true,
      label: 'Open entry ${entry.displayTitle}',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => state.selectEntry(entry.id),
          child: tile,
        ),
      ),
    );
  }
}
