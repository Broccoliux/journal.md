/// journal.md — app shell and entry point.
///
/// One responsive shell (no separate mobile/desktop implementations):
/// a persistent sidebar on wide screens, a navigation bar on narrow ones.
/// The same page widgets fill the main area either way. Location (section +
/// journal + open entry) is persisted so a reload returns you where you were.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import 'editor.dart';
import 'format_util.dart';
import 'import_export.dart';
import 'models.dart';
import 'pages.dart';
import 'store.dart';
import 'theme.dart';
import 'web_ext.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final store = Store();
  unawaited(store.open());
  // Flush pending autosaves the moment the tab is hidden.
  onTabHidden(() => unawaited(store.flush()));
  runApp(JournalApp(store: store));
}

class JournalApp extends StatelessWidget {
  const JournalApp({super.key, required this.store});

  final Store store;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        return MaterialApp(
          title: 'journal.md',
          debugShowCheckedModeBanner: false,
          themeMode: store.themeMode,
          theme: buildTheme(Brightness.light),
          darkTheme: buildTheme(Brightness.dark),
          home: HomeShell(store: store),
        );
      },
    );
  }
}

// --------------------------------------------------------------------- shell

class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.store});

  final Store store;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  static const _validSections = {'journals', 'timeline', 'search', 'tags', 'journal'};

  String _section = 'journals';
  String? _journalId;
  String? _entryId;
  bool _restored = false;

  Store get _store => widget.store;

  @override
  void initState() {
    super.initState();
    _store.addListener(_onStoreChanged);
  }

  @override
  void dispose() {
    _store.removeListener(_onStoreChanged);
    super.dispose();
  }

  /// Once the store is open, restore the last location.
  void _onStoreChanged() {
    if (_restored || !_store.ready) return;
    _restored = true;

    final ui = _store.readUi();
    if (ui == null) return;
    var section = ui.section;
    var journalId = ui.journalId;
    var entryId = ui.entryId;

    if (!_validSections.contains(section)) section = 'journals';
    if (section == 'journal' &&
        (journalId == null || _store.journal(journalId) == null)) {
      section = 'journals';
      journalId = null;
    }
    if (entryId != null && _store.entry(entryId) == null) entryId = null;

    if (mounted) {
      setState(() {
        _section = section;
        _journalId = journalId;
        _entryId = entryId;
      });
    } else {
      _section = section;
      _journalId = journalId;
      _entryId = entryId;
    }
  }

  // ------------------------------------------------------------ navigation

  void _go(String section, {String? journalId}) {
    setState(() {
      _section = section;
      _journalId =
          journalId ?? (section == 'journal' ? _journalId : null);
      _entryId = null;
    });
    unawaited(
      _store.saveUi(section: _section, journalId: _journalId, entryId: null),
    );
  }

  void _openJournal(String id) => _go('journal', journalId: id);

  void _openEntry(String id) {
    final entry = _store.entry(id);
    setState(() {
      _entryId = id;
      if (entry != null) _journalId = entry.journalId;
    });
    unawaited(
      _store.saveUi(section: _section, journalId: _journalId, entryId: id),
    );
  }

  void _closeEntry() {
    setState(() => _entryId = null);
    unawaited(
      _store.saveUi(section: _section, journalId: _journalId, entryId: null),
    );
  }

  // ----------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _store,
      builder: (context, _) {
        if (!_store.ready) {
          if (_store.loadError != null) {
            return _LoadErrorScreen(store: _store);
          }
          return const _Splash();
        }

        return LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 880;
            if (wide) {
              return Scaffold(
                body: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: 272,
                      child: _Sidebar(
                        store: _store,
                        section: _section,
                        journalId: _journalId,
                        onNavigate: _go,
                        onOpenJournal: _openJournal,
                      ),
                    ),
                    VerticalDivider(
                      width: 1,
                      thickness: 1,
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                    Expanded(child: _mainArea(context)),
                  ],
                ),
              );
            }

            final scheme = Theme.of(context).colorScheme;
            final journal = _journalId == null
                ? null
                : _store.journal(_journalId!);
            return Scaffold(
              appBar: AppBar(
                automaticallyImplyLeading: false,
                leading: _section == 'journal' && _entryId == null
                    ? IconButton(
                        tooltip: 'Back to journals',
                        icon: const Icon(Icons.arrow_back),
                        onPressed: () => _go('journals'),
                      )
                    : null,
                title: Text(
                  _entryId != null ? 'Entry' : (journal?.name ?? 'journal.md'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Lora',
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurface,
                  ),
                ),
                actions: [
                  const SizedBox(width: 4),
                  _SaveState(store: _store, compact: true),
                  IconButton(
                    tooltip: 'Theme: ${_themeLabel(_store.themeMode)}',
                    icon: Icon(_themeIcon(_store.themeMode)),
                    onPressed: () =>
                        unawaited(_store.setThemeMode(_nextTheme(_store.themeMode))),
                  ),
                  PopupMenuButton<String>(
                    tooltip: 'Backups',
                    icon: const Icon(Icons.more_vert),
                    onSelected: (value) {
                      if (value == 'export') {
                        unawaited(runExport(context, _store));
                      } else if (value == 'import') {
                        unawaited(runImport(context, _store));
                      }
                    },
                    itemBuilder: (context) => const [
                      PopupMenuItem(
                        value: 'export',
                        child: ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.file_download),
                          title: Text('Export backup'),
                        ),
                      ),
                      PopupMenuItem(
                        value: 'import',
                        child: ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.upload_file),
                          title: Text('Import backup'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              bottomNavigationBar: _entryId == null
                  ? NavigationBar(
                      selectedIndex: switch (_section) {
                        'timeline' => 1,
                        'search' => 2,
                        'tags' => 3,
                        _ => 0,
                      },
                      onDestinationSelected: (i) => _go(
                        const ['journals', 'timeline', 'search', 'tags'][i],
                      ),
                      destinations: const [
                        NavigationDestination(
                          icon: Icon(Icons.book_outlined),
                          selectedIcon: Icon(Icons.book),
                          label: 'Journals',
                        ),
                        NavigationDestination(
                          icon: Icon(Icons.timeline_outlined),
                          selectedIcon: Icon(Icons.timeline),
                          label: 'Timeline',
                        ),
                        NavigationDestination(
                          icon: Icon(Icons.search),
                          selectedIcon: Icon(Icons.search),
                          label: 'Search',
                        ),
                        NavigationDestination(
                          icon: Icon(Icons.tag),
                          selectedIcon: Icon(Icons.tag),
                          label: 'Tags',
                        ),
                      ],
                    )
                  : null,
              body: _mainArea(context),
            );
          },
        );
      },
    );
  }

  Widget _mainArea(BuildContext context) {
    if (_entryId != null) {
      final entry = _store.entry(_entryId!);
      if (entry != null) {
        return EntryEditor(
          store: _store,
          entryId: _entryId!,
          onClose: _closeEntry,
        );
      }
    }

    final Widget page;
    switch (_section) {
      case 'journal':
        page = JournalView(
          store: _store,
          journalId: _journalId ?? '',
          onOpenEntry: _openEntry,
        );
      case 'timeline':
        page = TimelinePage(store: _store, onOpenEntry: _openEntry);
      case 'search':
        page = SearchPage(
          store: _store,
          onOpenJournal: _openJournal,
          onOpenEntry: _openEntry,
        );
      case 'tags':
        page = TagsPage(store: _store, onOpenEntry: _openEntry);
      default:
        page = JournalsPage(store: _store, onOpenJournal: _openJournal);
    }

    if (_store.loadError != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _DataWarning(message: _store.loadError!),
          Expanded(child: page),
        ],
      );
    }
    return page;
  }
}

