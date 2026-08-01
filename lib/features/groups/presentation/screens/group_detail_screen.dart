import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/utils/currency_utils.dart';
import '../../../../core/utils/date_utils.dart';
import '../../../../features/customers/data/models/customer_entity.dart';
import '../../../../features/customers/presentation/providers/customer_providers.dart';
import '../../../../features/collection/presentation/providers/collection_provider.dart';
import '../../../../features/dashboard/presentation/providers/dashboard_provider.dart';
import '../providers/group_providers.dart';

class GroupDetailScreen extends ConsumerStatefulWidget {
  const GroupDetailScreen({super.key, required this.groupId});
  final String groupId;

  @override
  ConsumerState<GroupDetailScreen> createState() => _GroupDetailScreenState();
}

class _GroupDetailScreenState extends ConsumerState<GroupDetailScreen> {
  List<Customer> _members = [];
  Map<String, dynamic>? _stats;
  Map<String, double>? _collectionSummary;
  bool _loading = true;
  final Set<String> _selectedIds = {};
  bool _selectionMode = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      final repo = await ref.read(groupRepositoryProvider.future);
      final results = await Future.wait([
        repo.getMembers(widget.groupId),
        repo.getStats(widget.groupId),
        repo.getCollectionSummary(widget.groupId, DateTime.now()),
      ]);
      if (!mounted) return;
      setState(() {
        _members = results[0] as List<Customer>;
        _stats = results[1] as Map<String, dynamic>;
        _collectionSummary = results[2] as Map<String, double>;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _removeMember(String customerId) async {
    final customer = _members.firstWhere((c) => c.id == customerId);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove member?'),
        content: Text('Remove ${customer.fullName} from this group?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Remove')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final repo = await ref.read(groupRepositoryProvider.future);
    await repo.removeMember(customerId);
    _invalidate();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${customer.fullName} removed from group')),
      );
    }
  }

