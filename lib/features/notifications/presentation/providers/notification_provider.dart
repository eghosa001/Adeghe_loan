import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/di/providers.dart';
import '../../../backup/data/backup_service.dart';
import '../../data/notification_item.dart';

final notificationProvider = FutureProvider<List<NotificationItem>>((ref) async {
  final dbService = await ref.watch(databaseServiceProvider.future);
  final db = await dbService.database;
  final notifications = <NotificationItem>[];
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final uuid = const Uuid();
  final currency = await _getCurrency(db);

  // 1. Overdue loans — past due installments on active loans only
  final overdue = await db.rawQuery('''
    SELECT l.id, c.full_name, rs.due_date, rs.amount, rs.paid_amount,
           (rs.amount - rs.paid_amount) AS remaining
    FROM repayment_schedule rs
    INNER JOIN loans l ON rs.loan_id = l.id
    INNER JOIN customers c ON l.customer_id = c.id
    WHERE rs.status = 'pending' AND rs.due_date < ? AND l.status = 'active'
    ORDER BY rs.due_date ASC
    LIMIT 5
  ''', [today.toIso8601String().split('T').first]);

  for (final row in overdue) {
    final name = row['full_name'] as String;
    final remaining = (row['remaining'] as num?)?.toDouble() ?? 0;
    final dueDate = row['due_date'] as String;
    notifications.add(NotificationItem(
      id: uuid.v4(),
      type: 'overdue_loan',
      title: 'Overdue Payment — $name',
      body: '$currency${remaining.toStringAsFixed(0)} overdue since $dueDate',
      createdAt: now,
      icon: IconType.alert,
      actionRoute: '/loans/${row['id']}',
    ));
  }

  // 2. Payment due today
  final dueToday = await db.rawQuery('''
    SELECT l.id, c.full_name, rs.amount, rs.paid_amount,
           (rs.amount - rs.paid_amount) AS due
    FROM repayment_schedule rs
    INNER JOIN loans l ON rs.loan_id = l.id
    INNER JOIN customers c ON l.customer_id = c.id
    WHERE rs.status = 'pending' AND rs.due_date = ? AND l.status = 'active'
    ORDER BY c.full_name ASC
    LIMIT 5
  ''', [today.toIso8601String().split('T').first]);

  if (dueToday.isNotEmpty) {
    final totalDue = dueToday.fold<double>(0, (sum, r) => sum + ((r['due'] as num?)?.toDouble() ?? 0));
    notifications.add(NotificationItem(
      id: uuid.v4(),
      type: 'payment_due',
      title: 'Payments Due Today',
      body: '${dueToday.length} payment(s) — $currency${totalDue.toStringAsFixed(0)} total due',
      createdAt: now,
      icon: IconType.info,
      actionRoute: '/collections',
    ));
  }

  // 3. Upcoming collections (next 3 days)
  final upcomingEnd = today.add(const Duration(days: 3));
  final upcomingStart = today.add(const Duration(days: 1));
  final upcoming = await db.rawQuery('''
    SELECT l.id, c.full_name, rs.due_date, rs.amount
    FROM repayment_schedule rs
    INNER JOIN loans l ON rs.loan_id = l.id
    INNER JOIN customers c ON l.customer_id = c.id
    WHERE rs.status = 'pending'
      AND rs.due_date >= ? AND rs.due_date <= ?
      AND l.status = 'active'
    ORDER BY rs.due_date ASC
    LIMIT 5
  ''', [
    upcomingStart.toIso8601String().split('T').first,
    upcomingEnd.toIso8601String().split('T').first,
  ]);

  if (upcoming.isNotEmpty) {
    final totalUpcoming = upcoming.fold<double>(0, (sum, r) => sum + ((r['amount'] as num?)?.toDouble() ?? 0));
    final dates = upcoming.map((r) => r['due_date'] as String).toSet().toList();
    notifications.add(NotificationItem(
      id: uuid.v4(),
      type: 'upcoming_collection',
      title: 'Upcoming Collections',
      body: '${upcoming.length} payment(s) over ${dates.length} day(s) — $currency${totalUpcoming.toStringAsFixed(0)} total',
      createdAt: now,
      icon: IconType.info,
      actionRoute: '/collections/future-schedule',
    ));
  }

  // 4. Backup reminder — if no backup in 7+ days
  try {
    final backupService = BackupService(dbService);
    final backups = await backupService.listBackups();
    if (backups.isEmpty || backups.first.lastModifiedSync().isBefore(now.subtract(const Duration(days: 7)))) {
      notifications.add(NotificationItem(
        id: uuid.v4(),
        type: 'backup_reminder',
        title: 'Backup Reminder',
        body: backups.isEmpty
            ? 'No backup created yet. Back up your data regularly.'
            : 'Last backup was ${_daysAgo(backups.first.lastModifiedSync(), now)} ago.',
        createdAt: now,
        icon: IconType.backup,
        actionRoute: '/settings/backup',
      ));
    }
  } catch (_) {}

  return notifications;
});

Future<String> _getCurrency(Database db) async {
  final rows = await db.query('settings', where: "key = 'currency'", limit: 1);
  if (rows.isEmpty) return AppConstants.defaultCurrencySymbol;
  return rows.first['value'] as String? ?? AppConstants.defaultCurrencySymbol;
}

String _daysAgo(DateTime then, DateTime now) {
  final diff = now.difference(then);
  if (diff.inDays == 0) return 'today';
  if (diff.inDays == 1) return '1 day';
  return '${diff.inDays} days';
}
