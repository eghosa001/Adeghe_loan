import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../data/models/customer_entity.dart';
import '../providers/customer_providers.dart';
import '../../../savings/presentation/screens/savings_section.dart';
import '../../../groups/presentation/providers/group_providers.dart';
import '../../../loans/presentation/providers/loan_providers.dart';
import '../../../loans/data/models/loan_entity.dart';
import 'package:loantrack/core/utils/currency_utils.dart';
import '../../../payments/data/models/payment_entity.dart';
import '../../../payments/presentation/providers/payment_providers.dart';
import '../../../savings/presentation/providers/savings_providers.dart';
import '../../../collection/presentation/providers/collection_provider.dart';
import '../../../dashboard/presentation/providers/dashboard_provider.dart';
import '../../../../core/di/providers.dart';
import '../../../../core/widgets/keyboard_scrollable.dart';
import '../../../business/presentation/providers/business_providers.dart';
import '../../../reports/presentation/providers/report_provider.dart';

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

class _CustomerView extends ConsumerStatefulWidget {
  const _CustomerView({required this.customer});
  final Customer customer;

  @override
  ConsumerState<_CustomerView> createState() => _CustomerViewState();
}

class _CustomerViewState extends ConsumerState<_CustomerView>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _changeStatus(CustomerStatus status) async {
    try {
      final repo = await ref.read(customerRepositoryProvider.future);
      await repo.changeStatus(widget.customer.id, status);
      logAuditAction(ref, 'UPDATE',
          'Customer ${widget.customer.fullName} (${widget.customer.id}) status changed to ${status.value}');
      ref.invalidate(customerProvider(widget.customer.id));
      ref.invalidate(customerListProvider);
      ref.invalidate(customerCountProvider);
      ref.invalidate(dashboardDataProvider);
      ref.invalidate(collectionListProvider);
      invalidateReportData(ref.invalidate);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update status: $e')),
        );
      }
    }
  }

  Future<void> _printStatement() async {
    try {
      final statementService = await ref.read(statementServiceProvider.future);
      await statementService.printCustomerStatement(widget.customer.id);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to print statement: $e')),
        );
      }
    }
  }

  Future<void> _delete(BuildContext context) async {
    final customer = widget.customer;
    final isArchived = customer.status == CustomerStatus.archived;

    if (isArchived) {
      // For archived customers, offer permanent deletion
      final action = await showDialog<int>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Delete permanently?'),
          content: const Text(
              'This will PERMANENTLY delete the customer and ALL their data '
              '(loans, payments, savings, documents). This cannot be undone.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, 0),
                child: const Text('Cancel')),
            TextButton(
                onPressed: () => Navigator.pop(context, 1),
                child: const Text('Unarchive instead')),
            FilledButton(
                style: FilledButton.styleFrom(backgroundColor: Colors.red),
                onPressed: () => Navigator.pop(context, 2),
                child: const Text('Delete permanently')),
          ],
        ),
      );

      if (action == 0 || action == null) return;
      if (action == 1) {
        // Unarchive
        await _changeStatus(CustomerStatus.active);
        return;
      }
      // action == 2: permanent delete
      if (!mounted) return;
      _hardDelete();
      return;
    }

    // For non-archived customers, offer archive
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Archive customer?'),
        content: const Text(
            'This archives the customer. Their loans, payments and savings '
            'history are preserved and can be restored later.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Archive'))
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final repo = await ref.read(customerRepositoryProvider.future);
      await repo.delete(customer.id);
      logAuditAction(ref, 'DELETE',
          'Customer ${customer.fullName} (${customer.id}) archived');
      ref.invalidate(customerListProvider);
      ref.invalidate(customerCountProvider);
      ref.invalidate(dashboardDataProvider);
      ref.invalidate(collectionListProvider);
      invalidateReportData(ref.invalidate);
      ref.invalidate(savingsBalanceProvider(customer.id));
      ref.invalidate(savingsTransactionsProvider(customer.id));
      ref.invalidate(allSavingsAccountsProvider);
      ref.invalidate(allAccountsWithNamesProvider);
      if (!mounted) return;
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${customer.fullName} archived')),
        );
        context.go('/customers');
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to archive customer: $e')),
        );
      }
    }
  }

  Future<void> _hardDelete() async {
    final customer = widget.customer;
    try {
      final repo = await ref.read(customerRepositoryProvider.future);
      await repo.hardDelete(customer.id);
      logAuditAction(ref, 'DELETE',
          'Customer ${customer.fullName} (${customer.id}) permanently deleted');
      ref.invalidate(customerListProvider);
      ref.invalidate(customerCountProvider);
      ref.invalidate(dashboardDataProvider);
      ref.invalidate(collectionListProvider);
      invalidateReportData(ref.invalidate);
      ref.invalidate(savingsBalanceProvider(customer.id));
      ref.invalidate(savingsTransactionsProvider(customer.id));
      ref.invalidate(allSavingsAccountsProvider);
      ref.invalidate(allAccountsWithNamesProvider);
      if (!mounted) return;
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${customer.fullName} permanently deleted')),
        );
        context.go('/customers');
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete customer: $e')),
        );
      }
    }
  }

  Future<void> _changeGroup(CustomerGroup? group) async {
    try {
      final repo = await ref.read(customerRepositoryProvider.future);
      await repo.changeGroup(widget.customer.id, group?.id);
      ref.invalidate(customerProvider(widget.customer.id));
      ref.invalidate(customerListProvider);
      ref.invalidate(customerCountProvider);
      ref.invalidate(collectionListProvider);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to change group: $e')),
        );
      }
    }
  }

  void _showGroupDialog() {
    final groupsAsync = ref.read(groupListProvider);
    final groups = groupsAsync.valueOrNull ?? [];
    showDialog(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Switch group'),
        children: [
          SimpleDialogOption(
            onPressed: () {
              Navigator.pop(context);
              _changeGroup(null);
            },
            child: const Text('— No group —'),
          ),
          ...groups.map((g) => SimpleDialogOption(
                onPressed: () {
                  Navigator.pop(context);
                  _changeGroup(g);
                },
                child: Text(g.name),
              )),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final customer = widget.customer;
    // Resolve group name if set
    final groupAsync = customer.groupId != null
        ? ref.watch(groupListProvider)
        : const AsyncValue<List<CustomerGroup>>.data([]);
    final groupName = groupAsync.valueOrNull
        ?.where((g) => g.id == customer.groupId)
        .firstOrNull
        ?.name;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Customer profile'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.person_outline), text: 'Profile'),
            Tab(icon: Icon(Icons.savings_outlined), text: 'Savings'),
          ],
        ),
        actions: [
          PopupMenuButton<MenuAction>(
            onSelected: (action) {
              switch (action) {
                case MenuAction.edit:
                  context.push('/customers/${customer.id}/edit',
                      extra: customer);
                case MenuAction.archive:
                  _delete(context);
                case MenuAction.hardDelete:
                  _delete(context); // _delete now handles both archive and hard delete
                case MenuAction.blacklist:
                  _changeStatus(CustomerStatus.blacklisted);
                case MenuAction.activate:
                  _changeStatus(CustomerStatus.active);
                case MenuAction.switchGroup:
                  _showGroupDialog();
                case MenuAction.printStatement:
                  _printStatement();
              }
            },
            itemBuilder: (context) {
              final isArchived = customer.status == CustomerStatus.archived;
              return [
                const PopupMenuItem(
                    value: MenuAction.edit, child: Text('Edit customer')),
                const PopupMenuItem(
                    value: MenuAction.switchGroup,
                    child: Text('Switch group')),
                const PopupMenuItem(
                    value: MenuAction.printStatement,
                    child: Text('Print statement')),
                const PopupMenuDivider(),
                if (isArchived) ...[
                  const PopupMenuItem(
                      value: MenuAction.hardDelete,
                      child: Text('Delete permanently',
                          style: TextStyle(color: Colors.red))),
                  const PopupMenuItem(
                      value: MenuAction.activate, child: Text('Unarchive')),
                ] else ...[
                  const PopupMenuItem(
                      value: MenuAction.archive,
                      child: Text('Archive customer')),
                  const PopupMenuItem(
                      value: MenuAction.blacklist,
                      child: Text('Blacklist customer')),
                  const PopupMenuItem(
                      value: MenuAction.activate, child: Text('Mark active')),
                ],
              ];
            },
          ),
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _ProfileTab(customer: customer, groupName: groupName),
          _SavingsTab(customerId: customer.id),
        ],
      ),
    );
  }
}

