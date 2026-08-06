import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:open_filex/open_filex.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/date_utils.dart';
import '../../../business/presentation/providers/business_providers.dart';
import '../../services/export_manager.dart';

/// Runs a generic report export (save PDF / share Excel / print) with the
/// business branding loaded from the current profile, then surfaces a result
/// snackbar. Used by every per-report screen's export bar.
Future<void> runReportExport({
  required BuildContext context,
  required WidgetRef ref,
  required String action,
  required ReportExportData data,
}) async {
  final profile = ref.read(businessProfileProvider).valueOrNull;
  try {
     if (action == 'pdf') {
       await ExportManager.shareReportPdf(data, profile: profile);
    } else if (action == 'excel') {
      final file = await ExportManager.exportReportToXlsx(data);
      final opened = await OpenFilex.open(file.path);
      if (context.mounted) {
        final name = file.path.split(RegExp(r'[/\\]')).last;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(opened.type == ResultType.done
                ? 'Excel opened: $name'
                : 'Excel saved to downloads: $name')));
      }
    } else if (action == 'print') {
      await ExportManager.printReportPdf(data, profile: profile);
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export failed: $e')));
    }
  }
}

/// Shared building blocks for the redesigned Reports module: a consistent
/// screen shell, the reusable period selector, small metric cards, the
/// branded export action bar and the responsive sticky-header data table.

class ReportScreenShell extends StatelessWidget {
  const ReportScreenShell({
    super.key,
    required this.title,
    this.subtitle,
    this.actions = const [],
    this.onBack,
    required this.children,
  });

  final String title;
  final String? subtitle;
  final List<Widget> actions;

  /// When provided, renders a back button that calls this callback instead of
  /// the default GoRouter back.
  final VoidCallback? onBack;

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: 'Back',
          onPressed: onBack ??
              () {
                if (Navigator.of(context).canPop()) {
                  Navigator.of(context).pop();
                }
              },
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(title),
            if (subtitle != null)
              Text(
                subtitle!,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
        actions: actions,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: children,
        ),
      ),
    );
  }
}

/// A date range reported against. Mirrors the dashboard preset semantics so a
/// report's period label reads naturally ("This Month" vs "01 Jul - 31 Jul").
class ReportPeriod {
  const ReportPeriod(this.start, this.end, this.label);

  final DateTime start;
  final DateTime end;
  final String label;
}

/// Self-contained preset + custom date-range selector. Calls [onChanged] with
/// the effective range whenever the selection changes. Defaults to this month.
class ReportPeriodSelector extends StatefulWidget {
  const ReportPeriodSelector({
    super.key,
    required this.onChanged,
    this.compact = false,
  });

  final ValueChanged<ReportPeriod> onChanged;
  final bool compact;

  @override
  State<ReportPeriodSelector> createState() => _ReportPeriodSelectorState();
}

class _ReportPeriodSelectorState extends State<ReportPeriodSelector> {
  static final _presets = <(String, DateTime Function(DateTime))>[
    ('Today', (now) => now),
    ('Yesterday', (now) => now.subtract(const Duration(days: 1))),
    ('This Week', AppDateUtils.startOfWeek),
    ('Last Week',
        (now) => AppDateUtils.startOfWeek(now).subtract(const Duration(days: 7))),
    ('This Month', AppDateUtils.startOfMonth),
    ('Last Month', (now) => DateTime(now.year, now.month - 1, 1)),
    ('Last 30 Days', (now) => now.subtract(const Duration(days: 29))),
  ];

  String? _selectedPreset;
  DateTime? _customStart;
  DateTime? _customEnd;

  @override
  void initState() {
    super.initState();
    _applyPreset('This Month');
  }

