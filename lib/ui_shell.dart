import 'dart:async';

import 'package:flutter/material.dart' hide Ink;

import 'app_state.dart';
import 'models.dart';
import 'theme.dart';
import 'ui_common.dart';
import 'ui_data.dart';
import 'ui_entry.dart';
import 'ui_journals.dart';
import 'ui_search.dart';
import 'ui_timeline.dart';

/// Root widget: theme, snackbars for [AppState.messages], the shell.
class JournalMdApp extends StatelessWidget {
  const JournalMdApp({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (BuildContext context, _) {
        return MaterialApp(
          title: 'journal.md',
          debugShowCheckedModeBanner: false,
          themeMode: state.themeMode,
          theme: JournalTheme.light(),
          darkTheme: JournalTheme.dark(),
          home: Shell(state: state),
        );
      },
    );
  }
}

/// Responsive app shell.
///
/// Wide: sidebar (identity + sections + journals) → entry list → entry.
/// Narrow: header + bottom tab bar; panes stack full-width.
class Shell extends StatefulWidget {
  const Shell({super.key, required this.state});

  final AppState state;

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  StreamSubscription<String>? _messages;

  @override
  void initState() {
    super.initState();
    _messages = widget.state.messages.listen(
      (String text) => showNotice(context, text),
    );
  }

  @override
  void didUpdateWidget(Shell old) {
    super.didUpdateWidget(old);
    if (old.state != widget.state) {
      _messages?.cancel();
      _messages = widget.state.messages.listen(
        (String text) => showNotice(context, text),
      );
    }
  }

  @override
  void dispose() {
    _messages?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppState state = widget.state;
    final Ink ink = context.ink;

    if (state.loading) {
      return Scaffold(
        backgroundColor: ink.canvas,
        body: const IntroVeil(),
      );
    }

    return Scaffold(
      backgroundColor: ink.canvas,
      body: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints box) {
          final bool wide = box.maxWidth >= 1080;
          final bool medium = box.maxWidth >= 720;
          if (wide) return _wideLayout(context, state, medium);
          return _narrowLayout(context, state, box.maxWidth);
        },
      ),
    );
  }

  // -- Desktop: rail of journals | list | detail --------------------------

  Widget _wideLayout(BuildContext context, AppState state, bool showRail) {
    final Ink ink = context.ink;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _Sidebar(state: state, showJournals: showRail),
        VerticalDivider(width: 1, thickness: 1, color: ink.line),
        Expanded(child: _sectionPane(context, state, compact: false)),
        VerticalDivider(width: 1, thickness: 1, color: ink.line),
        SizedBox(
          width: 460,
          child: _detailPane(context, state),
        ),
      ],
    );
  }

  // -- Tablet / mobile: one pane + top bar + tab bar ----------------------

  Widget _narrowLayout(BuildContext context, AppState state, double width) {
    final bool tabbed = width < 720;
    return Column(
      children: <Widget>[
        _TopBar(state: state),
        Expanded(child: _sectionPane(context, state, compact: true)),
        if (tabbed) _TabBar(state: state),
      ],
    );
  }

  Widget _sectionPane(
    BuildContext context,
    AppState state, {
    required bool compact,
  }) {
    switch (state.section) {
      case Section.journals:
        return PaneSwitch(
          duration: paneSwitchDuration,
          child: state.journalId == null
              ? const JournalsPane()
              : EntryListPane(compact: compact),
        );
      case Section.timeline:
        return PaneSwitch(
          duration: paneSwitchDuration,
          child: const TimelinePane(),
        );
      case Section.search:
        return PaneSwitch(
          duration: paneSwitchDuration,
          child: const SearchPane(),
        );
      case Section.data:
        return PaneSwitch(
          duration: paneSwitchDuration,
          child: const LibraryPane(),
        );
    }
  }

  Widget _detailPane(BuildContext context, AppState state) {
    if (state.section != Section.journals) {
      return const SizedBox.shrink();
    }
    final Entry? entry = state.currentEntry;
    if (entry == null) {
      return const EmptyState(
        glyph: '✎',
        title: 'Nothing open',
        message: 'Pick an entry from the list, or create a new one.',
      );
    }
    return PaneSwitch(
      key: ValueKey<String>(entry.id),
      duration: paneSwitchDuration,
      child: EntryPane(entry: entry),
    );
  }
}

