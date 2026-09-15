import 'package:flutter/material.dart' hide Ink;

import 'app_state.dart';
import 'models.dart';
import 'theme.dart';
import 'ui_common.dart';
import 'ui_journals.dart';

/// Every entry, everywhere, in chronological order — grouped by day.
class TimelinePane extends StatelessWidget {
  const TimelinePane({super.key});

  @override
  Widget build(BuildContext context) {
    final AppState state = AppScope.of(context);
    final String? tag = state.tagFilter;
    final List<Entry> entries = tag == null
        ? state.allEntries
        : <Entry>[
            for (final Entry e in state.allEntries)
              if (e.tags.contains(tag)) e,
          ];

    if (entries.isEmpty) {
      return EmptyState(
        glyph: '⌛',
        title: tag == null ? 'Nothing written yet' : 'Nothing tagged #$tag',
        message: tag == null
            ? 'The timeline fills as you write — a running record of your '
                  'work, newest first.'
            : 'Clear the tag filter to see the full timeline.',
        actions: <Widget>[
          if (tag != null)
            TextButton(
              onPressed: () => state.setTagFilter(null),
              child: const Text('Clear tag filter'),
            ),
        ],
      );
    }

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: ListView.builder(
          padding: const EdgeInsets.fromLTRB(Tokens.s4, Tokens.s5, Tokens.s4, Tokens.s7),
          itemCount: entries.length + 1,
          itemBuilder: (BuildContext context, int index) {
            if (index == 0) return _TimelineHead(count: entries.length, tag: tag);
            final Entry entry = entries[index - 1];
            final Entry? previous = index >= 2 ? entries[index - 2] : null;
            final bool newDay =
                previous == null || !_sameDay(entry.date, previous.date);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                if (newDay)
                  _DayLabel(
                    date: entry.date,
                    first: index == 1,
                  ),
                AppearIn(
                  order: index.clamp(0, 8),
                  child: EntryTile(entry: entry, showJournal: true),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

class _TimelineHead extends StatelessWidget {
  const _TimelineHead({required this.count, required this.tag});

  final int count;
  final String? tag;

  @override
  Widget build(BuildContext context) {
    final Ink ink = context.ink;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Tokens.s1, 0, Tokens.s1, Tokens.s4),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              'Timeline',
              style: context.textTheme.displaySmall,
            ),
          ),
          Text(
            tag == null ? '$count entries' : '#$tag · $count entries',
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
  }
}

/// A date divider in the stream — quiet, mono, literary.
class _DayLabel extends StatelessWidget {
  const _DayLabel({required this.date, required this.first});

  final DateTime date;
  final bool first;

  @override
  Widget build(BuildContext context) {
    final Ink ink = context.ink;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        Tokens.s1,
        first ? 0 : Tokens.s5,
        Tokens.s1,
        Tokens.s2,
      ),
      child: Row(
        children: <Widget>[
          Text(
            _dayHeading(date),
            style: TextStyle(
              fontFamily: AppFonts.mono,
              fontSize: 11,
              letterSpacing: 1.2,
              color: ink.textFaint,
            ),
          ),
          const SizedBox(width: Tokens.s3),
          Expanded(child: Divider(height: 1, color: ink.line)),
        ],
      ),
    );
  }
}

const List<String> _weekdays = <String>[
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

String _dayHeading(DateTime d) =>
    '${_weekdays[d.weekday - 1]} · ${shortDate(d)}';
