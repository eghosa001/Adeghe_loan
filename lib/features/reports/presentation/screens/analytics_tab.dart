import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';

import '../../../../core/utils/currency_utils.dart';
import '../providers/analytics_provider.dart';
import '../../data/models/analytics_models.dart';

class AnalyticsTab extends ConsumerWidget {
  const AnalyticsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final portfolioAsync = ref.watch(portfolioBreakdownProvider);
    final collectionAsync = ref.watch(collectionTrendsProvider);
    final repaymentAsync = ref.watch(repaymentTrendsProvider);
    final growthAsync = ref.watch(growthStatsProvider);
    final savingsAsync = ref.watch(savingsTrendsProvider);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        portfolioAsync.when(
          loading: () => const SizedBox(height: 100, child: Center(child: CircularProgressIndicator())),
          error: (e, _) => Card(child: Padding(padding: const EdgeInsets.all(16), child: Text('Error: $e'))),
          data: (data) => _PortfolioPieChart(breakdown: data),
        ),
        const SizedBox(height: 20),
        collectionAsync.when(
          loading: () => const SizedBox(height: 100, child: Center(child: CircularProgressIndicator())),
          error: (e, _) => Card(child: Padding(padding: const EdgeInsets.all(16), child: Text('Error: $e'))),
          data: (data) => _CollectionEfficiencyChart(trends: data),
        ),
        const SizedBox(height: 20),
        repaymentAsync.when(
          loading: () => const SizedBox(height: 100, child: Center(child: CircularProgressIndicator())),
          error: (e, _) => Card(child: Padding(padding: const EdgeInsets.all(16), child: Text('Error: $e'))),
          data: (data) => _RepaymentTrendChart(trends: data),
        ),
        const SizedBox(height: 20),
        growthAsync.when(
          loading: () => const SizedBox(height: 100, child: Center(child: CircularProgressIndicator())),
          error: (e, _) => Card(child: Padding(padding: const EdgeInsets.all(16), child: Text('Error: $e'))),
          data: (data) => _CustomerActivitySection(stats: data),
        ),
        const SizedBox(height: 20),
        savingsAsync.when(
          loading: () => const SizedBox(height: 100, child: Center(child: CircularProgressIndicator())),
          error: (e, _) => Card(child: Padding(padding: const EdgeInsets.all(16), child: Text('Error: $e'))),
          data: (data) => _SavingsTrendChart(trends: data),
        ),
      ],
    );
  }
}

class _PortfolioPieChart extends StatelessWidget {
  const _PortfolioPieChart({required this.breakdown});
  final PortfolioBreakdown breakdown;

  @override
  Widget build(BuildContext context) {
    final total = breakdown.totalCount;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Loan Portfolio Overview',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            SizedBox(
              height: 200,
              child: total == 0
                  ? const Center(child: Text('No loan data'))
                  : PieChart(
                      PieChartData(
                        sections: [
                          PieChartSectionData(
                            value: breakdown.activeCount.toDouble(),
                            color: Colors.green,
                            title: 'Active\n${breakdown.activeCount}',
                            radius: 60,
                            titleStyle: const TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.bold),
                          ),
                          PieChartSectionData(
                            value: breakdown.completedCount.toDouble(),
                            color: Colors.blue,
                            title: 'Completed\n${breakdown.completedCount}',
                            radius: 60,
                            titleStyle: const TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.bold),
                          ),
                          PieChartSectionData(
                            value: breakdown.defaultedCount.toDouble(),
                            color: Colors.red,
                            title: 'Defaulted\n${breakdown.defaultedCount}',
                            radius: 60,
                            titleStyle: const TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.bold),
                          ),
                        ],
                        sectionsSpace: 2,
                        centerSpaceRadius: 40,
                      ),
                    ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _LegendDot(color: Colors.green, label: 'Active (${CurrencyUtils.format(breakdown.activeAmount)})'),
                const SizedBox(width: 16),
                _LegendDot(color: Colors.blue, label: 'Completed (${CurrencyUtils.format(breakdown.completedAmount)})'),
                const SizedBox(width: 16),
                _LegendDot(color: Colors.red, label: 'Defaulted (${CurrencyUtils.format(breakdown.defaultedAmount)})'),
              ],
            ),
            const SizedBox(height: 8),
            Center(child: Text('Total Loans: $total | Total Outstanding: ${CurrencyUtils.format(breakdown.totalAmount)}')),
          ],
        ),
      ),
    );
  }
}

