import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/group_providers.dart';

class GroupManagementScreen extends ConsumerWidget {
  const GroupManagementScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groupsAsync = ref.watch(groupListProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Customer Groups')),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.group_add),
        label: const Text('New group'),
        onPressed: () => _showGroupDialog(context, ref),
      ),
      body: groupsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (groups) => groups.isEmpty
            ? const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.group_outlined, size: 64, color: Colors.grey),
                    SizedBox(height: 12),
                    Text('No groups yet.\nTap + to create your first group.',
                        textAlign: TextAlign.center),
                  ],
                ),
              )
            : ListView.separated(
                padding: const EdgeInsets.only(bottom: 88),
                itemCount: groups.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final g = groups[i];
                  return ListTile(
                    leading: CircleAvatar(
                      child: Text(g.name[0].toUpperCase()),
                    ),
                    title: Text(g.name),
                    subtitle: g.description != null ? Text(g.description!) : null,
                    trailing: PopupMenuButton<_GroupAction>(
                      onSelected: (action) {
                        if (action == _GroupAction.edit) {
                          _showGroupDialog(context, ref, group: g);
                        } else {
                          _confirmDelete(context, ref, g.id, g.name);
                        }
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(
                            value: _GroupAction.edit, child: Text('Edit')),
                        PopupMenuItem(
                            value: _GroupAction.delete, child: Text('Delete')),
                      ],
                    ),
                  );
                },
              ),
      ),
    );
  }

  void _showGroupDialog(BuildContext context, WidgetRef ref,
      {CustomerGroup? group}) {
    final nameCtrl = TextEditingController(text: group?.name ?? '');
    final descCtrl = TextEditingController(text: group?.description ?? '');
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(group == null ? 'New Group' : 'Edit Group'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(labelText: 'Group name *'),
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: descCtrl,
              decoration: const InputDecoration(labelText: 'Description (optional)'),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final name = nameCtrl.text.trim();
              if (name.isEmpty) return;
              final repo = ref.read(groupRepositoryProvider);
              if (group == null) {
                await repo.create(name, description: descCtrl.text);
              } else {
                await repo.update(group.id,
                    name: name, description: descCtrl.text);
              }
              ref.invalidate(groupListProvider);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(
      BuildContext context, WidgetRef ref, String id, String name) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete group?'),
        content: Text(
            '"$name" will be deleted. Customers in this group will be unassigned.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              await ref.read(groupRepositoryProvider).delete(id);
              ref.invalidate(groupListProvider);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

enum _GroupAction { edit, delete }
