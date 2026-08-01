import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/notification_provider.dart';
import '../../data/notification_item.dart';

class NotificationScreen extends ConsumerWidget {
  const NotificationScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifAsync = ref.watch(notificationProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: notifAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (notifications) {
          if (notifications.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.notifications_none, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text('No notifications',
                      style: TextStyle(color: Colors.grey, fontSize: 16)),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: notifications.length,
            itemBuilder: (context, index) {
              final item = notifications[index];
              return _NotificationTile(item: item);
            },
          );
        },
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  final NotificationItem item;

  const _NotificationTile({required this.item});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: CircleAvatar(
        radius: 22,
        backgroundColor: _bgColor(item.icon).withValues(alpha: 0.15),
        child: Icon(_iconData(item.icon), color: _bgColor(item.icon), size: 22),
      ),
      title: Text(item.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(item.body, maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: item.actionRoute != null
          ? const Icon(Icons.chevron_right, size: 18)
          : null,
      onTap: item.actionRoute != null
          ? () => context.push(item.actionRoute!)
          : null,
    );
  }

  IconData _iconData(IconType icon) => switch (icon) {
    IconType.warning => Icons.warning_amber_rounded,
    IconType.info => Icons.info_outline,
    IconType.alert => Icons.error_outline,
    IconType.backup => Icons.cloud_upload_outlined,
    IconType.summary => Icons.bar_chart_rounded,
  };

  Color _bgColor(IconType icon) => switch (icon) {
    IconType.warning => Colors.orange,
    IconType.info => Colors.blue,
    IconType.alert => Colors.red,
    IconType.backup => Colors.teal,
    IconType.summary => Colors.indigo,
  };
}