class _CollectionEfficiencyChart extends StatelessWidget {
  const _CollectionEfficiencyChart({required this.trends});
  final List<CollectionTrend> trends;

  @override
  Widget build(BuildContext context) {
    if (trends.isEmpty) return const SizedBox.shrink();
    final maxVal = trends.fold<double>(0, (m, t) => [m, t.expected, t.collected].reduce((a, b) => a > b ? a : b));
    final chartMax = maxVal > 0 ? maxVal * 1.2 : 100.0;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Collection Performance (Monthly)',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            SizedBox(
              height: 200,
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  maxY: chartMax,
                  barTouchData: BarTouchData(
                    touchTooltipData: BarTouchTooltipData(
                      getTooltipItem: (group, groupIndex, rod, rodIndex) {
                        final label = rodIndex == 0 ? 'Expected' : 'Collected';
                        return BarTooltipItem(
                          '$label\n${CurrencyUtils.format(rod.toY)}',
                          const TextStyle(color: Colors.white, fontSize: 12),
                        );
                      },
                    ),
                  ),
                  titlesData: FlTitlesData(
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          final idx = value.toInt();
                          if (idx < 0 || idx >= trends.length) return const SizedBox.shrink();
                          return Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              trends[idx].label.split('-').last,
                              style: const TextStyle(fontSize: 10),
                            ),
                          );
                        },
                        reservedSize: 24,
                      ),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 50,
                        getTitlesWidget: (value, meta) {
                          if (value == 0) return const SizedBox.shrink();
                          return Text(CurrencyUtils.formatShort(value), style: const TextStyle(fontSize: 9));
                        },
                      ),
                    ),
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  ),
                  borderData: FlBorderData(show: false),
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    getDrawingHorizontalLine: (value) => FlLine(color: Colors.grey.withValues(alpha: 0.2), strokeWidth: 1),
                  ),
                  barGroups: List.generate(trends.length, (i) {
                    return BarChartGroupData(
                      x: i,
                      barRods: [
                        BarChartRodData(toY: trends[i].expected, color: Colors.blue.shade200, width: 14, borderRadius: const BorderRadius.vertical(top: Radius.circular(4))),
                        BarChartRodData(toY: trends[i].collected, color: Colors.green, width: 14, borderRadius: const BorderRadius.vertical(top: Radius.circular(4))),
                      ],
                    );
                  }),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _LegendDot(color: Colors.blue.shade200, label: 'Expected'),
                const SizedBox(width: 24),
                _LegendDot(color: Colors.green, label: 'Collected'),
                const SizedBox(width: 24),
                _LegendDot(
                  color: Colors.teal,
                  label: 'Avg Eff: ${(trends.fold<double>(0, (s, t) => s + t.efficiency) / trends.length).toStringAsFixed(1)}%',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RepaymentTrendChart extends StatelessWidget {
  const _RepaymentTrendChart({required this.trends});
  final List<MonthlyTrendPoint> trends;

  @override
  Widget build(BuildContext context) {
    if (trends.isEmpty) return const SizedBox.shrink();
    final maxVal = trends.fold<double>(0, (m, t) => t.value > m ? t.value : m);
    final chartMax = maxVal > 0 ? maxVal * 1.2 : 100.0;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Repayment Trends (Monthly)',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            SizedBox(
              height: 180,
              child: LineChart(
                LineChartData(
                  minY: 0,
                  maxY: chartMax,
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    getDrawingHorizontalLine: (value) => FlLine(color: Colors.grey.withValues(alpha: 0.2), strokeWidth: 1),
                  ),
                  titlesData: FlTitlesData(
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          final idx = value.toInt();
                          if (idx < 0 || idx >= trends.length) return const SizedBox.shrink();
                          return Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(trends[idx].label.split('-').last, style: const TextStyle(fontSize: 10)),
                          );
                        },
                        reservedSize: 24,
                      ),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 50,
                        getTitlesWidget: (value, meta) {
                          if (value == 0) return const SizedBox.shrink();
                          return Text(CurrencyUtils.formatShort(value), style: const TextStyle(fontSize: 9));
                        },
                      ),
                    ),
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  ),
                  borderData: FlBorderData(show: false),
                  lineBarsData: [
                    LineChartBarData(
                      spots: List.generate(trends.length, (i) => FlSpot(i.toDouble(), trends[i].value)),
                      isCurved: true,
                      color: Colors.teal,
                      barWidth: 3,
                      dotData: FlDotData(
                        show: true,
                        getDotPainter: (spot, percent, barData, index) => FlDotCirclePainter(
                          radius: 4,
                          color: Colors.teal,
                          strokeWidth: 2,
                          strokeColor: Colors.white,
                        ),
                      ),
                      belowBarData: BarAreaData(show: true, color: Colors.teal.withValues(alpha: 0.1)),
                    ),
                  ],
                  lineTouchData: LineTouchData(
                    touchTooltipData: LineTouchTooltipData(
                      getTooltipItems: (touchedSpots) => touchedSpots.map((spot) {
                        return LineTooltipItem(
                          CurrencyUtils.format(spot.y),
                          const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CustomerActivitySection extends StatelessWidget {
  const _CustomerActivitySection({required this.stats});
  final GrowthStats stats;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Customer Activity Summary',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: _ActivityCard(label: 'Total', value: stats.totalCustomers.toString(), icon: Icons.people, color: Colors.blue)),
                    const SizedBox(width: 8),
                    Expanded(child: _ActivityCard(label: 'Active', value: stats.activeCustomers.toString(), icon: Icons.check_circle, color: Colors.green)),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(child: _ActivityCard(label: 'Inactive', value: stats.inactiveCustomers.toString(), icon: Icons.cancel, color: Colors.orange)),
                    const SizedBox(width: 8),
                    Expanded(child: _ActivityCard(label: 'Repeat Borrowers', value: stats.repeatBorrowers.toString(), icon: Icons.repeat, color: Colors.purple)),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(child: _ActivityCard(label: 'New This Month', value: stats.newCustomersThisMonth.toString(), icon: Icons.person_add, color: Colors.teal)),
                    const SizedBox(width: 8),
                    Expanded(child: _ActivityCard(label: 'Total Loans', value: stats.loanGrowth.fold<int>(0, (s, p) => s + p.value.toInt()).toString(), icon: Icons.layers, color: Colors.indigo)),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Monthly Growth (New Customers vs Loans)',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                SizedBox(
                  height: 180,
                  child: _GrowthBarChart(customerGrowth: stats.customerGrowth, loanGrowth: stats.loanGrowth),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _LegendDot(color: Colors.blue, label: 'New Customers'),
                    const SizedBox(width: 24),
                    _LegendDot(color: Colors.orange, label: 'New Loans'),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _GrowthBarChart extends StatelessWidget {
  const _GrowthBarChart({required this.customerGrowth, required this.loanGrowth});
  final List<MonthlyTrendPoint> customerGrowth;
  final List<MonthlyTrendPoint> loanGrowth;

  @override
  Widget build(BuildContext context) {
    final maxCust = customerGrowth.fold<double>(0, (m, t) => t.value > m ? t.value : m);
    final maxLoan = loanGrowth.fold<double>(0, (m, t) => t.value > m ? t.value : m);
    final maxVal = maxCust > maxLoan ? maxCust : maxLoan;
    final chartMax = maxVal > 0 ? maxVal * 1.2 : 10.0;

    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: chartMax,
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              final label = rodIndex == 0 ? 'Customers' : 'Loans';
              return BarTooltipItem('$label\n${rod.toY.toInt()}', const TextStyle(color: Colors.white, fontSize: 12));
            },
          ),
        ),
        titlesData: FlTitlesData(
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) {
                final idx = value.toInt();
                if (idx < 0 || idx >= customerGrowth.length) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(customerGrowth[idx].label.split('-').last, style: const TextStyle(fontSize: 10)),
                );
              },
              reservedSize: 24,
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 36,
              getTitlesWidget: (value, meta) {
                if (value == 0) return const SizedBox.shrink();
                return Text('${value.toInt()}', style: const TextStyle(fontSize: 9));
              },
            ),
          ),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(show: false),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (value) => FlLine(color: Colors.grey.withValues(alpha: 0.2), strokeWidth: 1),
        ),
        barGroups: List.generate(customerGrowth.length, (i) {
          return BarChartGroupData(
            x: i,
            barRods: [
              BarChartRodData(toY: customerGrowth[i].value, color: Colors.blue, width: 12, borderRadius: const BorderRadius.vertical(top: Radius.circular(4))),
              BarChartRodData(toY: loanGrowth[i].value, color: Colors.orange, width: 12, borderRadius: const BorderRadius.vertical(top: Radius.circular(4))),
            ],
          );
        }),
      ),
    );
  }
}

