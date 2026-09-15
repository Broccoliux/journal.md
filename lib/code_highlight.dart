import 'package:flutter/material.dart' hide Ink;

import 'theme.dart';

/// A small, dependency-free syntax highlighter for fenced code blocks.
///
/// Deliberately a scanner rather than a parser: it recognises comments,
/// strings, numbers, keywords, type names and calls, which is enough to make
/// technical notes readable. Unknown languages simply render as plain code,
/// and the highlighter can never throw.


enum TokenKind { plain, comment, string, number, keyword, type, call }

class CodeToken {
  const CodeToken(this.text, this.kind);

  final String text;
  final TokenKind kind;
}

/// Colours for the code card. Code is shown on a dark surface in both themes,
/// the way a terminal sits on a desk in any room.
@immutable
class CodeTheme {
  const CodeTheme({
    required this.plain,
    required this.comment,
    required this.string,
    required this.number,
    required this.keyword,
    required this.type,
    required this.call,
    required this.headerText,
    required this.headerLine,
  });

  final Color plain;
  final Color comment;
  final Color string;
  final Color number;
  final Color keyword;
  final Color type;
  final Color call;
  final Color headerText;
  final Color headerLine;

  static const CodeTheme dark = CodeTheme(
    plain: Color(0xFFD7DEE9),
    comment: Color(0xFF6E7887),
    string: Color(0xFFA8D8A6),
    number: Color(0xFFE4BE7D),
    keyword: Color(0xFFC49AE8),
    type: Color(0xFF8DB4FF),
    call: Color(0xFF7FD8C8),
    headerText: Color(0xFF8892A0),
    headerLine: Color(0xFF2A2F37),
  );

  Color colorFor(TokenKind kind) => switch (kind) {
    TokenKind.plain => plain,
    TokenKind.comment => comment,
    TokenKind.string => string,
    TokenKind.number => number,
    TokenKind.keyword => keyword,
    TokenKind.type => type,
    TokenKind.call => call,
  };

  static TextStyle get base => const TextStyle(
    fontSize: 13.5,
    height: 1.62,
  ).copyWith(fontFamily: AppFonts.mono);
}

/// Keywords across the languages people actually write notes in. One shared
/// set keeps the highlighter short; a false positive only means one word is
/// tinted purple, which never misleads.
const Set<String> _keywords = <String>{
  'abstract', 'and', 'as', 'assert', 'async', 'await', 'base', 'begin',
  'break', 'case', 'catch', 'class', 'const', 'continue', 'covariant',
  'default', 'def', 'defer', 'deferred', 'do', 'dynamic', 'elif', 'else',
  'end', 'enum', 'except', 'export', 'extends', 'extension', 'external',
  'factory', 'false', 'final', 'finally', 'fn', 'for', 'from', 'function',
  'get', 'goto', 'if', 'impl', 'implements', 'import', 'in', 'interface',
  'is', 'lambda', 'late', 'let', 'library', 'loop', 'match', 'mixin',
  'module', 'mut', 'new', 'not', 'null', 'on', 'operator', 'or', 'override',
  'package', 'part', 'pass', 'private', 'protected', 'pub', 'public', 'raise',
  'ref', 'register', 'required', 'return', 'sealed', 'self', 'set', 'sizeof',
  'static', 'struct', 'super', 'switch', 'sync', 'this', 'throw', 'trait',
  'true', 'try', 'typedef', 'type', 'typeof', 'union', 'use', 'val', 'var',
  'void', 'volatile', 'when', 'where', 'while', 'with', 'yield',
};

const Map<String, Set<String>> _types = <String, Set<String>>{
  'dart': <String>{
    'int', 'double', 'num', 'String', 'bool', 'List', 'Map', 'Set',
    'Iterable', 'Future', 'Stream', 'Object', 'dynamic', 'Uint8List',
    'DateTime', 'Duration', 'Widget', 'BuildContext',
  },
  'typescript': <String>{
    'number', 'string', 'boolean', 'any', 'unknown', 'never', 'void',
    'Array', 'Promise', 'Record', 'Partial', 'Readonly',
  },
  'javascript': <String>{'Number', 'String', 'Boolean', 'Array', 'Object',
    'Promise', 'Symbol', 'BigInt', 'Function', 'Error', 'Date', 'RegExp'},
  'python': <String>{
    'int', 'float', 'str', 'bool', 'list', 'dict', 'set', 'tuple', 'bytes',
    'object', 'None', 'Exception', 'self', 'cls',
  },
  'rust': <String>{
    'i8', 'i16', 'i32', 'i64', 'u8', 'u16', 'u32', 'u64', 'f32', 'f64',
    'usize', 'isize', 'String', 'Vec', 'Option', 'Result', 'Box', 'Rc',
    'Arc', 'RefCell', 'HashMap', 'HashSet', 'Self',
  },
  'go': <String>{
    'int', 'int8', 'int16', 'int32', 'int64', 'uint', 'float32', 'float64',
    'string', 'bool', 'byte', 'rune', 'error', 'any', 'nil',
  },
  'c': <String>{
    'int', 'char', 'float', 'double', 'void', 'long', 'short', 'unsigned',
    'size_t', 'FILE', 'bool',
  },
  'cpp': <String>{
    'int', 'char', 'float', 'double', 'void', 'bool', 'size_t', 'string',
    'vector', 'map', 'set', 'unique_ptr', 'shared_ptr', 'auto', 'std',
  },
  'java': <String>{
    'int', 'long', 'double', 'float', 'boolean', 'char', 'byte', 'short',
    'String', 'Object', 'Integer', 'Long', 'Double', 'Boolean', 'List',
    'Map', 'Set', 'Optional', 'Exception',
  },
  'kotlin': <String>{
    'Int', 'Long', 'Double', 'Float', 'Boolean', 'Char', 'String', 'Any',
    'Unit', 'Nothing', 'List', 'Map', 'Set',
  },
  'swift': <String>{
    'Int', 'Double', 'Float', 'Bool', 'String', 'Character', 'Any',
    'Array', 'Dictionary', 'Set', 'Optional', 'Self',
  },
  'sql': <String>{'INT', 'TEXT', 'VARCHAR', 'BOOLEAN', 'DATE', 'TIMESTAMP',
    'FLOAT', 'DOUBLE', 'DECIMAL', 'NULL'},
  'json': <String>{'true', 'false', 'null'},
};

