import 'package:flutter/material.dart' hide Ink;

import 'app_state.dart';
import 'models.dart';
import 'portable.dart';
import 'theme.dart';
import 'ui_common.dart';
import 'web_io.dart';
import 'zip.dart';

/// Exports one journal as a portable folder, packed into a `.zip` download.
///
/// The folder itself is plain Markdown with relative asset paths; the archive
/// is only how a browser moves a folder in one file.
Future<void> exportJournalAsZip(
  BuildContext context,
  Journal journal, {
  AppState? state,
}) async {
  final AppState app = state ?? AppScope.of(context);
  try {
    final Bundle? bundle = await app.buildExport(journal.id);
    if (bundle == null) {
      app.say('That journal no longer exists.');
      return;
    }
    downloadBytes(
      fileName: '${bundle.folder}.zip',
      bytes: encodeBundle(bundle),
      mime: 'application/zip',
    );
    app.say(
      'Exported "${journal.name}" — ${bundle.files.length} files, '
      'readable in any Markdown tool.',
    );
  } catch (error) {
    app.say('Could not export this journal: $error');
  }
}

/// Asks the user for a portable file (`.zip` or `.md`) and imports it.
///
/// Both shapes are accepted because both are produced by the app: a zip is
/// the normal download, a single `.md` covers journals exported as one file
/// or hand-written markdown dropped into journal.md.
Future<void> importPortableFile(BuildContext context) async {
  final AppState state = AppScope.of(context);
  final List<PickedFile> files;
  try {
    files = await pickFiles(
      accept: '.zip,.md,.markdown,text/markdown',
      multiple: false,
    );
  } catch (_) {
    state.say('File picking is not available in this browser.');
    return;
  }
  if (files.isEmpty || !context.mounted) return;
  final PickedFile file = files.first;

  try {
    final Bundle bundle;
    if (file.name.toLowerCase().endsWith('.zip')) {
      bundle = decodeArchive(archiveName: file.name, bytes: file.bytes);
    } else {
      final String base = file.name
          .split('/')
          .last
          .split('\\')
          .last
          .replaceFirst(RegExp(r'\.(md|markdown)$', caseSensitive: false), '');
      bundle = Bundle(
        folder: base.isEmpty ? 'imported-journal' : base,
        files: <String, List<int>>{'journal/${file.name}': file.bytes},
      );
    }

    final ImportResult result = await state.importPortable(
      bundle,
      fallbackName: file.name,
    );
    if (!context.mounted) return;
    if (result.isEmpty) {
      state.say(
        'That file contained no entries. Was it exported from journal.md?',
      );
      return;
    }
    final String warnings = result.warnings.isEmpty
        ? ''
        : ' ${result.warnings.length} file(s) were skipped.';
    state.say(
      'Imported "${result.journal.name}" — ${result.entries.length} '
      'entries.$warnings',
    );
  } on FormatException catch (error) {
    state.say(error.message);
  } catch (error) {
    state.say('Could not import that file: $error');
  }
}

/// The Library pane: export everything, import back, and the whole-data
/// controls that belong to the user rather than to one journal.
class LibraryPane extends StatelessWidget {
  const LibraryPane({super.key});

