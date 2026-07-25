import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:loantrack/core/utils/currency_utils.dart';
import 'package:loantrack/core/widgets/app_drawer.dart';

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
          child: TextField(
            onChanged: (value) =>
                ref.read(customerSearchQueryProvider.notifier).state = value,
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
          error: (_, __) => const SizedBox.shrink(),
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
                      onSelected: (_) => ref
                          .read(customerGroupFilterProvider.notifier)
                          .state = null,
                    ),
                  ),
                  ...groups.map((g) => Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: FilterChip(
                          label: Text(g.name),
                          selected: selectedGroup == g.id,
                          onSelected: (_) => ref
                              .read(customerGroupFilterProvider.notifier)
                              .state = selectedGroup == g.id ? null : g.id,
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
            data: (items) => items.isEmpty
                ? const Center(
                    child: Text('No customers found. Add your first customer.'))
                : RefreshIndicator(
                    onRefresh: () async => ref.invalidate(customerListProvider),
                    child: ListView.separated(
                      itemCount: items.length,
                      separatorBuilder: (context, index) =>
                          const Divider(height: 1),
                      itemBuilder: (context, index) =>
                          _CustomerTile(customer: items[index]),
                    ),
                  ),
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
    final color = switch (customer.status) {
      CustomerStatus.active => Colors.green,
      CustomerStatus.closed => Colors.blueGrey,
      CustomerStatus.blacklisted => Theme.of(context).colorScheme.error,
      CustomerStatus.archived => Colors.grey,
    };
    return ListTile(
      leading: CircleAvatar(
          child: Text(customer.fullName.isEmpty
              ? '?'
              : customer.fullName[0].toUpperCase())),
      title: Text(customer.fullName),
      subtitle: Text(
        '${customer.id}\n${customer.phone}'
        '${customer.totalOwed != null && customer.totalOwed! > 0 ? '\nOwed: ${CurrencyUtils.format(customer.totalOwed!)}' : ''}',
      ),
      isThreeLine: customer.totalOwed != null && customer.totalOwed! > 0,
      trailing: Chip(
          label: Text(customer.status.name),
          labelStyle: TextStyle(color: color)),
      onTap: () => context.push('/customers/${customer.id}'),
    );
  }
}
