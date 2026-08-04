import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:loantrack/core/constants/app_constants.dart';
import 'package:loantrack/core/utils/input_formatters.dart';
import 'package:loantrack/core/widgets/app_drawer.dart';
import 'package:loantrack/core/widgets/empty_state.dart';

import '../providers/group_providers.dart';
import '../../../collection/presentation/providers/collection_provider.dart';
import '../../../dashboard/presentation/providers/dashboard_provider.dart';
import '../../../customers/presentation/providers/customer_providers.dart';
import '../../../reports/services/excel_export_service.dart';

class GroupManagementScreen extends ConsumerStatefulWidget {
  const GroupManagementScreen({super.key});

  @override
  ConsumerState<GroupManagementScreen> createState() => _GroupManagementScreenState();
}

class _GroupManagementScreenState extends ConsumerState<GroupManagementScreen> {
  String _searchQuery = '';

  @override
  Widget build(BuildContext context) {
    final groupsAsync = ref.watch(groupListProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Customer Groups'),
        actions: [
          IconButton(
            icon: const Icon(Icons.file_download),
            tooltip: 'Export to Excel',
            onPressed: _exportGroups,
          ),
        ],
      ),
      drawer: const AppDrawer(currentRoute: '/groups'),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showGroupDialog(context, ref, null),
        icon: const Icon(Icons.group_add),
        label: const Text('New group'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Search groups...',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (value) => setState(() => _searchQuery = value),
            ),
          ),
          Expanded(
            child: groupsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (groups) {
                var filtered = groups;
                if (_searchQuery.isNotEmpty) {
                  final term = _searchQuery.toLowerCase();
                  filtered = groups
                      .where((g) =>
                          g.name.toLowerCase().contains(term) ||
                          (g.description?.toLowerCase().contains(term) ?? false))
                      .toList();
                }
                if (filtered.isEmpty) {
                  return RefreshIndicator(
                    onRefresh: () async => ref.invalidate(groupListProvider),
                    child: ListView(
                      children: const [
                        SizedBox(height: 200),
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            EmptyState(
                              icon: Icons.group_outlined,
                              title: 'No groups found',
                              subtitle: 'Tap + to create your first group.',
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                }
                return RefreshIndicator(
                  onRefresh: () async => ref.invalidate(groupListProvider),
                  child: ListView.separated(
                    padding: const EdgeInsets.only(bottom: 88),
                    itemCount: filtered.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final group = filtered[index];
                      return ListTile(
                        leading: CircleAvatar(
                          child: Text(group.name[0].toUpperCase()),
                        ),
                        title: Text(group.name),
                        subtitle: group.description != null
                            ? Text(group.description!)
                            : null,
                        onTap: () => context.push('/groups/${group.id}'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit_outlined),
                              tooltip: 'Rename',
                              onPressed: () =>
                                  _showGroupDialog(context, ref, group),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline),
                              tooltip: 'Delete',
                              onPressed: () =>
                                  _confirmDelete(context, ref, group),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showGroupDialog(
      BuildContext context, WidgetRef ref, CustomerGroup? existing) async {
    final nameCtrl =
        TextEditingController(text: existing?.name ?? '');
    final descCtrl =
        TextEditingController(text: existing?.description ?? '');
    final formKey = GlobalKey<FormState>();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(existing == null ? 'New Group' : 'Edit Group'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'Group name'),
                autofocus: true,
                inputFormatters:
                    textFormatters(maxLength: AppConstants.maxGroupNameLength),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Name is required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: descCtrl,
                decoration:
                    const InputDecoration(labelText: 'Description (optional)'),
                maxLines: 2,
                inputFormatters:
                    textFormatters(maxLength: AppConstants.maxGroupDescriptionLength),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () {
                if (formKey.currentState!.validate()) {
                  Navigator.pop(ctx, true);
                }
              },
              child: const Text('Save')),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    final repo = await ref.read(groupRepositoryProvider.future);
    try {
      if (existing == null) {
        await repo.create(
            name: nameCtrl.text, description: descCtrl.text);
      } else {
        await repo.update(existing.copyWith(
            name: nameCtrl.text.trim(),
            description: descCtrl.text.trim().isEmpty
                ? null
                : descCtrl.text.trim()));
      }
      ref.invalidate(groupListProvider);
      ref.invalidate(customerListProvider);
      ref.invalidate(collectionListProvider);
      ref.invalidate(dashboardDataProvider);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _confirmDelete(
      BuildContext context, WidgetRef ref, CustomerGroup group) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete group?'),
        content: Text(
            'Customers in "${group.name}" will be unassigned from this group.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final repo = await ref.read(groupRepositoryProvider.future);
    final memberIds = await repo.delete(group.id);
    ref.invalidate(groupListProvider);
    ref.invalidate(customerListProvider);
    ref.invalidate(collectionListProvider);
    ref.invalidate(dashboardDataProvider);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${group.name} deleted'),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () async {
              final repo = await ref.read(groupRepositoryProvider.future);
              final restored = await repo.create(
                  name: group.name, description: group.description);
              if (memberIds.isNotEmpty) {
                await repo.moveMembers(memberIds, restored.id);
              }
              ref.invalidate(groupListProvider);
              ref.invalidate(customerListProvider);
              ref.invalidate(collectionListProvider);
              ref.invalidate(dashboardDataProvider);
            },
          ),
        ),
      );
    }
  }

  Future<void> _exportGroups() async {
    final groups = ref.read(groupListProvider).valueOrNull;
    if (groups == null || groups.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No groups to export')),
      );
      return;
    }
    try {
      final headers = ['Group Name', 'Description', 'Created Date'];
      final rows = groups.map((g) => [
        g.name,
        g.description ?? '-',
        g.createdAt.split('T').first,
      ]).toList();
      final file = await ExcelExportService.buildXlsx(
        headers: headers,
        rows: rows,
        title: 'Groups Report',
        sheetName: 'Groups',
      );
      await ExcelExportService.shareXlsx(file, 'Groups Report');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export failed: $e')),
        );
      }
    }
  }
}