  void _applyPreset(String label) {
    final now = DateTime.now();
    final start = switch (label) {
      'Today' => AppDateUtils.startOfDay(now),
      'Yesterday' => AppDateUtils.startOfDay(now.subtract(const Duration(days: 1))),
      'This Week' => AppDateUtils.startOfWeek(now),
      'Last Week' => AppDateUtils.startOfWeek(now).subtract(const Duration(days: 7)),
      'This Month' => AppDateUtils.startOfMonth(now),
      'Last Month' => DateTime(now.year, now.month - 1, 1),
      'Last 30 Days' => AppDateUtils.startOfDay(now.subtract(const Duration(days: 29))),
      _ => AppDateUtils.startOfDay(now),
    };
    final end = switch (label) {
      'Today' || 'Yesterday' => AppDateUtils.endOfDay(now),
      'This Week' || 'Last Week' => AppDateUtils.endOfDay(start.add(const Duration(days: 6))),
      'This Month' => AppDateUtils.endOfMonth(now),
      'Last Month' => AppDateUtils.endOfDay(
          DateTime(now.year, now.month, 0)),
      'Last 30 Days' => AppDateUtils.endOfDay(now),
      _ => AppDateUtils.endOfDay(now),
    };
    setState(() {
      _selectedPreset = label;
      _customStart = null;
      _customEnd = null;
    });
    widget.onChanged(ReportPeriod(start, end, label));
  }

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final start = _customStart ?? AppDateUtils.startOfMonth(now);
    final end = _customEnd ?? AppDateUtils.endOfDay(now);
    final pickedStart = await showDatePicker(
      context: context,
      initialDate: start,
      firstDate: DateTime(now.year - 10),
      lastDate: now,
    );
    if (pickedStart == null || !mounted) return;
    final pickedEnd = await showDatePicker(
      context: context,
      initialDate: end.isBefore(pickedStart) ? pickedStart : end,
      firstDate: DateTime(now.year - 10),
      lastDate: now,
    );
    if (pickedEnd == null || !mounted) return;
    setState(() {
      _selectedPreset = null;
      _customStart = AppDateUtils.startOfDay(pickedStart);
      _customEnd = AppDateUtils.endOfDay(pickedEnd);
    });
    widget.onChanged(ReportPeriod(
      AppDateUtils.startOfDay(pickedStart),
      AppDateUtils.endOfDay(pickedEnd),
      '${AppDateUtils.formatDate(pickedStart)} - ${AppDateUtils.formatDate(pickedEnd)}',
    ));
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final chips = Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final preset in _presets)
          ChoiceChip(
            label: Text(preset.$1),
            selected: _selectedPreset == preset.$1,
            onSelected: (_) => _applyPreset(preset.$1),
            showCheckmark: false,
            selectedColor: colorScheme.primary.withValues(alpha: 0.12),
            labelStyle: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: _selectedPreset == preset.$1
                  ? colorScheme.primary
                  : colorScheme.onSurfaceVariant,
            ),
          ),
        ChoiceChip(
          label: const Text('Custom'),
          selected: _selectedPreset == null,
          onSelected: (_) => _pickRange(),
          showCheckmark: false,
          avatar: const Icon(Icons.date_range, size: 16),
          selectedColor: colorScheme.primary.withValues(alpha: 0.12),
          labelStyle: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: _selectedPreset == null
                ? colorScheme.primary
                : colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );

    if (widget.compact) return chips;

    final label = _selectedPreset ?? 'Custom Range';
    final rangeLabel = _selectedPreset == null && _customStart != null
        ? '${AppDateUtils.formatDate(_customStart!)} - ${AppDateUtils.formatDate(_customEnd!)}'
        : label;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.calendar_month, size: 18, color: colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Report Period',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: colorScheme.primary,
                  ),
                ),
                const Spacer(),
                Text(
                  rangeLabel,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            chips,
          ],
        ),
      ),
    );
  }
}

/// Small metric card used in summary strips above report tables.
class ReportMetricCard extends StatelessWidget {
  const ReportMetricCard({
    super.key,
    required this.label,
    required this.value,
    this.icon,
    this.accent = false,
  });

  final String label;
  final String value;
  final IconData? icon;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: accent ? AppTheme.accentGradient : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (icon != null) ...[
                  Icon(icon,
                      size: 16,
                      color: accent
                          ? AppTheme.primaryColor
                          : colorScheme.primary.withValues(alpha: 0.7)),
                  const SizedBox(width: 6),
                ],
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: accent
                          ? AppTheme.primaryColor
                          : colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: accent
                    ? AppTheme.primaryColor
                    : colorScheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Horizontal summary strip of [ReportMetricCard]s that wraps on narrow
/// screens. Tiles have a fixed width so a strip reads like a KPI dashboard.
class ReportMetricStrip extends StatelessWidget {
  const ReportMetricStrip({
    super.key,
    required this.cards,
    this.tileWidth = 180,
    this.height = 110,
  });

