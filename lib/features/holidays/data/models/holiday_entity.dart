import 'package:loantrack/core/utils/date_utils.dart';

class Holiday {
  final String id;
  final String name;
  final DateTime date;
  final bool isRecurring;
  final bool isEnabled;

  Holiday({
    required this.id,
    required this.name,
    required this.date,
    this.isRecurring = false,
    this.isEnabled = true,
  });

  Holiday copyWith({
    String? id,
    String? name,
    DateTime? date,
    bool? isRecurring,
    bool? isEnabled,
  }) {
    return Holiday(
      id: id ?? this.id,
      name: name ?? this.name,
      date: date ?? this.date,
      isRecurring: isRecurring ?? this.isRecurring,
      isEnabled: isEnabled ?? this.isEnabled,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'date': AppDateUtils.formatForStorage(date),
      'is_recurring': isRecurring ? 1 : 0,
      'is_enabled': isEnabled ? 1 : 0,
    };
  }

  factory Holiday.fromMap(Map<String, dynamic> map) {
    return Holiday(
      id: map['id'] as String,
      name: map['name'] as String,
      date: AppDateUtils.tryParseStorage(map['date'] as String) ?? DateTime.now(),
      isRecurring: map['is_recurring'] == 1,
      isEnabled: map['is_enabled'] == 1,
    );
  }
}
