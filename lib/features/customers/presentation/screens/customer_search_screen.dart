import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/customer_entity.dart';
import '../providers/customer_providers.dart';

class CustomerListScreen extends ConsumerWidget {
  const CustomerListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final customers = ref.watch(customerListProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Customers')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/customers/new'),
        icon: const Icon(Icons.person_add),
        label: const Text('Add customer'),
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(16),
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
      subtitle: Text('${customer.id}\n${customer.phone}'),
      isThreeLine: true,
      trailing: Chip(
          label: Text(customer.status.name),
          labelStyle: TextStyle(color: color)),
      onTap: () => context.push('/customers/${customer.id}'),
    );
  }
}
