import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/database/database_service.dart';

class SearchResultItem {
  final String category;
  final String id;
  final String title;
  final String subtitle;
  final String route;
  final Map<String, dynamic>? extra;

  const SearchResultItem({
    required this.category,
    required this.id,
    required this.title,
    required this.subtitle,
    required this.route,
    this.extra,
  });
}

class GlobalSearchRepository {
  final DatabaseService _dbService;

  GlobalSearchRepository(this._dbService);

  Future<List<SearchResultItem>> search(String query) async {
    if (query.trim().isEmpty) return [];

    final db = await _dbService.database;
    final term = '%${query.trim()}%';
    final results = <SearchResultItem>[];
    final currency = await _getCurrency(db);

    final customers = await db.rawQuery('''
      SELECT id, full_name, phone FROM customers
      WHERE status != 'archived'
        AND (full_name LIKE ? OR phone LIKE ? OR bvn LIKE ? OR nin LIKE ?
            OR residential_address LIKE ? OR id LIKE ?)
      ORDER BY full_name COLLATE NOCASE ASC
      LIMIT 15
    ''', [term, term, term, term, term, term]);

    for (final row in customers) {
      results.add(SearchResultItem(
        category: 'customer',
        id: row['id'] as String,
        title: row['full_name'] as String,
        subtitle: row['phone'] as String? ?? '-',
        route: '/customers/${row['id']}',
      ));
    }

    final loans = await db.rawQuery('''
      SELECT l.id, c.full_name AS customer_name, l.amount, l.status, l.loan_date
      FROM loans l INNER JOIN customers c ON l.customer_id = c.id
      WHERE l.id LIKE ? OR c.full_name LIKE ? OR c.phone LIKE ?
          OR l.status LIKE ? OR l.loan_date LIKE ? OR l.loan_type LIKE ?
      ORDER BY l.loan_date DESC
      LIMIT 15
    ''', [term, term, term, term, term, term]);

    for (final row in loans) {
      results.add(SearchResultItem(
        category: 'loan',
        id: row['id'] as String,
        title: row['customer_name'] as String,
        subtitle: '${_formatAmount(row['amount'] as num? ?? 0, currency)} • ${(row['status'] as String).toUpperCase()} • ${(row['loan_date'] as String).split('T').first}',
        route: '/loans/${row['id']}',
      ));
    }

    final groups = await db.rawQuery('''
      SELECT id, name, description, created_at FROM customer_groups
      WHERE name LIKE ? OR description LIKE ?
      ORDER BY name COLLATE NOCASE ASC
      LIMIT 10
    ''', [term, term]);

    for (final row in groups) {
      results.add(SearchResultItem(
        category: 'group',
        id: row['id'] as String,
        title: row['name'] as String,
        subtitle: row['description'] as String? ?? '-',
        route: '/groups/${row['id']}',
      ));
    }

    return results;
  }

  Future<String> _getCurrency(Database db) async {
    final rows = await db.query('settings', where: "key = 'currency'", limit: 1);
    if (rows.isEmpty) return AppConstants.defaultCurrencySymbol;
    return rows.first['value'] as String? ?? AppConstants.defaultCurrencySymbol;
  }

  String _formatAmount(num amount, String currency) {
    return '$currency${amount.toStringAsFixed(2)}';
  }
}
