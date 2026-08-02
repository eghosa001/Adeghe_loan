import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:loantrack/core/widgets/app_drawer.dart';
import 'package:loantrack/core/widgets/empty_state.dart';

import '../../../../core/di/providers.dart';
import '../../../../core/utils/date_utils.dart';
import '../../data/models/audit_log_entity.dart';

final _auditLogsProvider = FutureProvider<List<AuditLog>>((ref) async {
  final repo = await ref.watch(auditLogRepositoryProvider.future);
  final result = await repo.getAll();
  return result.when(
    success: (logs) => logs,
    failure: (f) => throw f,
  );
});

final _auditLogSearchProvider = StateProvider<String>((ref) => '');

class AuditLogScreen extends ConsumerStatefulWidget {
  const AuditLogScreen({super.key});

  @override
  ConsumerState<AuditLogScreen> createState() => _AuditLogScreenState();
}

class _AuditLogScreenState extends ConsumerState<AuditLogScreen> {
  String _selectedAction = 'All';

  static const _actionTypes = [
    'All',
    'CREATE',
    'UPDATE',
    'DELETE',
    'LOGIN',
    'LOGOUT',
    'BACKUP',
    'RESTORE',
  ];

  @override
  Widget build(BuildContext context) {
    final logsAsync = ref.watch(_auditLogsProvider);
    final searchQuery = ref.watch(_auditLogSearchProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Audit Log'),
      ),
      drawer: const AppDrawer(currentRoute: '/audit-log'),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Search audit logs...',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (value) {
                ref.read(_auditLogSearchProvider.notifier).state = value;
              },
            ),
          ),
          SizedBox(
            height: 40,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: _actionTypes.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final type = _actionTypes[index];
                final selected = _selectedAction == type;
                return FilterChip(
                  label: Text(type),
                  selected: selected,
                  onSelected: (_) {
                    setState(() => _selectedAction = type);
                  },
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: logsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (logs) {
                var filtered = logs;
                if (_selectedAction != 'All') {
                  filtered = filtered
                      .where((l) => l.action == _selectedAction)
                      .toList();
                }
                if (searchQuery.isNotEmpty) {
                  final term = searchQuery.toLowerCase();
                  filtered = filtered
                      .where((l) =>
                          l.user.toLowerCase().contains(term) ||
                          l.action.toLowerCase().contains(term) ||
                          l.details.toLowerCase().contains(term))
                      .toList();
                }
                if (filtered.isEmpty) {
                  return const EmptyState(
                    icon: Icons.history,
                    title: 'No audit log entries found',
                    subtitle: 'Actions will appear here as you use the app.',
                  );
                }
                return _buildGroupedList(filtered);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGroupedList(List<AuditLog> logs) {
    final grouped = <String, List<AuditLog>>{};
    for (final log in logs) {
      final dateKey = AppDateUtils.formatDate(log.timestamp);
      grouped.putIfAbsent(dateKey, () => []).add(log);
    }

    final dateKeys = grouped.keys.toList();

    return ListView.builder(
      itemCount: dateKeys.length,
      itemBuilder: (context, dateIndex) {
        final dateKey = dateKeys[dateIndex];
        final entries = grouped[dateKey]!;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text(
                dateKey,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ),
            ...entries.map((log) => ListTile(
                  leading: CircleAvatar(
                    radius: 16,
                    child: Text(
                      log.action.characters.first,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                  title: Text(log.action),
                  subtitle: Text(
                    '${log.user} — ${AppDateUtils.formatTime(log.timestamp)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  trailing: const Icon(Icons.chevron_right),
                )),
          ],
        );
      },
    );
  }
}
