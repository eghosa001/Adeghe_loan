import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:loantrack/core/widgets/keyboard_scrollable.dart';

import '../../data/global_search_repository.dart';
import '../providers/global_search_provider.dart';

class GlobalSearchScreen extends ConsumerStatefulWidget {
  const GlobalSearchScreen({super.key});

  @override
  ConsumerState<GlobalSearchScreen> createState() => _GlobalSearchScreenState();
}

class _GlobalSearchScreenState extends ConsumerState<GlobalSearchScreen> {
  final _controller = TextEditingController();
  late final FocusNode _focusNode;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focusNode.requestFocus());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final resultsAsync = ref.watch(globalSearchResultsProvider);

    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          focusNode: _focusNode,
          decoration: const InputDecoration(
            hintText: 'Search customers, loans, groups...',
            border: InputBorder.none,
            filled: false,
          ),
          autofocus: true,
          textInputAction: TextInputAction.search,
          onChanged: (value) {
            _debounce?.cancel();
            _debounce = Timer(const Duration(milliseconds: 300), () {
              if (mounted) {
                ref.read(globalSearchQueryProvider.notifier).state = value;
              }
            });
          },
        ),
        actions: [
          if (_controller.text.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.clear),
              onPressed: () {
                _controller.clear();
                ref.read(globalSearchQueryProvider.notifier).state = '';
              },
            ),
        ],
      ),
      body: resultsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Search error: $e')),
        data: (results) {
          final query = ref.watch(globalSearchQueryProvider);
          if (query.trim().isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.search, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text('Type to search across customers,\nloans, and groups',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey, fontSize: 16)),
                ],
              ),
            );
          }

          if (results.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.search_off, size: 64, color: Colors.grey),
                  const SizedBox(height: 16),
                  Text('No results for "$query"',
                      style: const TextStyle(color: Colors.grey, fontSize: 16)),
                ],
              ),
            );
          }

          final customerResults = results.where((r) => r.category == 'customer').toList();
          final loanResults = results.where((r) => r.category == 'loan').toList();
          final groupResults = results.where((r) => r.category == 'group').toList();

          // Flat descriptor list (header label | result item) so only the
          // visible section headers/tiles are built by the lazy ListView.
          final items = <(String?, SearchResultItem?)>[];
          if (customerResults.isNotEmpty) {
            items.add(('Customers (${customerResults.length})', null));
            items.addAll(customerResults.map((r) => (null, r)));
          }
          if (loanResults.isNotEmpty) {
            items.add(('Loans (${loanResults.length})', null));
            items.addAll(loanResults.map((r) => (null, r)));
          }
          if (groupResults.isNotEmpty) {
            items.add(('Groups (${groupResults.length})', null));
            items.addAll(groupResults.map((r) => (null, r)));
          }

          return KeyboardScrollable(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: items.length,
              itemBuilder: (context, index) {
                final (label, item) = items[index];
                if (item == null) {
                  return _SectionHeader(label: label!);
                }
                final icon = switch (item.category) {
                  'customer' => Icons.person_rounded,
                  'loan' => Icons.monetization_on_rounded,
                  _ => Icons.group_rounded,
                };
                return _ResultTile(
                  item: item,
                  icon: icon,
                  onTap: () => context.push(item.route),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String label;
  const _SectionHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(label,
          style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.primary)),
    );
  }
}

class _ResultTile extends StatelessWidget {
  final SearchResultItem item;
  final IconData icon;
  final VoidCallback onTap;

  const _ResultTile({
    required this.item,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: CircleAvatar(
        radius: 20,
        backgroundColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
        child: Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
      ),
      title: Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(item.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: const Icon(Icons.chevron_right, size: 18),
      onTap: onTap,
    );
  }
}