/// One shared duration for pane transitions; zeroed by reduced motion.
const Duration paneSwitchDuration = Duration(milliseconds: 200);

/// The opening moment: a floating journal, the name, then the app fades in.
class IntroVeil extends StatefulWidget {
  const IntroVeil({super.key});

  @override
  State<IntroVeil> createState() => _IntroVeilState();
}

class _IntroVeilState extends State<IntroVeil>
    with SingleTickerProviderStateMixin {
  late final AnimationController _float = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  )..repeat(reverse: true);

  late final Animation<double> _bob = CurvedAnimation(
    parent: _float,
    curve: Curves.easeInOut,
  );

  @override
  void dispose() {
    _float.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Ink ink = context.ink;
    final bool reduced = context.reducedMotion;

    final Widget mark = SizedBox(
      width: 74,
      height: 100,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: ink.surfaceRaised,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: ink.lineStrong),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: ink.canvas.withValues(alpha: 0.9),
              blurRadius: 26,
              offset: const Offset(0, 14),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                width: 22,
                height: 2,
                color: ink.accent,
              ),
              const Spacer(),
              Container(height: 1, color: ink.line),
              const SizedBox(height: 5),
              Container(height: 1, color: ink.line),
              const SizedBox(height: 5),
              FractionallySizedBox(
                widthFactor: 0.6,
                child: Container(height: 1, color: ink.line),
              ),
            ],
          ),
        ),
      ),
    );

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          reduced
              ? mark
              : AnimatedBuilder(
                  animation: _bob,
                  builder: (BuildContext context, _) {
                    return Transform.translate(
                      offset: Offset(0, -8 * _bob.value),
                      child: Transform.rotate(
                        angle: -0.03 + 0.03 * _bob.value,
                        child: mark,
                      ),
                    );
                  },
                ),
          const SizedBox(height: Tokens.s5),
          Text(
            'journal.md',
            style: TextStyle(
              fontFamily: AppFonts.serif,
              fontSize: 24,
              letterSpacing: -0.4,
              color: ink.text,
            ),
          ),
          const SizedBox(height: Tokens.s1),
          Text(
            'a quiet place for work in progress',
            style: TextStyle(
              fontFamily: AppFonts.mono,
              fontSize: 11,
              letterSpacing: 0.8,
              color: ink.textFaint,
            ),
          ),
        ],
      ),
    );
  }
}

/// Quiet in-app notice. Auto-dismisses; errors stay a little longer.
void showNotice(BuildContext context, String text) {
  final bool negative =
      text.toLowerCase().contains('could not') ||
      text.toLowerCase().contains('failed') ||
      text.toLowerCase().contains('error');
  ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(
      SnackBar(
        content: Text(text, style: const TextStyle(fontSize: 13, height: 1.4)),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: negative ? 6 : 3),
      ),
    );
}

/// Left column on desktop: identity, sections, journals, theme toggle.
class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.state, required this.showJournals});

  final AppState state;
  final bool showJournals;

  @override
  Widget build(BuildContext context) {
    final Ink ink = context.ink;
    return SizedBox(
      width: showJournals ? 236 : 210,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Tokens.s4,
              Tokens.s4,
              Tokens.s3,
              Tokens.s3,
            ),
            child: Row(
              children: <Widget>[
                Container(
                  width: 26,
                  height: 26,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: ink.surfaceRaised,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: ink.lineStrong),
                  ),
                  child: Text(
                    'j',
                    style: TextStyle(
                      fontFamily: AppFonts.serif,
                      fontSize: 15,
                      height: 1,
                      color: ink.accent,
                    ),
                  ),
                ),
                const SizedBox(width: Tokens.s2),
                Expanded(
                  child: Text(
                    'journal.md',
                    style: TextStyle(
                      fontFamily: AppFonts.serif,
                      fontSize: 15.5,
                      fontWeight: FontWeight.w600,
                      color: ink.text,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: state.themeMode == ThemeMode.dark
                      ? 'Switch to light'
                      : 'Switch to dark',
                  onPressed: () => state.setThemeMode(
                    state.themeMode == ThemeMode.dark
                        ? ThemeMode.light
                        : ThemeMode.dark,
                  ),
                  icon: Icon(
                    state.themeMode == ThemeMode.dark
                        ? Icons.light_mode_outlined
                        : Icons.dark_mode_outlined,
                    size: 17,
                  ),
                  visualDensity: VisualDensity.compact,
                  style: IconButton.styleFrom(foregroundColor: ink.textSoft),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Tokens.s3),
            child: Column(
              children: <Widget>[
                for (final Section section in Section.values)
                  _SectionRow(section: section),
              ],
            ),
          ),
          if (showJournals) ...<Widget>[
            const Divider(height: 24, color: Colors.transparent),
            const Expanded(child: JournalRail()),
          ],
        ],
      ),
    );
  }
}