  Future<void> _addMembers() async {
    final repo = await ref.read(customerRepositoryProvider.future);
    final allCustomers = await repo.search('');
    final available = allCustomers
        .where((c) => c.groupId != widget.groupId)
        .toList()
      ..sort((a, b) => a.fullName.compareTo(b.fullName));

    if (!mounted) return;
    final selected = await showDialog<Set<String>>(
      context: context,
      builder: (ctx) => _MemberPickerDialog(customers: available),
    );
    if (selected == null || selected.isEmpty || !mounted) return;
    for (final id in selected) {
      await repo.changeGroup(id, widget.groupId);
    }
    _invalidate();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${selected.length} member(s) added')),
      );
    }
  }

  Future<void> _moveSelectedMembers() async {
    final groups = await ref.read(groupListProvider.future);
    final otherGroups = groups.where((g) => g.id != widget.groupId).toList();
    if (!mounted) return;
    final target = await showDialog<CustomerGroup>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Move to group'),
        children: [
          ...otherGroups.map((g) => SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, g),
                child: Text(g.name),
              )),
          if (otherGroups.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('No other groups available'),
            ),
        ],
      ),
    );
    if (target == null || !mounted) return;

    final movedCount = _selectedIds.length;
    final repo = await ref.read(groupRepositoryProvider.future);
    await repo.moveMembers(_selectedIds.toList(), target.id);
    _invalidate();
    setState(() {
      _selectedIds.clear();
      _selectionMode = false;
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$movedCount member(s) moved to ${target.name}')),
      );
    }
  }

  void _invalidate() {
    ref.invalidate(groupListProvider);
    ref.invalidate(customerListProvider);
    ref.invalidate(collectionListProvider);
    ref.invalidate(dashboardDataProvider);
    _loadData();
  }

  void _toggleSelection(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
        if (_selectedIds.isEmpty) _selectionMode = false;
      } else {
        _selectedIds.add(id);
        _selectionMode = true;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final groupsAsync = ref.watch(groupListProvider);
    final group = groupsAsync.valueOrNull?.where((g) => g.id == widget.groupId).firstOrNull;

    return Scaffold(
      appBar: AppBar(
        title: Text(group?.name ?? 'Group'),
        actions: [
          if (_selectionMode)
            TextButton(
              onPressed: _selectedIds.isEmpty ? null : _moveSelectedMembers,
              child: const Text('Move'),
            ),
          if (_selectionMode)
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => setState(() {
                _selectedIds.clear();
                _selectionMode = false;
              }),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addMembers,
        icon: const Icon(Icons.person_add),
        label: const Text('Add members'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              child: ListView(
                padding: const EdgeInsets.only(bottom: 88),
                children: [
                  _GroupInfoCard(group: group),
                  _StatsCards(stats: _stats),
                  _CollectionSummaryCard(summary: _collectionSummary),
                  _buildMemberSection(),
                ],
              ),
            ),
    );
  }

  Widget _buildMemberSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              Text('Members (${_members.length})',
                  style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              if (_members.isNotEmpty)
                TextButton(
                  onPressed: () => setState(() {
                    _selectionMode = !_selectionMode;
                    if (!_selectionMode) _selectedIds.clear();
                  }),
                  child: Text(_selectionMode ? 'Cancel' : 'Select'),
                ),
            ],
          ),
        ),
        if (_members.isEmpty)
          const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: Text('No members in this group yet.')),
          )
        else
          ..._members.map((customer) => ListTile(
                leading: _selectionMode
                    ? Checkbox(
                        value: _selectedIds.contains(customer.id),
                        onChanged: (_) => _toggleSelection(customer.id),
                      )
                    : CircleAvatar(
                        child: Text(customer.fullName.isNotEmpty
                            ? customer.fullName[0].toUpperCase()
                            : '?'),
                      ),
                title: Text(customer.fullName),
                subtitle: Text(customer.phone),
                trailing: _selectionMode
                    ? null
                    : PopupMenuButton<String>(
                        onSelected: (action) {
                          if (action == 'remove') _removeMember(customer.id);
                          if (action == 'view') context.push('/customers/${customer.id}');
                        },
                        itemBuilder: (_) => [
                          const PopupMenuItem(value: 'view', child: Text('View profile')),
                          const PopupMenuItem(value: 'remove', child: Text('Remove from group')),
                        ],
                      ),
                onTap: _selectionMode
                    ? () => _toggleSelection(customer.id)
                    : () => context.push('/customers/${customer.id}'),
              )),
        const SizedBox(height: 16),
        Center(
          child: OutlinedButton.icon(
            onPressed: () {
            ref.read(collectionGroupFilterProvider.notifier).state = widget.groupId;
            context.push('/collections');
          },
            icon: const Icon(Icons.collections_bookmark),
            label: const Text('View group collections'),
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}

class _GroupInfoCard extends StatelessWidget {
  const _GroupInfoCard({required this.group});
  final CustomerGroup? group;

  @override
  Widget build(BuildContext context) {
    if (group == null) return const SizedBox.shrink();
    final created = DateTime.tryParse(group!.createdAt);
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                  child: Text(group!.name[0].toUpperCase(),
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.onPrimaryContainer)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(group!.name,
                          style: Theme.of(context).textTheme.titleLarge),
                      if (created != null)
                        Text('Created ${AppDateUtils.formatDate(created)}',
                            style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
              ],
            ),
            if (group!.description != null && group!.description!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(group!.description!,
                  style: Theme.of(context).textTheme.bodyMedium),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatsCards extends StatelessWidget {
  const _StatsCards({required this.stats});
  final Map<String, dynamic>? stats;

  @override
  Widget build(BuildContext context) {
    if (stats == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _StatCard(
            label: 'Members',
            value: '${stats!['memberCount']}',
            icon: Icons.people,
            color: Colors.blue,
          ),
          _StatCard(
            label: 'Active Loans',
            value: '${stats!['activeLoans']}',
            icon: Icons.monetization_on,
            color: Colors.orange,
          ),
          _StatCard(
            label: 'Outstanding',
            value: CurrencyUtils.format((stats!['totalOutstanding'] as num).toDouble()),
            icon: Icons.account_balance,
            color: Colors.red,
          ),
          _StatCard(
            label: 'Total Savings',
            value: CurrencyUtils.format((stats!['totalSavings'] as num).toDouble()),
            icon: Icons.savings,
            color: Colors.green,
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: (MediaQuery.of(context).size.width - 40) / 2,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(height: 8),
              Text(value,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      )),
              Text(label, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}

class _CollectionSummaryCard extends StatelessWidget {
  const _CollectionSummaryCard({required this.summary});
  final Map<String, double>? summary;

  @override
  Widget build(BuildContext context) {
    if (summary == null) return const SizedBox.shrink();
    final due = summary!['due'] ?? 0;
    final paid = summary!['paid'] ?? 0;
    final remaining = summary!['remaining'] ?? 0;
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Today's Collection",
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _SummaryCol(label: 'Due', value: CurrencyUtils.format(due)),
                _SummaryCol(label: 'Paid', value: CurrencyUtils.format(paid)),
                _SummaryCol(label: 'Remaining', value: CurrencyUtils.format(remaining)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryCol extends StatelessWidget {
  const _SummaryCol({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value,
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(fontWeight: FontWeight.bold)),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _MemberPickerDialog extends StatefulWidget {
  const _MemberPickerDialog({required this.customers});
  final List<Customer> customers;

  @override
  State<_MemberPickerDialog> createState() => _MemberPickerDialogState();
}

class _MemberPickerDialogState extends State<_MemberPickerDialog> {
  String _search = '';
  final Set<String> _selected = {};

  @override
  Widget build(BuildContext context) {
    final filtered = widget.customers
        .where((c) =>
            _search.isEmpty ||
            c.fullName.toLowerCase().contains(_search.toLowerCase()) ||
            c.phone.contains(_search))
        .toList();

    return AlertDialog(
      title: const Text('Add members'),
      content: SizedBox(
        width: double.maxFinite,
        height: 400,
        child: Column(
          children: [
            TextField(
              decoration: const InputDecoration(
                hintText: 'Search customers...',
                prefixIcon: Icon(Icons.search),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _search = v),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: filtered.isEmpty
                  ? const Center(child: Text('No customers found'))
                  : ListView(
                      children: filtered.map((c) {
                        final isSelected = _selected.contains(c.id);
                        return CheckboxListTile(
                          value: isSelected,
                          title: Text(c.fullName),
                          subtitle: Text(c.phone),
                          onChanged: (_) {
                            setState(() {
                              if (isSelected) {
                                _selected.remove(c.id);
                              } else {
                                _selected.add(c.id);
                              }
                            });
                          },
                        );
                      }).toList(),
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _selected.isEmpty
              ? null
              : () => Navigator.pop(context, _selected),
          child: Text('Add (${_selected.length})'),
        ),
      ],
    );
  }
}
