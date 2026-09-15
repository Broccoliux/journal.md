import 'dart:async';

import 'package:flutter/material.dart' hide Ink;

import 'app_state.dart';
import 'models.dart';
import 'theme.dart';
import 'ui_common.dart';
import 'ui_journals.dart';

/// Global search: journal names, entry titles, content and tags.
///
/// The query lives here, not in [AppState] — results are derived on demand,
/// debounced so typing stays smooth.
class SearchPane extends StatefulWidget {
  const SearchPane({super.key});

  @override
  State<SearchPane> createState() => _SearchPaneState();
}

class _SearchPaneState extends State<SearchPane> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focus = FocusNode();
  Timer? _debounce;
  String _query = '';

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 120), () {
      if (mounted) setState(() => _query = value.trim());
    });
  }

  @override
  Widget build(BuildContext context) {
    final AppState state = AppScope.of(context);
    final Ink ink = context.ink;
    final List<SearchHit> hits = _query.isEmpty
        ? const <SearchHit>[]
        : state.search(_query);

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Tokens.s5,
                Tokens.s5,
                Tokens.s5,
                Tokens.s2,
              ),
              child: TextField(
                controller: _controller,
                focusNode: _focus,
                autofocus: true,
                onChanged: _onChanged,
                textInputAction: TextInputAction.search,
                style: TextStyle(
                  fontFamily: AppFonts.serif,
                  fontSize: 17,
                  color: ink.text,
                ),
                decoration: InputDecoration(
                  hintText:
                      'Search titles, text, tags, journals…',
                  prefixIcon: Icon(
                    Icons.search_rounded,
                    size: 19,
                    color: ink.textFaint,
                  ),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Clear',
                          icon: const Icon(Icons.close_rounded, size: 16),
                          onPressed: () {
                            _controller.clear();
                            setState(() => _query = '');
                            _focus.requestFocus();
                          },
                        ),
                ),
              ),
            ),
            if (state.tagFilter != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(Tokens.s5, 0, Tokens.s5, Tokens.s2),
                child: Wrap(
                  spacing: Tokens.s1,
                  children: <Widget>[
                    Text(
                      'Tag filter:',
                      style: TextStyle(fontSize: 12, color: ink.textFaint),
                    ),
                    TagPill(
                      tag: state.tagFilter!,
                      dense: true,
                      selected: true,
                      onTap: () => state.setTagFilter(null),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: _query.isEmpty
                  ? _IdleSearch(state: state)
                  : hits.isEmpty
                      ? EmptyState(
                          compact: true,
                          glyph: '∅',
                          title: 'No matches',
                          message:
                              'Nothing matched “$_query”. Try fewer words, or '
                              'search by a tag like #ai.',
                        )
                      : _ResultList(query: _query, hits: hits),
            ),
          ],
        ),
      ),
    );
  }
}

/// Before typing: popular tags and a hint, so the pane is never blank.
class _IdleSearch extends StatelessWidget {
  const _IdleSearch({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final Ink ink = context.ink;
    final List<String> tags = state.tags;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        Tokens.s5,
        Tokens.s2,
        Tokens.s5,
        Tokens.s5,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            _hint(state),
            style: TextStyle(fontSize: 13, height: 1.6, color: ink.textSoft),
          ),
          if (tags.isNotEmpty) ...<Widget>[
            const SizedBox(height: Tokens.s4),
            const SectionLabel('Tags', padding: EdgeInsets.zero),
            const SizedBox(height: Tokens.s2),
            Wrap(
              spacing: Tokens.s1,
              runSpacing: Tokens.s1,
              children: <Widget>[
                for (final String tag in tags)
                  TagPill(
                    tag: tag,
                    dense: true,
                    onTap: () => state.setTagFilter(tag),
                  ),
              ],
            ),
          ],
          if (state.tagFilter != null) ...<Widget>[
            const SizedBox(height: Tokens.s4),
            TextButton(
              onPressed: () => state.setTagFilter(null),
              child: Text('Clear filter #${state.tagFilter}'),
            ),
          ],
        ],
      ),
    );
  }

  static String _hint(AppState state) {
    final int entries = state.allEntries.length;
    if (entries == 0) {
      return 'Search looks through every journal you write. '
          'There is nothing to search yet — create an entry first.';
    }
    return 'Search runs through $entries entries — titles, full text, tags '
        'and journal names. Results open directly.';
  }
}

/// Ranked results with the matched field called out.
class _ResultList extends StatelessWidget {
  const _ResultList({required this.query, required this.hits});

  final String query;
  final List<SearchHit> hits;

  @override
  Widget build(BuildContext context) {
    final AppState state = AppScope.of(context);
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(Tokens.s4, 0, Tokens.s4, Tokens.s6),
      itemCount: hits.length,
      itemBuilder: (BuildContext context, int index) {
        final SearchHit hit = hits[index];
        return AppearIn(
          order: index.clamp(0, 8),
          child: _HitTile(hit: hit, query: query, state: state),
        );
      },
    );
  }
}

class _HitTile extends StatelessWidget {
  const _HitTile({required this.hit, required this.query, required this.state});

  final SearchHit hit;
  final String query;
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final Ink ink = context.ink;
    final Entry entry = hit.entry;
    final List<String> fields = <String>[
      if (hit.matchedTitle) 'title',
      if (hit.where.contains('content')) 'text',
      if (hit.where.contains('tags')) 'tags',
      if (hit.where.contains('journal')) 'journal',
    ];

    final Widget tile = Container(
      margin: const EdgeInsets.only(bottom: Tokens.s2),
      decoration: BoxDecoration(
        color: ink.surface,
        borderRadius: BorderRadius.circular(Tokens.rLg),
        border: Border.all(color: ink.line),
      ),
      child: Padding(
        padding: const EdgeInsets.all(Tokens.s4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Container(
              margin: const EdgeInsets.only(top: 6),
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: hit.journal == null
                    ? ink.lineStrong
                    : Color(hit.journal!.accent),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: Tokens.s3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    entry.displayTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: AppFonts.serif,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: ink.text,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    <String>[
                      if (hit.journal != null) hit.journal!.name,
                      dateTimeLabel(entry.date),
                      'in ${fields.join(' · ')}',
                    ].join('  ·  '),
                    style: TextStyle(
                      fontFamily: AppFonts.mono,
                      fontSize: 10.5,
                      letterSpacing: 0.5,
                      color: ink.textFaint,
                    ),
                  ),
                  if (hit.snippet.isNotEmpty) ...<Widget>[
                    const SizedBox(height: Tokens.s2),
                    Text(
                      hit.snippet,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.5,
                        color: ink.textSoft,
                      ),
                    ),
                  ],
                  if (entry.tags.isNotEmpty) ...<Widget>[
                    const SizedBox(height: Tokens.s2),
                    Wrap(
                      spacing: Tokens.s1,
                      runSpacing: Tokens.s1,
                      children: <Widget>[
                        for (final String tag in entry.tags)
                          TagPill(
                            tag: tag,
                            dense: true,
                            onTap: () => state.setTagFilter(tag),
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
      label: 'Open search result ${entry.displayTitle}',
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