class _SectionRow extends StatelessWidget {
  const _SectionRow({required this.section});

  final Section section;

  @override
  Widget build(BuildContext context) {
    final AppState state = AppScope.of(context);
    final Ink ink = context.ink;
    final bool selected = state.section == section;
    final IconData icon = switch (section) {
      Section.journals => Icons.menu_book_outlined,
      Section.timeline => Icons.timeline_outlined,
      Section.search => Icons.search_rounded,
      Section.data => Icons.folder_zip_outlined,
    };
    return Semantics(
      button: true,
      selected: selected,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => state.goTo(section),
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: Tokens.s3,
              vertical: 8,
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
                Icon(
                  icon,
                  size: 16,
                  color: selected ? ink.accent : ink.textSoft,
                ),
                const SizedBox(width: Tokens.s2),
                Expanded(
                  child: Text(
                    section.label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                      color: selected ? ink.accent : ink.textSoft,
                    ),
                  ),
                ),
                if (section == Section.search && state.tagFilter != null)
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: ink.accent,
                      shape: BoxShape.circle,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
/// Top bar for narrow layouts: identity, section tabs, theme.
class _TopBar extends StatelessWidget {
  const _TopBar({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final Ink ink = context.ink;
    return Container(
      decoration: BoxDecoration(
        color: ink.surface,
        border: Border(bottom: BorderSide(color: ink.line)),
      ),
      padding: const EdgeInsets.fromLTRB(Tokens.s4, Tokens.s2, Tokens.s2, Tokens.s2),
      child: Row(
        children: <Widget>[
          Text(
            'journal.md',
            style: TextStyle(
              fontFamily: AppFonts.serif,
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: ink.text,
            ),
          ),
          const Spacer(),
          IconButton(
            tooltip: state.themeMode == ThemeMode.dark
                ? 'Switch to light'
                : 'Switch to dark',
            onPressed: () => state.setThemeMode(
              state.themeMode == ThemeMode.dark
                  ? ThemeMode.light
                  : ThemeMode.dark,
            ),
            icon: Icon(
              state.themeMode == ThemeMode.dark
                  ? Icons.light_mode_outlined
                  : Icons.dark_mode_outlined,
              size: 18,
            ),
            style: IconButton.styleFrom(foregroundColor: ink.textSoft),
          ),
        ],
      ),
    );
  }
}

/// Bottom tab bar for phones.
class _TabBar extends StatelessWidget {
  const _TabBar({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final Ink ink = context.ink;
    return Container(
      decoration: BoxDecoration(
        color: ink.surface,
        border: Border(top: BorderSide(color: ink.line)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: <Widget>[
            for (final Section section in Section.values)
              Expanded(child: _Tab(state: state, section: section)),
          ],
        ),
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({required this.state, required this.section});

  final AppState state;
  final Section section;

  @override
  Widget build(BuildContext context) {
    final Ink ink = context.ink;
    final bool selected = state.section == section;
    final IconData icon = switch (section) {
      Section.journals => Icons.menu_book_outlined,
      Section.timeline => Icons.timeline_outlined,
      Section.search => Icons.search_rounded,
      Section.data => Icons.folder_zip_outlined,
    };
    return Semantics(
      button: true,
      selected: selected,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => state.goTo(section),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(
                  icon,
                  size: 20,
                  color: selected ? ink.accent : ink.textSoft,
                ),
                const SizedBox(height: 2),
                Text(
                  section.label,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    color: selected ? ink.accent : ink.textSoft,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