class _SavingsTrendChart extends StatelessWidget {
  const _SavingsTrendChart({required this.trends});
  final List<SavingsTrendPoint> trends;

  @override
  Widget build(BuildContext context) {
    if (trends.isEmpty) return const SizedBox.shrink();
    final maxVal = trends.fold<double>(0, (m, t) => [m, t.deposits, t.withdrawals].reduce((a, b) => a > b ? a : b));
    final chartMax = maxVal > 0 ? maxVal * 1.2 : 100.0;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Savings Trends (Monthly)',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            SizedBox(
              height: 180,
              child: _SavingsLineChart(trends: trends, chartMax: chartMax),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _LegendDot(color: Colors.green, label: 'Deposits'),
                const SizedBox(width: 24),
                _LegendDot(color: Colors.red, label: 'Withdrawals'),
                const SizedBox(width: 24),
                _LegendDot(color: Colors.indigo, label: 'Net Balance'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SavingsLineChart extends StatelessWidget {
  const _SavingsLineChart({required this.trends, required this.chartMax});
  final List<SavingsTrendPoint> trends;
  final double chartMax;

  @override
  Widget build(BuildContext context) {
    return LineChart(
      LineChartData(
        minY: 0,
        maxY: chartMax,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (value) => FlLine(color: Colors.grey.withValues(alpha: 0.2), strokeWidth: 1),
        ),
        titlesData: FlTitlesData(
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) {
                final idx = value.toInt();
                if (idx < 0 || idx >= trends.length) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(trends[idx].label.split('-').last, style: const TextStyle(fontSize: 10)),
                );
              },
              reservedSize: 24,
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 50,
              getTitlesWidget: (value, meta) {
                if (value == 0) return const SizedBox.shrink();
                return Text(CurrencyUtils.formatShort(value), style: const TextStyle(fontSize: 9));
              },
            ),
          ),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(show: false),
        lineBarsData: [
          LineChartBarData(
            spots: List.generate(trends.length, (i) => FlSpot(i.toDouble(), trends[i].deposits)),
            isCurved: true,
            color: Colors.green,
            barWidth: 2,
            dotData: FlDotData(show: true, getDotPainter: (spot, percent, barData, index) => FlDotCirclePainter(radius: 3, color: Colors.green, strokeWidth: 2, strokeColor: Colors.white)),
            belowBarData: BarAreaData(show: true, color: Colors.green.withValues(alpha: 0.05)),
          ),
          LineChartBarData(
            spots: List.generate(trends.length, (i) => FlSpot(i.toDouble(), trends[i].withdrawals)),
            isCurved: true,
            color: Colors.red,
            barWidth: 2,
            dotData: FlDotData(show: true, getDotPainter: (spot, percent, barData, index) => FlDotCirclePainter(radius: 3, color: Colors.red, strokeWidth: 2, strokeColor: Colors.white)),
          ),
          LineChartBarData(
            spots: List.generate(trends.length, (i) => FlSpot(i.toDouble(), trends[i].balance < 0 ? 0 : trends[i].balance)),
            isCurved: true,
            color: Colors.indigo,
            barWidth: 2,
            dashArray: [5, 3],
            dotData: FlDotData(show: true, getDotPainter: (spot, percent, barData, index) => FlDotCirclePainter(radius: 3, color: Colors.indigo, strokeWidth: 2, strokeColor: Colors.white)),
          ),
        ],
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipItems: (touchedSpots) => touchedSpots.map((spot) {
              final label = ['Deposits', 'Withdrawals', 'Balance'][touchedSpots.indexOf(spot) % 3];
              return LineTooltipItem(
                '$label: ${CurrencyUtils.format(spot.y)}',
                const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }
}

class _ActivityCard extends StatelessWidget {
  const _ActivityCard({required this.label, required this.value, required this.icon, required this.color});
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 4),
            Text(value, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold, color: color)),
            Text(label, style: Theme.of(context).textTheme.bodySmall, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 4),
        Text(label, style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 11)),
      ],
    );
  }
}
