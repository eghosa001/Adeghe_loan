class NotificationItem {
  final String id;
  final String type;
  final String title;
  final String body;
  final DateTime createdAt;
  final bool read;
  final String? actionRoute;
  final IconType icon;

  const NotificationItem({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.createdAt,
    this.read = false,
    this.actionRoute,
    required this.icon,
  });
}

enum IconType {
  warning,
  info,
  alert,
  backup,
  summary,
}