  @override
  Widget build(BuildContext context) {
    final AppState state = AppScope.of(context);
    int images = 0;
    int voices = 0;
    for (final Entry entry in state.allEntries) {
      for (final MediaRef ref in entry.media) {
        if (ref.kind == MediaKind.image) {
          images++;
        } else {
          voices++;
        }
      }
    }
    final int entries = state.allEntries.length;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(Tokens.s6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text('Library', style: context.textTheme.displaySmall),
              const SizedBox(height: Tokens.s2),
              Text(
                'Your journals are plain files at heart. Export them as '
                'Markdown folders, read them in any editor, and bring them '
                'back anytime.',
                style: context.textTheme.bodyMedium,
              ),
              const SizedBox(height: Tokens.s5),
              AppearIn(
                order: 0,
                child: _ExportCard(onExportAll: () => _exportAll(context), state: state),
              ),
              const SizedBox(height: Tokens.s4),
              AppearIn(
                order: 1,
                child: Panel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text('Import', style: context.textTheme.titleMedium),
                      const SizedBox(height: Tokens.s2),
                      Text(
                        'Bring back an archive exported from journal.md, or '
                        'drop in any Markdown file. Import always creates a '
                        'new journal — your existing data is never overwritten.',
                        style: context.textTheme.bodyMedium,
                      ),
                      const SizedBox(height: Tokens.s4),
                      FilledButton.tonalIcon(
                        onPressed: () => importPortableFile(context),
                        icon: const Icon(Icons.file_open_outlined, size: 17),
                        label: const Text('Import .zip or .md'),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: Tokens.s4),
              AppearIn(
                order: 2,
                child: Panel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text('This browser', style: context.textTheme.titleMedium),
                      const SizedBox(height: Tokens.s2),
                      Text(
                        '${state.journals.length} journals · $entries entries · '
                        '$images images · $voices recordings. Everything lives '
                        'in this browser’s local storage — nothing is sent '
                        'anywhere.',
                        style: context.textTheme.bodyMedium,
                      ),
                      const SizedBox(height: Tokens.s4),
                      Wrap(
                        spacing: Tokens.s2,
                        runSpacing: Tokens.s2,
                        children: <Widget>[
                          OutlinedButton(
                            onPressed: () => _confirmReset(context),
                            child: const Text('Erase all local data'),
                          ),
                        ],
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

  Future<void> _exportAll(BuildContext context) async {
    final AppState state = AppScope.of(context);
    try {
      state.say('Packing everything…');
      final Bundle bundle = await state.buildExportAll();
      if (bundle.files.isEmpty) {
        state.say('There is nothing to export yet — write something first.');
        return;
      }
      downloadBytes(
        fileName: 'journal-md-export.zip',
        bytes: encodeBundle(bundle),
        mime: 'application/zip',
      );
      state.say(
        'Exported ${bundle.files.length} files. Import them back into any '
        'journal.md to restore.',
      );
    } catch (error) {
      state.say('Could not export: $error');
    }
  }

  Future<void> _confirmReset(BuildContext context) async {
    final AppState state = AppScope.of(context);
    final bool ok = await confirm(
      context,
      title: 'Erase all local data?',
      message:
          'Every journal, entry, image and recording in this browser will be '
          'deleted. Export first if you want to keep anything.',
      confirmLabel: 'Erase everything',
      destructive: true,
    );
    if (!ok) return;
    await state.eraseEverything();
    state.say('All local data erased.');
  }
}

/// The export card: journals listed with their sizes, one big button.
class _ExportCard extends StatelessWidget {
  const _ExportCard({required this.onExportAll, required this.state});

  final VoidCallback onExportAll;
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final List<Journal> journals = state.journals;
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('Export', style: context.textTheme.titleMedium),
          const SizedBox(height: Tokens.s2),
          Text(
            'Everything, packed as one archive of Markdown folders — one '
            'folder per journal, assets beside the entries that use them.',
            style: context.textTheme.bodyMedium,
          ),
          const SizedBox(height: Tokens.s4),
          Wrap(
            spacing: Tokens.s2,
            runSpacing: Tokens.s2,
            children: <Widget>[
              FilledButton.icon(
                onPressed: journals.isEmpty ? null : onExportAll,
                icon: const Icon(Icons.ios_share_rounded, size: 17),
                label: const Text('Export everything (.zip)'),
              ),
            ],
          ),
          if (journals.isNotEmpty) ...<Widget>[
            const SizedBox(height: Tokens.s3),
            Wrap(
              spacing: Tokens.s1,
              runSpacing: Tokens.s1,
              children: <Widget>[
                for (final Journal journal in journals)
                  FilterChip(
                    label: Text(journal.name),
                    onSelected: (_) =>
                        exportJournalAsZip(context, journal, state: state),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
