import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:loantrack/core/widgets/app_drawer.dart';
import 'package:loantrack/core/widgets/debounced_text_field.dart';
import 'package:loantrack/core/widgets/empty_state.dart';

import '../../../../core/constants/app_constants.dart';
import '../../data/customer_repository.dart';
import '../../data/models/customer_entity.dart';
import '../providers/customer_providers.dart';
import '../../../groups/presentation/providers/group_providers.dart';

class CustomerListScreen extends ConsumerWidget {
  const CustomerListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final customers = ref.watch(customerListProvider);
    final selectedGroup = ref.watch(customerGroupFilterProvider);
    final groupsAsync = ref.watch(groupListProvider);
    final currentPage = ref.watch(customerPageProvider);
    final countAsync = ref.watch(customerCountProvider);

    final totalCount = countAsync.valueOrNull ?? 0;
    final hasMore = (currentPage + 1) * AppConstants.defaultPageSize < totalCount;

    return Scaffold(
      appBar: AppBar(title: const Text('Customers')),
      drawer: const AppDrawer(currentRoute: '/customers'),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/customers/new'),
        icon: const Icon(Icons.person_add),
        label: const Text('Add customer'),
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: DebouncedTextField(
            onChanged: (value) {
              ref.read(customerSearchQueryProvider.notifier).state = value;
              ref.read(customerPageProvider.notifier).state = 0;
            },
            decoration: const InputDecoration(
              labelText: 'Search customers',
              hintText: 'Name, ID, phone, BVN, NIN or address',
              prefixIcon: Icon(Icons.search),
            ),
          ),
        ),
        // Group filter chips
        groupsAsync.when(
          loading: () => const SizedBox.shrink(),
          error: (_, _) => const SizedBox.shrink(),
          data: (groups) {
            if (groups.isEmpty) return const SizedBox.shrink();
            return SizedBox(
              height: 44,
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                scrollDirection: Axis.horizontal,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: FilterChip(
                      label: const Text('All'),
                      selected: selectedGroup == null,
                      onSelected: (_) {
                        ref.read(customerGroupFilterProvider.notifier).state = null;
                        ref.read(customerPageProvider.notifier).state = 0;
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: FilterChip(
                      label: const Text('No group'),
                      selected: selectedGroup == ungroupedGroupFilter,
                      onSelected: (_) {
                        ref.read(customerGroupFilterProvider.notifier).state =
                            selectedGroup == ungroupedGroupFilter
                                ? null
                                : ungroupedGroupFilter;
                        ref.read(customerPageProvider.notifier).state = 0;
                      },
                    ),
                  ),
                  ...groups.map((g) => Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: FilterChip(
                          label: Text(g.name),
                          selected: selectedGroup == g.id,
                          onSelected: (_) {
                            ref.read(customerGroupFilterProvider.notifier).state =
                                selectedGroup == g.id ? null : g.id;
                            ref.read(customerPageProvider.notifier).state = 0;
                          },
                        ),
                      )),
                ],
              ),
            );
          },
        ),
        // Sort selector
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              const Text('Sort by:', style: TextStyle(fontSize: 12)),
              const SizedBox(width: 8),
              Expanded(
                child: Consumer(builder: (context, ref, _) {
                  final sortBy = ref.watch(customerSortByProvider);
                  return DropdownButtonHideUnderline(
                    child: DropdownButton<CustomerSortBy>(
                      value: sortBy,
                      isDense: true,
                      items: const [
                        DropdownMenuItem(
                            value: CustomerSortBy.name, child: Text('Name')),
                        DropdownMenuItem(
                            value: CustomerSortBy.group, child: Text('Group')),
                        DropdownMenuItem(
                            value: CustomerSortBy.amountOwed,
                            child: Text('Amount Owed')),
                      ],
                      onChanged: (value) => ref
                          .read(customerSortByProvider.notifier)
                          .state = value!,
                    ),
                  );
                }),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Expanded(
          child: customers.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) =>
                Center(child: Text('Unable to load customers: $error')),
            data: (items) {
              if (items.isEmpty && currentPage == 0) {
                return const EmptyState(
                  icon: Icons.people_outline,
                  title: 'No customers found',
                  subtitle: 'Add your first customer to get started.',
                );
              }
              if (items.isEmpty && currentPage > 0) {
                ref.read(customerPageProvider.notifier).state = 0;
                return const EmptyState(
                  icon: Icons.people_outline,
                  title: 'No customers found',
                  subtitle: 'Add your first customer to get started.',
                );
              }
              return RefreshIndicator(
                    onRefresh: () async => ref.invalidate(customerListProvider),
                    child: ListView.separated(
                      itemCount: items.length + (hasMore ? 1 : 0),
                      separatorBuilder: (context, index) {
                        if (index == items.length) return const SizedBox.shrink();
                        return const Divider(height: 1);
                      },
                      itemBuilder: (context, index) {
                        if (index == items.length) {
                          return TextButton(
                            onPressed: () {
                              ref.read(customerPageProvider.notifier).state++;
                            },
                            child: const Text('Load more'),
                          );
                        }
                        return _CustomerTile(customer: items[index]);
                      },
                    ),
                  );
            },
          ),
        ),
      ]),
    );
  }
}

class _CustomerTile extends StatelessWidget {
  const _CustomerTile({required this.customer});
  final Customer customer;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: CircleAvatar(
          child: Text(customer.fullName.isEmpty
              ? '?'
              : customer.fullName[0].toUpperCase())),
      title: Text(customer.fullName),
      onTap: () => context.push('/customers/${customer.id}'),
    );
  }
}