// ------------------------------------------------------------------- splash

/// A quiet splash matching the HTML boot splash: the word, a thin rule.
class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final word = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'journal.md',
          style: TextStyle(
            fontFamily: 'Lora',
            fontSize: 30,
            fontWeight: FontWeight.w600,
            color: scheme.onSurface,
          ),
        ),
        const SizedBox(height: 18),
        Container(width: 44, height: 1, color: scheme.outline),
      ],
    );

    if (prefersReducedMotion()) {
      return Scaffold(body: Center(child: word));
    }
    return Scaffold(
      body: Center(
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 450),
          curve: Curves.easeOut,
          builder: (context, opacity, child) =>
              Opacity(opacity: opacity, child: child),
          child: word,
        ),
      ),
    );
  }
}

/// Shown when local storage cannot be opened at all.
class _LoadErrorScreen extends StatelessWidget {
  const _LoadErrorScreen({required this.store});

  final Store store;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.error_outline, size: 30, color: scheme.error),
                const SizedBox(height: 14),
                Text(
                  'Your journal could not be opened',
                  style: TextStyle(
                    fontFamily: 'Lora',
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurface,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'This browser blocked access to local storage (it may be '
                  'full, disabled, or in a private window). Your data is not '
                  'lost — try another browser or adjust the setting.',
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.6,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 18),
                OutlinedButton.icon(
                  onPressed: () => unawaited(store.open()),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Try again'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Thin notice when saved data could not be decoded (app still runs).
class _DataWarning extends StatelessWidget {
  const _DataWarning({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
        color: scheme.surfaceContainerLow,
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_outlined, size: 16, color: scheme.error),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Saved data could not be read — starting empty. $message',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'RobotoMono',
                fontSize: 11.5,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------ sidebar

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.store,
    required this.section,
    required this.journalId,
    required this.onNavigate,
    required this.onOpenJournal,
  });

  final Store store;
  final String section;
  final String? journalId;
  final ValueChanged<String> onNavigate;
  final ValueChanged<String> onOpenJournal;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final label = TextStyle(
      fontFamily: 'RobotoMono',
      fontSize: 9.5,
      letterSpacing: 1.4,
      color: scheme.onSurfaceVariant,
    );

    final recent = List.of(store.journals)
      ..sort((a, b) => store.lastActivity(b.id).compareTo(store.lastActivity(a.id)));

    return Material(
      color: scheme.surfaceContainerLow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 26, 24, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'journal.md',
                  style: TextStyle(
                    fontFamily: 'Lora',
                    fontSize: 21,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Text('LOCAL-FIRST · OFFLINE', style: label),
              ],
            ),
          ),

          // Primary navigation.
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _NavItem(
                  icon: Icons.book_outlined,
                  label: 'Journals',
                  selected: section == 'journals' || section == 'journal',
                  onTap: () => onNavigate('journals'),
                ),
                const SizedBox(height: 2),
                _NavItem(
                  icon: Icons.timeline_outlined,
                  label: 'Timeline',
                  selected: section == 'timeline',
                  onTap: () => onNavigate('timeline'),
                ),
                const SizedBox(height: 2),
                _NavItem(
                  icon: Icons.search,
                  label: 'Search',
                  selected: section == 'search',
                  onTap: () => onNavigate('search'),
                ),
                const SizedBox(height: 2),
                _NavItem(
                  icon: Icons.tag,
                  label: 'Tags',
                  selected: section == 'tags',
                  onTap: () => onNavigate('tags'),
                ),
              ],
            ),
          ),

          // Quick access to journals.
          if (recent.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 6),
              child: Text('NOTEBOOKS', style: label),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                children: [
                  for (final j in recent.take(8))
                    _JournalLink(
                      journal: j,
                      count: store.entryCount(j.id),
                      selected: j.id == journalId,
                      onTap: () => onOpenJournal(j.id),
                    ),
                ],
              ),
            ),
          ] else ...[
            const Spacer(),
          ],

          // Bottom bar: save state + actions.
          Divider(height: 1, thickness: 1, color: scheme.outlineVariant),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
            child: _SaveState(store: store),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 6),
            child: Row(
              children: [
                IconButton(
                  tooltip: 'Theme: ${_themeLabel(store.themeMode)}',
                  icon: Icon(_themeIcon(store.themeMode)),
                  onPressed: () =>
                      unawaited(store.setThemeMode(_nextTheme(store.themeMode))),
                ),
                IconButton(
                  tooltip: 'Import backup',
                  icon: const Icon(Icons.upload_file),
                  onPressed: () => unawaited(runImport(context, store)),
                ),
                IconButton(
                  tooltip: 'Export backup',
                  icon: const Icon(Icons.file_download),
                  onPressed: () => unawaited(runExport(context, store)),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
            child: Text(
              'Everything stays in this browser.',
              style: label.copyWith(fontSize: 9),
            ),
          ),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? scheme.surface : null,
          borderRadius: BorderRadius.circular(8),
          border: selected ? Border.all(color: scheme.outlineVariant) : null,
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 19,
              color: selected ? scheme.onSurface : scheme.onSurfaceVariant,
            ),
            const SizedBox(width: 12),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                color: selected ? scheme.onSurface : scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _JournalLink extends StatelessWidget {
  const _JournalLink({
    required this.journal,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final Journal journal;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
        child: Row(
          children: [
            Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected ? scheme.secondary : Colors.transparent,
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                journal.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  color: selected ? scheme.onSurface : scheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '$count',
              style: TextStyle(
                fontFamily: 'RobotoMono',
                fontSize: 11,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Quiet save-state indicator: a dot and a mono label.
class _SaveState extends StatelessWidget {
  const _SaveState({required this.store, this.compact = false});

  final Store store;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    final Color dot;
    final String label;
    switch (store.saveState) {
      case SaveState.pending:
      case SaveState.saving:
        dot = scheme.onSurfaceVariant;
        label = 'Saving…';
      case SaveState.error:
        dot = scheme.error;
        label = 'Save failed';
      case SaveState.clean:
        dot = scheme.secondary;
        label = store.lastSavedAt == null
            ? 'All changes saved'
            : 'Saved ${formatTime(store.lastSavedAt!.millisecondsSinceEpoch)}';
    }

    if (compact) {
      return Tooltip(
        message: label,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(shape: BoxShape.circle, color: dot),
          ),
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(shape: BoxShape.circle, color: dot),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            fontFamily: 'RobotoMono',
            fontSize: 11,
            color: scheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

// ------------------------------------------------------------ theme cycling

String _themeLabel(ThemeMode mode) => switch (mode) {
      ThemeMode.system => 'system',
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
    };

IconData _themeIcon(ThemeMode mode) => switch (mode) {
      ThemeMode.system => Icons.brightness_auto,
      ThemeMode.light => Icons.light_mode,
      ThemeMode.dark => Icons.dark_mode,
    };

ThemeMode _nextTheme(ThemeMode mode) => switch (mode) {
      ThemeMode.system => ThemeMode.light,
      ThemeMode.light => ThemeMode.dark,
      ThemeMode.dark => ThemeMode.system,
    };