  final List<ReportMetricCard> cards;
  final double tileWidth;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (final card in cards)
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: SizedBox(width: tileWidth, child: card),
            ),
        ],
      ),
    );
  }
}

/// Branded export action bar: PDF (save), Excel (share), Print.
class ReportExportBar extends StatelessWidget {
  const ReportExportBar({
    super.key,
    required this.onSavePdf,
    required this.onExcel,
    required this.onPrint,
    this.enabled = true,
  });

  final VoidCallback onSavePdf;
  final VoidCallback onExcel;
  final VoidCallback onPrint;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    Widget button(IconData icon, String label, VoidCallback onPressed) {
      return Expanded(
        child: FilledButton.tonalIcon(
          onPressed: enabled ? onPressed : null,
          icon: Icon(icon, size: 18),
          label: Text(label),
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 12),
          ),
        ),
      );
    }

    return Row(
      children: [
        button(Icons.picture_as_pdf_rounded, 'PDF', onSavePdf),
        const SizedBox(width: 8),
        button(Icons.table_chart_rounded, 'Excel', onExcel),
        const SizedBox(width: 8),
        button(Icons.print_rounded, 'Print', onPrint),
      ],
    );
  }
}

/// Responsive table with a sticky header. The header row stays fixed while
/// body rows scroll vertically, and the header + body share one horizontal
/// scroll so headers stay in sync when swiping on narrow screens. Values are
/// pre-formatted display strings.
class ReportDataTable extends StatefulWidget {
  const ReportDataTable({
    super.key,
    required this.columns,
    required this.rows,
    this.rightAlignColumns = const [],
    this.totalsRow,
    this.emptyMessage = 'No records match the current filters.',
  });

  final List<String> columns;
  final List<List<String>> rows;
  final List<int> rightAlignColumns;
  final List<String>? totalsRow;
  final String emptyMessage;

  @override
  State<ReportDataTable> createState() => _ReportDataTableState();
}

class _ReportDataTableState extends State<ReportDataTable> {
  final ScrollController _horizontalController = ScrollController();

  @override
  void dispose() {
    _horizontalController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      child: Scrollbar(
        controller: _horizontalController,
        notificationPredicate: (notification) =>
            notification.depth == 0,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          controller: _horizontalController,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _headerRow(context),
              if (widget.rows.isEmpty)
                SizedBox(
                  width: widget.columns.length * 140.0,
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(
                      widget.emptyMessage,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 13,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                )
              else
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.55,
                  ),
                  child: Scrollbar(
                    child: SingleChildScrollView(
                      child: Column(
                        children: [
                          for (var i = 0; i < widget.rows.length; i++)
                            _dataRow(
                                context, widget.rows[i], i.isEven),
                        ],
                      ),
                    ),
                  ),
                ),
              if (widget.totalsRow != null)
                Container(
                  decoration: BoxDecoration(
                    color:
                        colorScheme.primary.withValues(alpha: 0.08),
                    border: Border(
                      top: BorderSide(color: colorScheme.outlineVariant),
                    ),
                  ),
                  child: _row(context, widget.totalsRow!),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _headerRow(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: AppTheme.primaryGradient,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: _row(context, widget.columns,
          isHeader: true, valueStyle: const TextStyle(color: Colors.white)),
    );
  }

  Widget _dataRow(BuildContext context, List<String> cells, bool even) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      color: even
          ? colorScheme.surfaceContainerLowest
          : colorScheme.surfaceContainerLow,
      child: _row(context, cells),
    );
  }

  Widget _row(
    BuildContext context,
    List<String> cells, {
    bool isHeader = false,
    TextStyle? valueStyle,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return IntrinsicHeight(
      child: Row(
        children: [
          for (var i = 0; i < cells.length; i++)
            Container(
              width: 140,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              alignment: widget.rightAlignColumns.contains(i)
                  ? Alignment.centerRight
                  : Alignment.centerLeft,
              child: Text(
                cells[i],
                textAlign: widget.rightAlignColumns.contains(i)
                    ? TextAlign.right
                    : TextAlign.left,
                style: valueStyle ??
                    GoogleFonts.plusJakartaSans(
                      fontSize: 12.5,
                      fontWeight:
                          isHeader ? FontWeight.w700 : FontWeight.w500,
                      color: isHeader ? Colors.white : colorScheme.onSurface,
                    ),
              ),
            ),
        ],
      ),
    );
  }
}