class _ProfileTab extends ConsumerWidget {
  const _ProfileTab({required this.customer, this.groupName});
  final Customer customer;
  final String? groupName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeLoans = ref.watch(activeLoansForCustomerProvider(customer.id));

    return KeyboardScrollable(
      child: ListView(padding: const EdgeInsets.all(16), children: [
        Center(
            child: CircleAvatar(
                radius: 48,
                backgroundImage: customer.passportPath == null
                    ? null
                    : FileImage(File(customer.passportPath!)),
                child: customer.passportPath == null
                    ? Text(
                        (customer.fullName.isEmpty
                                ? '?'
                                : customer.fullName[0])
                            .toUpperCase(),
                        style: Theme.of(context).textTheme.headlineMedium)
                    : null)),
        const SizedBox(height: 12),
      Center(
          child: Text(customer.fullName,
              style: Theme.of(context).textTheme.headlineSmall)),
      Center(
        child: Text(
          customer.id,
          style: Theme.of(context).textTheme.bodySmall,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      if (groupName != null) ...[
        const SizedBox(height: 4),
        Center(
          child: Chip(
            avatar: const Icon(Icons.group_outlined, size: 16),
            label: Text(groupName!),
            visualDensity: VisualDensity.compact,
          ),
        ),
      ],
      const SizedBox(height: 20),

      // Active Loans section
      activeLoans.when(
        loading: () => const SizedBox.shrink(),
        error: (e, _) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            'Could not load active loans: $e',
            style: TextStyle(
              color: Theme.of(context).colorScheme.error,
            ),
          ),
        ),
        data: (loans) {
          if (loans.isEmpty) return const SizedBox.shrink();
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                   Text('Active Loans',
                       style: Theme.of(context).textTheme.titleMedium),
                   const SizedBox(height: 8),
                   ListView.builder(
                     shrinkWrap: true,
                     physics: const NeverScrollableScrollPhysics(),
                     itemCount: loans.length,
                     itemBuilder: (context, i) => _LoanTile(loan: loans[i]),
                   ),
                ],
              ),
            ),
          );
        },
      ),

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
        'NIN': customer.nin,
        'BVN': customer.bvn,
      }),
      _GuarantorSection(customer: customer),
      _Section(title: 'Account', entries: {
        'Status': customer.status.name,
        'Group': groupName,
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

class _LoanTile extends ConsumerWidget {
  const _LoanTile({required this.loan});
  final Loan loan;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(
        '${loan.loanType.name.toUpperCase()} loan — ${CurrencyUtils.format(loan.amount)}',
      ),
      subtitle: Text(
        'Outstanding: ${CurrencyUtils.format(loan.outstandingBalance)}',
      ),
      trailing: FilledButton.tonal(
        onPressed: () => _quickPay(context, ref),
        child: const Text('Pay'),
      ),
    );
  }

  void _quickPay(BuildContext context, WidgetRef ref) {
    final installment = loan.installmentAmount;
    final outstanding = loan.outstandingBalance;
    final amount = installment > 0 && installment <= outstanding
        ? installment
        : outstanding;

    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.bolt),
              title: const Text('Quick Pay'),
              subtitle: Text('Pay ${CurrencyUtils.format(amount)}'),
              onTap: () {
                Navigator.pop(ctx);
                _recordPayment(context, ref, amount);
              },
            ),
            ListTile(
              leading: const Icon(Icons.savings_outlined),
              title: const Text('Clear with Savings'),
              subtitle: const Text('Deduct outstanding from savings'),
              onTap: () {
                Navigator.pop(ctx);
                _clearWithSavings(context, ref);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _recordPayment(
      BuildContext context, WidgetRef ref, double amount) async {
    try {
      final repo = await ref.read(paymentRepositoryProvider.future);
      final collectorName =
          ref.read(businessProfileProvider).valueOrNull?.ownerName ?? 'Admin';
      await repo.createPayment(
        loanId: loan.id,
        customerId: loan.customerId,
        amount: amount,
        method: PaymentMethod.cash,
        collector: collectorName,
        clientRequestId: const Uuid().v4(),
      );
      ref.invalidate(activeLoansForCustomerProvider(loan.customerId));
      ref.invalidate(loanDetailsProvider(loan.id));
      ref.invalidate(loanScheduleProvider(loan.id));
      ref.invalidate(dashboardDataProvider);
      ref.invalidate(collectionListProvider);
      ref.invalidate(weeklyCollectionListProvider);
      invalidateReportData(ref.invalidate);
      ref.invalidate(futureScheduleProvider);
      ref.invalidate(savingsBalanceProvider(loan.customerId));
      ref.invalidate(savingsTransactionsProvider(loan.customerId));
      ref.invalidate(paymentsForLoanProvider(loan.id));
      ref.invalidate(customerProvider(loan.customerId));
      ref.invalidate(allSavingsAccountsProvider);
      ref.invalidate(allAccountsWithNamesProvider);
      ref.invalidate(customerListProvider);
      ref.invalidate(allLoansProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Paid ${CurrencyUtils.format(amount)}')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Payment failed: $e')),
        );
      }
    }
  }

  Future<void> _clearWithSavings(BuildContext context, WidgetRef ref) async {
    final double savingsBalance;
    try {
      savingsBalance =
          await ref.read(savingsBalanceProvider(loan.customerId).future);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to load savings balance.')),
        );
      }
      return;
    }

    if (!context.mounted) return;

    if (savingsBalance < loan.outstandingBalance) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
          'Insufficient savings (${CurrencyUtils.format(savingsBalance)}) '
          'to clear this loan (${CurrencyUtils.format(loan.outstandingBalance)})',
        ),
        backgroundColor: Colors.orange,
      ));
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear loan with savings?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Outstanding: ${CurrencyUtils.format(loan.outstandingBalance)}'),
            const SizedBox(height: 4),
            Text('Savings: ${CurrencyUtils.format(savingsBalance)}'),
            const SizedBox(height: 12),
            const Text(
              'This will deduct from savings and mark the loan as completed.',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    try {
      final repo = await ref.read(paymentRepositoryProvider.future);
      await repo.clearLoanWithSavings(
        loanId: loan.id,
        customerId: loan.customerId,
      );
      ref.invalidate(activeLoansForCustomerProvider(loan.customerId));
      ref.invalidate(loanDetailsProvider(loan.id));
      ref.invalidate(loanScheduleProvider(loan.id));
      ref.invalidate(savingsBalanceProvider(loan.customerId));
      ref.invalidate(savingsTransactionsProvider(loan.customerId));
      ref.invalidate(allSavingsAccountsProvider);
      ref.invalidate(allAccountsWithNamesProvider);
      ref.invalidate(dashboardDataProvider);
      ref.invalidate(collectionListProvider);
      invalidateReportData(ref.invalidate);
      ref.invalidate(futureScheduleProvider);
      ref.invalidate(weeklyCollectionListProvider);
      ref.invalidate(paymentsForLoanProvider(loan.id));
      ref.invalidate(customerProvider(loan.customerId));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Loan cleared with savings.')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e')),
        );
      }
    }
  }
}

