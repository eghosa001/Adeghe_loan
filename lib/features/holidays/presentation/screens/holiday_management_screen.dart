import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:loantrack/core/utils/date_utils.dart';
import 'package:loantrack/core/widgets/app_drawer.dart';
import 'package:loantrack/features/holidays/data/models/holiday_entity.dart';
import 'package:loantrack/features/holidays/presentation/providers/holiday_provider.dart';
import 'package:uuid/uuid.dart';

class HolidayManagementScreen extends ConsumerWidget {
  const HolidayManagementScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final holidaysAsync = ref.watch(holidayListProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Holiday Management'),
      ),
      drawer: const AppDrawer(currentRoute: '/holidays'),
      body: holidaysAsync.when(
        data: (holidays) {
          if (holidays.isEmpty) {
            return const Center(
              child: Text('No holidays defined. Add one to get started.'),
            );
          }
          return ListView.builder(
            itemCount: holidays.length,
            itemBuilder: (context, index) {
              final holiday = holidays[index];
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
                        final holidayRepository =
                            await ref.read(holidayRepositoryProvider.future);
                        final result = await holidayRepository
                            .saveHoliday(holiday.copyWith(isEnabled: isEnabled));

                        result.when(
                          success: (_) => ref.invalidate(holidayListProvider),
                          failure: (failure) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                    content: Text(
                                        'Error: ${failure.message}')),
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
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Error: $error')),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showHolidayDialog(context, ref),
        child: const Icon(Icons.add),
      ),
    );
  }

  Future<void> _deleteHoliday(
      BuildContext context, WidgetRef ref, Holiday holiday) async {
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
      final holidayRepository =
          await ref.read(holidayRepositoryProvider.future);
      final result = await holidayRepository.deleteHoliday(holiday.id);
      if (context.mounted) {
        result.when(
          success: (_) => ref.invalidate(holidayListProvider),
          failure: (failure) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Error: ${failure.message}')),
            );
          },
        );
      }
    }
  }

  void _showHolidayDialog(BuildContext context, WidgetRef ref,
      {Holiday? holiday}) {
    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController(text: holiday?.name);
    DateTime selectedDate = holiday?.date ?? DateTime.now();
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
                      decoration:
                          const InputDecoration(labelText: 'Holiday Name'),
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
                      onChanged: (value) => setState(() => isRecurring = value ?? false),
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
                      final holidayRepository =
                          await ref.read(holidayRepositoryProvider.future);
                      final result = await holidayRepository.saveHoliday(newHoliday);
                      if (context.mounted) {
                        result.when(
                          success: (_) {
                            ref.invalidate(holidayListProvider);
                            Navigator.pop(context);
                          },
                          failure: (failure) {
                            ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Error: ${failure.message}')));
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
