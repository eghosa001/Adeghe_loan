import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Daily / Weekly selector shown at the top of both collection screens. The two
/// modules stay on separate routes (`/collections` and `/collections/weekly`)
/// with their own providers and state; this toggle only navigates between them,
/// so the bottom-nav Collections tab reaches either one with a single tap.
class CollectionTypeToggle extends StatelessWidget {
  const CollectionTypeToggle({super.key, required this.isWeekly});

  final bool isWeekly;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: SegmentedButton<bool>(
        segments: const [
          ButtonSegment(value: false, label: Text('Daily')),
          ButtonSegment(value: true, label: Text('Weekly')),
        ],
        selected: {isWeekly},
        showSelectedIcon: false,
        onSelectionChanged: (selection) {
          final goWeekly = selection.first;
          if (goWeekly == isWeekly) return;
          context.go(goWeekly ? '/collections/weekly' : '/collections');
        },
      ),
    );
  }
}