class _SavingsTab extends StatelessWidget {
  const _SavingsTab({required this.customerId});
  final String customerId;

  @override
  Widget build(BuildContext context) {
    return KeyboardScrollable(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [SavingsSection(customerId: customerId)],
      ),
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

class _GuarantorSection extends StatelessWidget {
  const _GuarantorSection({required this.customer});
  final Customer customer;

  @override
  Widget build(BuildContext context) {
    final hasG1 = customer.guarantor1Name?.isNotEmpty == true;
    final hasG2 = customer.guarantor2Name?.isNotEmpty == true;
    if (!hasG1 && !hasG2) return const SizedBox.shrink();
    return Card(
        child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Guarantors',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  if (hasG1) ...[
                    Text(customer.guarantor1Name!,
                        style: Theme.of(context).textTheme.titleSmall),
                    if (customer.guarantor1Phone?.isNotEmpty == true)
                      Text('Phone: ${customer.guarantor1Phone}'),
                    if (customer.guarantor1Address?.isNotEmpty == true)
                      Text('Address: ${customer.guarantor1Address}'),
                  ],
                  if (hasG1 && hasG2) const SizedBox(height: 12),
                  if (hasG2) ...[
                    Text(customer.guarantor2Name!,
                        style: Theme.of(context).textTheme.titleSmall),
                    if (customer.guarantor2Phone?.isNotEmpty == true)
                      Text('Phone: ${customer.guarantor2Phone}'),
                    if (customer.guarantor2Address?.isNotEmpty == true)
                      Text('Address: ${customer.guarantor2Address}'),
                  ],
                ])));
  }
}

enum MenuAction {
  edit,
  switchGroup,
  printStatement,
  archive,
  hardDelete,
  blacklist,
  activate,
}
