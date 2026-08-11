import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:loantrack/core/constants/app_constants.dart';
import 'package:loantrack/core/utils/date_utils.dart';
import 'package:loantrack/core/utils/input_formatters.dart';
import 'package:loantrack/core/widgets/app_drawer.dart';
import 'package:loantrack/core/widgets/empty_state.dart';
import 'package:loantrack/core/widgets/keyboard_refreshable.dart';
import 'package:loantrack/features/collection/presentation/providers/collection_provider.dart';
import 'package:loantrack/features/dashboard/presentation/providers/dashboard_provider.dart';
import 'package:loantrack/features/holidays/data/models/holiday_entity.dart';
import 'package:loantrack/features/holidays/presentation/providers/holiday_provider.dart';
import 'package:loantrack/features/loans/data/loan_schedule_service.dart';
import 'package:loantrack/features/reports/presentation/providers/report_provider.dart';
import 'package:uuid/uuid.dart';

class HolidayManagementScreen extends ConsumerStatefulWidget {
  const HolidayManagementScreen({super.key});

  @override
  ConsumerState<HolidayManagementScreen> createState() =>
      _HolidayManagementScreenState();
}

class _HolidayManagementScreenState
    extends ConsumerState<HolidayManagementScreen> {
  String _searchQuery = '';
  bool _showCalendar = false;
  int _calendarYear = DateTime.now().year;
  int _calendarMonth = DateTime.now().month;

  @override
  Widget build(BuildContext context) {
    final holidaysAsync = ref.watch(holidayListProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Holiday Management'),
        actions: [
          IconButton(
            icon: Icon(_showCalendar ? Icons.list : Icons.calendar_month),
            tooltip: _showCalendar ? 'List view' : 'Calendar view',
            onPressed: () => setState(() => _showCalendar = !_showCalendar),
          ),
        ],
      ),
      drawer: const AppDrawer(currentRoute: '/holidays'),
      body: holidaysAsync.when(
        data: (holidays) {
          final filtered = _searchQuery.isEmpty
              ? holidays
              : holidays
                    .where(
                      (h) => h.name.toLowerCase().contains(
                        _searchQuery.toLowerCase(),
                      ),
                    )
                    .toList();

          if (_showCalendar) {
            return _buildCalendarView(context, filtered, holidays);
          }
          return _buildListView(context, filtered, holidays);
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Error: $error')),
      ),
      floatingActionButton: _showCalendar
          ? null
          : FloatingActionButton(
              onPressed: () => _showHolidayDialog(context, ref),
              child: const Icon(Icons.add),
            ),
    );
  }

  Widget _buildListView(
    BuildContext context,
    List<Holiday> filtered,
    List<Holiday> allHolidays,
  ) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12.0),
          child: TextField(
            decoration: const InputDecoration(
              hintText: 'Search holidays...',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (value) => setState(() => _searchQuery = value),
          ),
        ),
        Expanded(
          child: filtered.isEmpty
              ? KeyboardRefreshable(
                  onRefresh: () async => ref.invalidate(holidayListProvider),
                  child: ListView(
                    children: const [
                      SizedBox(height: 200),
                      EmptyState(
                        icon: Icons.event_busy_outlined,
                        title: 'No holidays found',
                        subtitle: 'Tap + to add one to get started.',
                      ),
                    ],
                  ),
                )
              : KeyboardRefreshable(
                  onRefresh: () async => ref.invalidate(holidayListProvider),
                  child: ListView.builder(
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final holiday = filtered[index];
                      return _holidayTile(context, holiday);
                    },
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildCalendarView(
    BuildContext context,
    List<Holiday> filtered,
    List<Holiday> allHolidays,
  ) {
    final now = DateTime.now();
    final firstDay = DateTime(_calendarYear, _calendarMonth, 1);
    final lastDay = DateTime(_calendarYear, _calendarMonth + 1, 0);
    final daysInMonth = lastDay.day;
    final startWeekday = firstDay.weekday; // 1=Mon ... 7=Sun

    final holidayDates = <DateTime, List<Holiday>>{};
    for (final h in allHolidays) {
      if (!h.isEnabled) continue;
      if (h.isRecurring) {
        final key = DateTime(_calendarYear, h.date.month, h.date.day);
        if (key.month == _calendarMonth) {
          holidayDates.putIfAbsent(key, () => []).add(h);
        }
      } else {
        if (h.date.year == _calendarYear && h.date.month == _calendarMonth) {
          holidayDates
              .putIfAbsent(
                DateTime(h.date.year, h.date.month, h.date.day),
                () => [],
              )
              .add(h);
        }
      }
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              TextButton.icon(
                onPressed: () {
                  setState(() {
                    if (_calendarMonth == 1) {
                      _calendarMonth = 12;
                      _calendarYear--;
                    } else {
                      _calendarMonth--;
                    }
                  });
                },
                icon: const Icon(Icons.chevron_left),
                label: const Text(''),
              ),
              Text(
                '${_monthName(_calendarMonth)} $_calendarYear',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              TextButton.icon(
                onPressed: () {
                  setState(() {
                    if (_calendarMonth == 12) {
                      _calendarMonth = 1;
                      _calendarYear++;
                    } else {
                      _calendarMonth++;
                    }
                  });
                },
                icon: const Icon(Icons.chevron_right),
                label: const Text(''),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 7,
            childAspectRatio: 1,
            children: [
              for (final day in ['M', 'T', 'W', 'T', 'F', 'S', 'S'])
                Center(
                  child: Text(
                    day,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
              for (int i = 1; i < startWeekday; i++) const SizedBox.shrink(),
              for (int day = 1; day <= daysInMonth; day++) ...[
                _buildDayCell(
                  day,
                  _calendarYear,
                  _calendarMonth,
                  holidayDates,
                  now,
                  allHolidays,
                ),
              ],
            ],
          ),
        ),
        const Divider(),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Icon(Icons.circle, size: 12, color: Colors.red.shade200),
              const SizedBox(width: 6),
              const Text('Holiday', style: TextStyle(fontSize: 12)),
              const SizedBox(width: 16),
              Icon(Icons.circle, size: 12, color: Colors.grey.shade300),
              const SizedBox(width: 6),
              const Text('Weekend', style: TextStyle(fontSize: 12)),
            ],
          ),
        ),
        if (holidayDates.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Holidays this month: ${holidayDates.length}',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.red.shade700,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildDayCell(
    int day,
    int year,
    int month,
    Map<DateTime, List<Holiday>> holidayDates,
    DateTime now,
    List<Holiday> allHolidays,
  ) {
    final date = DateTime(year, month, day);
    final isToday =
        date.year == now.year && date.month == now.month && date.day == now.day;
    final isWeekend = date.weekday == 6 || date.weekday == 7;
    final hasHoliday = holidayDates.containsKey(date);
    final holidaysOnDay = holidayDates[date];

    Color? bgColor;
    if (hasHoliday) {
      bgColor = Colors.red.shade50;
    } else if (isWeekend) {
      bgColor = Colors.grey.shade100;
    }

    return GestureDetector(
      onTap: () {
        if (hasHoliday && holidaysOnDay != null && holidaysOnDay.isNotEmpty) {
          _showHolidayDialog(context, ref, holiday: holidaysOnDay.first);
        } else if (!isWeekend) {
          _showHolidayDialog(context, ref, prefillDate: date);
        }
      },
      child: Container(
        margin: const EdgeInsets.all(1),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(4),
          border: isToday
              ? Border.all(
                  color: Theme.of(context).colorScheme.primary,
                  width: 2,
                )
              : null,
        ),
        child: Center(
          child: Text(
            '$day',
            style: TextStyle(
              fontSize: 13,
              fontWeight: isToday ? FontWeight.w700 : FontWeight.w400,
              color: hasHoliday
                  ? Colors.red.shade800
                  : isWeekend
                  ? Colors.grey
                  : null,
            ),
          ),
        ),
      ),
    );
  }

  String _monthName(int month) {
    const names = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return names[month - 1];
  }

  Widget _holidayTile(BuildContext context, Holiday holiday) {
    return ListTile(
      title: Text(holiday.name),
      subtitle: Text(
        '${AppDateUtils.formatDate(holiday.date)}${holiday.isRecurring ? ' (Recurring)' : ''}',
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Switch(
            value: holiday.isEnabled,
            onChanged: (isEnabled) async {
              final holidayRepository = await ref.read(
                holidayRepositoryProvider.future,
              );
              final result = await holidayRepository.saveHoliday(
                holiday.copyWith(isEnabled: isEnabled),
              );
              result.when(
                success: (_) {
                  ref.invalidate(holidayListProvider);
                  _regenSchedules(ref);
                },
                failure: (failure) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Error: ${failure.message}')),
                    );
                  }
                },
              );
            },
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'edit') {
                _showHolidayDialog(context, ref, holiday: holiday);
              } else if (value == 'delete') {
                _deleteHoliday(context, ref, holiday);
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'edit', child: Text('Edit')),
              PopupMenuItem(value: 'delete', child: Text('Delete')),
            ],
          ),
        ],
      ),
    );
  }

  /// After any holiday change, fully re-derives every loan's repayment
  /// schedule from source data (loan + holidays + completed payments) and
  /// refreshes schedule-dependent screens. Best-effort: a failure here never
  /// blocks the holiday save itself.
  Future<void> _regenSchedules(WidgetRef ref) async {
    try {
      final scheduleService = await ref.read(
        loanScheduleServiceProvider.future,
      );
      await scheduleService.rebuildAllSchedules();
      ref.invalidate(collectionListProvider);
      ref.invalidate(dashboardDataProvider);
      invalidateReportData(ref.invalidate);
    } catch (_) {}
  }

  Future<void> _deleteHoliday(
    BuildContext context,
    WidgetRef ref,
    Holiday holiday,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Holiday?'),
        content: Text('Are you sure you want to delete "${holiday.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final holidayRepository = await ref.read(
        holidayRepositoryProvider.future,
      );
      final result = await holidayRepository.deleteHoliday(holiday.id);
      if (context.mounted) {
        result.when(
          success: (_) {
            ref.invalidate(holidayListProvider);
            _regenSchedules(ref);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('${holiday.name} deleted'),
                action: SnackBarAction(
                  label: 'Undo',
                  onPressed: () async {
                    final repo = await ref.read(
                      holidayRepositoryProvider.future,
                    );
                    await repo.saveHoliday(holiday);
                    ref.invalidate(holidayListProvider);
                    _regenSchedules(ref);
                  },
                ),
              ),
            );
          },
          failure: (failure) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Error: ${failure.message}')),
            );
          },
        );
      }
    }
  }

  void _showHolidayDialog(
    BuildContext context,
    WidgetRef ref, {
    Holiday? holiday,
    DateTime? prefillDate,
  }) {
    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController(text: holiday?.name);
    DateTime selectedDate = holiday?.date ?? prefillDate ?? DateTime.now();
    bool isRecurring = holiday?.isRecurring ?? false;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text(holiday == null ? 'Add Holiday' : 'Edit Holiday'),
              content: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: nameController,
                      decoration: const InputDecoration(
                        labelText: 'Holiday Name',
                      ),
                      inputFormatters: textFormatters(
                        maxLength: AppConstants.maxNameLength,
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please enter a name';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Date'),
                      subtitle: Text(AppDateUtils.formatDate(selectedDate)),
                      trailing: const Icon(Icons.calendar_today),
                      onTap: () async {
                        final pickedDate = await showDatePicker(
                          context: context,
                          initialDate: selectedDate,
                          firstDate: DateTime(2000),
                          lastDate: DateTime(2101),
                        );
                        if (pickedDate != null) {
                          setState(() => selectedDate = pickedDate);
                        }
                      },
                    ),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Recurring Holiday'),
                      subtitle: const Text('Repeats on this date every year'),
                      value: isRecurring,
                      onChanged: (value) =>
                          setState(() => isRecurring = value ?? false),
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
                  onPressed: () async {
                    if (formKey.currentState!.validate()) {
                      final newHoliday = Holiday(
                        id: holiday?.id ?? const Uuid().v4(),
                        name: nameController.text,
                        date: selectedDate,
                        isRecurring: isRecurring,
                        isEnabled: holiday?.isEnabled ?? true,
                      );
                      final holidayRepository = await ref.read(
                        holidayRepositoryProvider.future,
                      );
                      final result = await holidayRepository.saveHoliday(
                        newHoliday,
                      );
                      if (context.mounted) {
                        result.when(
                          success: (_) {
                            ref.invalidate(holidayListProvider);
                            _regenSchedules(ref);
                            Navigator.pop(context);
                          },
                          failure: (failure) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Error: ${failure.message}'),
                              ),
                            );
                          },
                        );
                      }
                    }
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
