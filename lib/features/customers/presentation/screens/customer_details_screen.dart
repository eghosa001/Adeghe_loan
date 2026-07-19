import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/customer_entity.dart';
import '../providers/customer_providers.dart';

class CustomerDetailScreen extends ConsumerWidget {
  const CustomerDetailScreen({super.key, required this.customerId});
  final String customerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final customer = ref.watch(customerProvider(customerId));
    return customer.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (error, _) => Scaffold(
          body: Center(child: Text('Unable to load customer: $error'))),
      data: (item) => item == null
          ? const Scaffold(body: Center(child: Text('Customer not found.')))
          : _CustomerView(customer: item),
    );
  }
}

class _CustomerView extends ConsumerWidget {
  const _CustomerView({required this.customer});
  final Customer customer;

  Future<void> _changeStatus(
      BuildContext context, WidgetRef ref, CustomerStatus status) async {
    await ref
        .read(customerRepositoryProvider)
        .changeStatus(customer.id, status);
    ref.invalidate(customerProvider(customer.id));
    ref.invalidate(customerListProvider);
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete customer?'),
        content: const Text(
            'This permanently deletes the customer and associated local records.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete'))
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(customerRepositoryProvider).delete(customer.id);
    ref.invalidate(customerListProvider);
    if (context.mounted) context.go('/customers');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Customer profile'), actions: [
        IconButton(
            onPressed: () =>
                context.push('/customers/${customer.id}/edit', extra: customer),
            icon: const Icon(Icons.edit),
            tooltip: 'Edit customer'),
        PopupMenuButton<CustomerStatus>(
          onSelected: (status) => _changeStatus(context, ref, status),
          itemBuilder: (context) => [
            const PopupMenuItem(
                value: CustomerStatus.archived,
                child: Text('Archive customer')),
            const PopupMenuItem(
                value: CustomerStatus.blacklisted,
                child: Text('Blacklist customer')),
            const PopupMenuItem(
                value: CustomerStatus.active, child: Text('Mark active')),
          ],
        ),
        IconButton(
            onPressed: () => _delete(context, ref),
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Delete customer'),
      ]),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Center(
            child: CircleAvatar(
                radius: 48,
                backgroundImage: customer.passportPath == null
                    ? null
                    : FileImage(File(customer.passportPath!)),
                child: customer.passportPath == null
                    ? Text(customer.fullName[0].toUpperCase(),
                        style: Theme.of(context).textTheme.headlineMedium)
                    : null)),
        const SizedBox(height: 12),
        Center(
            child: Text(customer.fullName,
                style: Theme.of(context).textTheme.headlineSmall)),
        Center(child: Text(customer.id)),
        const SizedBox(height: 20),
        _Section(title: 'Contact', entries: {
          'Phone': customer.phone,
          'Alternative phone': customer.altPhone,
          'Email': customer.email,
          'Address': customer.residentialAddress,
          'Business address': customer.businessAddress
        }),
        _Section(title: 'Personal & identity', entries: {
          'Gender': customer.gender,
          'Date of birth': customer.dateOfBirth,
          'Occupation': customer.occupation,
          'Employer': customer.employer,
          'NIN': customer.nin,
          'BVN': customer.bvn,
          'ID': [customer.idType, customer.idNumber]
              .whereType<String>()
              .join(' • ')
        }),
        _Section(title: 'Next of kin & guarantors', entries: {
          'Next of kin': customer.nextOfKin,
          'Relationship': customer.nextOfKinRelation,
          'Next of kin phone': customer.nextOfKinPhone,
          'Guarantor 1': customer.guarantor1Name,
          'Guarantor 2': customer.guarantor2Name,
          'Guarantor phone': customer.guarantorPhone,
          'Guarantor address': customer.guarantorAddress
        }),
        _Section(title: 'Account', entries: {
          'Status': customer.status.name,
          'Credit score': customer.creditScore.toStringAsFixed(0),
          'Notes': customer.notes
        }),
        const SizedBox(height: 8),
        Card(
          child: ListTile(
            leading: const Icon(Icons.folder_outlined),
            title: const Text('Documents'),
            subtitle: const Text('View and manage encrypted customer files'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/customers/${customer.id}/documents'),
          ),
        ),
        Card(
          child: ListTile(
            leading: const Icon(Icons.attach_money),
            title: const Text('Issue loan'),
            subtitle: const Text('Create a new loan for this customer'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/customers/${customer.id}/loans/new'),
          ),
        ),
      ]),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.entries});
  final String title;
  final Map<String, String?> entries;

  @override
  Widget build(BuildContext context) {
    final visible = entries.entries
        .where((entry) => entry.value != null && entry.value!.isNotEmpty)
        .toList();
    if (visible.isEmpty) return const SizedBox.shrink();
    return Card(
        child: Padding(
            padding: const EdgeInsets.all(16),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              ...visible.map((entry) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Text('${entry.key}: ${entry.value}')))
            ])));
  }
}
