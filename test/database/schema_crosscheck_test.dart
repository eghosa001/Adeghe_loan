import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guard against SQL table/column name drift (the class of bug that broke the
/// loan list, analytics growth, and savings reports over time).
///
/// Every `rawQuery`/`query`/`execute` SQL string in lib/ is parsed and each
/// referenced table, `alias.column` pair, and bare (unqualified) column is
/// checked against the real schema (database_service.dart + migrations.dart).
void main() {
  final root = Directory.current.path;
  final lib = Directory('$root/lib');

  final schema = _parseSchema(lib);
  final violations = <String>[];

  for (final file in _allDartFiles(lib)) {
    final text = file.readAsStringSync();
    for (final sql in _extractSqlStrings(text)) {
      // CREATE/ALTER/DROP TABLE statements define or rename tables; their
      // column lists are already validated by _parseSchema.
      if (_isTableDdl(sql)) continue;
      final tableRefs = _referencedTables(sql).toSet();
      for (final table in tableRefs) {
        if (!schema.containsKey(table)) {
          violations.add(
              '${file.path}: unknown table "$table" in: $sql');
        }
      }
      final aliases = _buildAliasMap(sql);
      for (final ref in _aliasedColumnRefs(sql)) {
        final table = aliases[ref.$1];
        if (table == null) continue; // undeclared alias — not verifiable
        if (!schema.containsKey(table)) continue;
        if (!schema[table]!.contains(ref.$2)) {
          violations.add(
              '${file.path}: column "${ref.$1}.${ref.$2}" does not exist on '
              'table "$table" in: $sql');
        }
      }
      // Bare-column check: any unqualified column must exist on at least one
      // of the tables referenced by the statement.
      final columnUniverse = <String>{};
      for (final table in tableRefs) {
        columnUniverse.addAll(schema[table] ?? const {});
      }
      final excluded = _excludedIdentifiers(sql, aliases, tableRefs);
      for (final bare in _bareColumnRefs(sql)) {
        if (excluded.contains(bare)) continue;
        if (!columnUniverse.contains(bare)) {
          violations.add(
              '${file.path}: column "$bare" does not exist on any referenced '
              'table (${tableRefs.join(', ')}) in: $sql');
        }
      }
    }
    // Plain table names passed as the first argument to
    // `insert`/`update`/`delete`/`query` (e.g. `db.insert('loans', ...)`).
    for (final table in _plainTableNames(text)) {
      if (!schema.containsKey(table)) {
        violations.add('${file.path}: unknown table "$table"');
      }
    }
  }

  test('every SQL table and aliased column exists in the schema', () {
    expect(violations, isEmpty,
        reason: 'SQL name mismatches found:\n${violations.join('\n')}');
  });
}

Map<String, Set<String>> _parseSchema(Directory lib) {
  final schema = <String, Set<String>>{};

  void ingestCreateTables(String source) {
    final createRe = RegExp(
        r'CREATE TABLE\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(',
        caseSensitive: false);
    for (final m in createRe.allMatches(source)) {
      final name = m.group(1)!;
      final columns = <String>{};
      // Walk to the matching closing paren (column defs may contain parens).
      var i = source.indexOf('(', m.start) + 1;
      var depth = 1;
      final buffer = StringBuffer();
      while (i < source.length && depth > 0) {
        final ch = source[i];
        if (ch == '(') depth++;
        if (ch == ')') depth--;
        if (depth > 0) buffer.write(ch);
        i++;
      }
      final body = buffer.toString();
      for (final line in body.split('\n')) {
        final col = RegExp(r'^\s*([A-Za-z_][A-Za-z0-9_]*)')
            .firstMatch(line)
            ?.group(1);
        if (col == null) continue;
        if (const {'FOREIGN', 'PRIMARY', 'UNIQUE', 'CHECK', 'CONSTRAINT'}
            .contains(col)) {
          continue;
        }
        columns.add(col);
      }
      schema.putIfAbsent(name, () => {}).addAll(columns);
    }
  }

  void ingestAlterAdds(String source) {
    final alterRe = RegExp(
        r'ALTER TABLE\s+([A-Za-z_][A-Za-z0-9_]*)\s+ADD COLUMN\s+([A-Za-z_][A-Za-z0-9_]*)',
        caseSensitive: false);
    for (final m in alterRe.allMatches(source)) {
      schema.putIfAbsent(m.group(1)!, () => {}).add(m.group(2)!);
    }
  }

  final dbService = File('${lib.path}/core/database/database_service.dart');
  final migrations = File('${lib.path}/core/database/migrations.dart');
  if (dbService.existsSync()) {
    ingestCreateTables(dbService.readAsStringSync());
  }
  if (migrations.existsSync()) {
    ingestCreateTables(migrations.readAsStringSync());
    ingestAlterAdds(migrations.readAsStringSync());
  }
  return schema;
}

Iterable<File> _allDartFiles(Directory dir) sync* {
  for (final entry in dir.listSync(recursive: true, followLinks: false)) {
    if (entry is File && entry.path.endsWith('.dart')) {
      yield entry;
    }
  }
}

/// Extracts the SQL passed as the first argument to sqflite query methods
/// (`rawQuery`, `execute`, `query`, `insert`, ...). Only strings that contain
/// an actual SQL keyword are treated as SQL, so prose error messages are never
/// scanned.
Iterable<String> _extractSqlStrings(String source) {
  final callRe = RegExp(
      r'\.(?:rawQuery|rawInsert|rawUpdate|rawDelete|execute|query|insert|update|delete)\s*\(\s*',
      caseSensitive: false);
  final sqlKeyword = RegExp(
      r'\b(SELECT|INSERT|UPDATE|DELETE|CREATE|ALTER|FROM|JOIN|INTO)\b',
      caseSensitive: false);
  final result = <String>[];
  for (final m in callRe.allMatches(source)) {
    final rest = source.substring(m.end);
    final literal = _leadingStringLiteral(rest);
    if (literal != null && sqlKeyword.hasMatch(literal)) {
      result.add(literal);
    }
  }
  return result;
}

/// Returns the content of the string literal at the start of [text], or null.
String? _leadingStringLiteral(String text) {
  String? trySingleQuoted(String source) {
    if (!source.startsWith("'")) return null;
    final buffer = StringBuffer();
    var i = 1;
    while (i < source.length) {
      final ch = source[i];
      if (ch == '\\' && i + 1 < source.length) {
        buffer.write(source[i + 1]);
        i += 2;
        continue;
      }
      if (ch == "'") {
        return buffer.toString();
      }
      buffer.write(ch);
      i++;
    }
    return null;
  }

  String? tryTripleQuoted(String source) {
    if (!source.startsWith("'''")) return null;
    final end = source.indexOf("'''", 3);
    if (end < 0) return null;
    return source.substring(3, end);
  }

  String? tryDoubleQuoted(String source) {
    if (!source.startsWith('"')) return null;
    final buffer = StringBuffer();
    var i = 1;
    while (i < source.length) {
      final ch = source[i];
      if (ch == '\\' && i + 1 < source.length) {
        buffer.write(source[i + 1]);
        i += 2;
        continue;
      }
      if (ch == '"') {
        return buffer.toString();
      }
      buffer.write(ch);
      i++;
    }
    return null;
  }

  return tryTripleQuoted(text) ?? trySingleQuoted(text) ?? tryDoubleQuoted(text);
}

Iterable<String> _referencedTables(String sql) {
  final result = <String>[];
  void add(RegExp re) {
    for (final m in re.allMatches(sql)) {
      result.add(m.group(1)!);
    }
  }

  add(RegExp(
      r'\b(?:FROM|JOIN|UPDATE|INTO)\s+([A-Za-z_][A-Za-z0-9_]*)',
      caseSensitive: false));
  add(RegExp(
      r'\bCREATE\s+INDEX(?:\s+IF\s+NOT\s+EXISTS)?\s+[A-Za-z_][A-Za-z0-9_]*\s+ON\s+([A-Za-z_][A-Za-z0-9_]*)',
      caseSensitive: false));
  return result;
}

bool _isTableDdl(String sql) {
  return RegExp(
          r'\b(?:CREATE\s+TABLE|ALTER\s+TABLE|DROP\s+TABLE)\b',
          caseSensitive: false)
      .hasMatch(sql);
}

/// Table names passed as the first argument to sqflite methods that take a
/// plain table name instead of SQL (e.g. `db.insert('loans', ...)`).
Iterable<String> _plainTableNames(String source) {
  final callRe = RegExp(
      r'\.(?:insert|update|delete|query|rawInsert|rawUpdate|rawDelete)\s*\(\s*',
      caseSensitive: false);
  final tableName = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$');
  final result = <String>[];
  for (final m in callRe.allMatches(source)) {
    final rest = source.substring(m.end);
    final literal = _leadingStringLiteral(rest);
    if (literal != null && tableName.hasMatch(literal)) {
      result.add(literal);
    }
  }
  return result;
}

Map<String, String> _buildAliasMap(String sql) {
  final aliases = <String, String>{};
  final re = RegExp(
      r'\b(?:FROM|JOIN|UPDATE|INTO)\s+([A-Za-z_][A-Za-z0-9_]*)\s+(?:AS\s+)?([A-Za-z_][A-Za-z0-9_]*)',
      caseSensitive: false);
  for (final m in re.allMatches(sql)) {
    aliases[m.group(2)!] = m.group(1)!;
    aliases[m.group(1)!] = m.group(1)!;
  }
  return aliases;
}

Iterable<(String, String)> _aliasedColumnRefs(String sql) {
  final re = RegExp(r'\b([A-Za-z_][A-Za-z0-9_]*)\.([A-Za-z_][A-Za-z0-9_]*)\b');
  final seen = <String>{};
  final result = <(String, String)>[];
  for (final m in re.allMatches(sql)) {
    final key = '${m.group(1)}.${m.group(2)}';
    if (seen.add(key)) result.add((m.group(1)!, m.group(2)!));
  }
  return result;
}

/// Unqualified identifiers that are not allowed to count as column refs.
///
/// These are SQL keywords/functions, referenced table names, table aliases,
/// and `SELECT ... AS <alias>` output names.
Set<String> _excludedIdentifiers(
    String sql, Map<String, String> aliases, Set<String> tableRefs) {
  final excluded = <String>{
    ..._sqlStopwords,
    for (final t in tableRefs) t.toLowerCase(),
    for (final a in aliases.keys) a.toLowerCase(),
  };
  final asRe = RegExp(r'\bAS\s+([A-Za-z_][A-Za-z0-9_]*)',
      caseSensitive: false);
  for (final m in asRe.allMatches(sql)) {
    excluded.add(m.group(1)!.toLowerCase());
  }
  final idxRe = RegExp(
      r'\bCREATE\s+INDEX(?:\s+IF\s+NOT\s+EXISTS)?\s+([A-Za-z_][A-Za-z0-9_]*)',
      caseSensitive: false);
  for (final m in idxRe.allMatches(sql)) {
    excluded.add(m.group(1)!.toLowerCase());
  }
  return excluded;
}

/// Bare (unqualified) identifiers in [sql] after removing string literals,
/// Dart interpolations, numeric literals, and dotted refs.
Iterable<String> _bareColumnRefs(String sql) {
  var s = sql.replaceAll(
      RegExp(r'\$[A-Za-z_][A-Za-z0-9_]*|\$\{[^}]*\}'), ' ');
  s = s.replaceAll(RegExp(r"'(?:[^']|'')*'"), ' ');
  s = s.replaceAll(RegExp(r'\b[A-Za-z_][A-Za-z0-9_]*\.[A-Za-z_][A-Za-z0-9_]*\b'),
      ' ');
  s = s.replaceAll(RegExp(r'\b\d+(?:\.\d+)?\b'), ' ');
  final re = RegExp(r'\b([A-Za-z_][A-Za-z0-9_]*)\b', caseSensitive: false);
  final result = <String>[];
  final seen = <String>{};
  for (final m in re.allMatches(s)) {
    final id = m.group(1)!.toLowerCase();
    if (seen.add(id)) result.add(id);
  }
  return result;
}

const _sqlStopwords = {
  'select', 'from', 'where', 'and', 'or', 'not', 'in', 'between', 'like',
  'group', 'by', 'order', 'having', 'limit', 'offset', 'join', 'left', 'right',
  'inner', 'outer', 'full', 'cross', 'on', 'as', 'case', 'when', 'then', 'else',
  'end',   'distinct', 'desc', 'asc', 'null', 'is', 'exists', 'union', 'all',
  'with', 'over', 'partition', 'values', 'set', 'insert', 'update', 'delete',
  'create', 'alter', 'table', 'into', 'index', 'key', 'primary', 'foreign',
  'references', 'default', 'constraint', 'cascade', 'nullif', 'ifnull',
  'coalesce', 'date', 'datetime', 'julianday', 'strftime', 'printf', 'lower',
  'upper', 'substr', 'length', 'replace', 'trim', 'typeof', 'round', 'abs',
  'min', 'max', 'avg', 'total', 'sum', 'count', 'row', 'number', 'natural',
  'rename', 'drop', 'add', 'column', 'temp', 'temporary', 'autoincrement',
  'unique', 'check', 'collate', 'varchar', 'integer', 'text', 'real', 'blob',
  'numeric', 'float', 'double', 'boolean', 'bigint', 'smallint', 'char', 'bool',
  'returning', 'upsert', 'conflict', 'nothing', 'sqlite_sequence', 'pragma',
  'if', 'to', 'nocase', 'binary', 'rtrim', 'ltrim', 'glob', 'escape', 'current',
  'time', 'cast', 'changes', 'sqlite_version', 'transaction', 'begin',
  'commit', 'rollback', 'enable', 'disable', 'foreign_keys', 'cascading',
};