/// Languages whose comments start with `#`.
const Set<String> _hashComment = <String>{
  'bash', 'conf', 'dockerfile', 'ini', 'makefile', 'perl', 'properties',
  'python', 'r', 'ruby', 'sh', 'shell', 'toml', 'yaml', 'yml',
};

/// Languages whose comments start with `--`.
const Set<String> _dashComment = <String>{
  'elm', 'haskell', 'lua', 'sql',
};

/// Languages with no block comment syntax.
const Set<String> _noBlockComment = <String>{
  'bash', 'conf', 'dockerfile', 'ini', 'makefile', 'perl', 'properties',
  'python', 'ruby', 'sh', 'shell', 'toml', 'yaml', 'yml',
};

const String _identifierPattern = r'[A-Za-z_$][A-Za-z0-9_$]*';
const String _numberPattern =
    r'0[xXbBoO][0-9a-fA-F_]+|\d[\d_]*(?:\.\d[\d_]*)?(?:[eE][+-]?\d+)?';

/// Splits [source] into coloured tokens. Never throws: in the worst case it
/// returns one plain token and the code still renders correctly.
List<CodeToken> highlightCode(String source, String language) {
  final String lang = language.trim().toLowerCase();
  final String lineComment = _lineComment(lang);
  final bool blockComments = !_noBlockComment.contains(lang);
  final Set<String> types = _types[lang] ?? const <String>{};
  final RegExp identifier = RegExp(_identifierPattern);
  final RegExp number = RegExp(_numberPattern);

  final List<CodeToken> out = <CodeToken>[];
  final StringBuffer plain = StringBuffer();

  void flush() {
    if (plain.isEmpty) return;
    out.add(CodeToken(plain.toString(), TokenKind.plain));
    plain.clear();
  }

  void emit(String text, TokenKind kind) {
    flush();
    out.add(CodeToken(text, kind));
  }

  int i = 0;
  while (i < source.length) {
    final String c = source[i];

    if (source.startsWith(lineComment, i)) {
      final int nl = source.indexOf('\n', i);
      final int end = nl == -1 ? source.length : nl;
      emit(source.substring(i, end), TokenKind.comment);
      i = end;
      continue;
    }

    if (blockComments && source.startsWith('/*', i)) {
      final int close = source.indexOf('*/', i + 2);
      final int end = close == -1 ? source.length : close + 2;
      emit(source.substring(i, end), TokenKind.comment);
      i = end;
      continue;
    }

    if (c == '"' || c == "'" || c == '`') {
      final bool triple =
          i + 2 < source.length && source[i + 1] == c && source[i + 2] == c;
      final String fence = triple ? c * 3 : c;
      int j = i + fence.length;
      while (j < source.length) {
        if (!triple && source[j] == '\\') {
          j += 2;
          continue;
        }
        if (source.startsWith(fence, j)) {
          j += fence.length;
          break;
        }
        if (!triple && source[j] == '\n') break;
        j++;
      }
      final int end = j.clamp(0, source.length);
      emit(source.substring(i, end), TokenKind.string);
      i = end;
      continue;
    }

    final RegExpMatch? word = identifier.matchAsPrefix(source, i);
    if (word != null) {
      final String text = word.group(0)!;
      emit(text, _classify(text, source, word.end, types));
      i = word.end;
      continue;
    }

    final RegExpMatch? numeric = number.matchAsPrefix(source, i);
    if (numeric != null) {
      emit(numeric.group(0)!, TokenKind.number);
      i = numeric.end;
      continue;
    }

    plain.write(c);
    i++;
  }
  flush();
  return out;
}

String _lineComment(String language) {
  if (_hashComment.contains(language)) return '#';
  if (_dashComment.contains(language)) return '--';
  if (language == 'latex' || language == 'tex') return '%';
  return '//';
}

TokenKind _classify(
  String text,
  String source,
  int end,
  Set<String> types,
) {
  final String lower = text.toLowerCase();
  if (_keywords.contains(text) || _keywords.contains(lower)) {
    return TokenKind.keyword;
  }
  if (types.contains(text) || types.contains(lower)) return TokenKind.type;
  int j = end;
  while (j < source.length && source[j] == ' ') {
    j++;
  }
  if (j < source.length && source[j] == '(') return TokenKind.call;
  if (text.length > 1 && RegExp(r'^[A-Z]').hasMatch(text)) {
    return TokenKind.type;
  }
  return TokenKind.plain;
}

/// Label for the code card header.
String languageLabel(String language) {
  final String lang = language.trim();
  return lang.isEmpty ? 'text' : lang.toLowerCase();
}
    'Future', 'Stream', 'Object', 'Widget', 'BuildContext', 'State',
    'Uint8List',
  },
  'python': <String>{
    'int', 'float', 'str', 'bool', 'list', 'dict', 'set', 'tuple',
  },
  'sql': <String>{
    'int', 'text', 'varchar', 'boolean', 'timestamp', 'date', 'json',
  },
};