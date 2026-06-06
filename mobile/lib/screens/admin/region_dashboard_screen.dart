import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../../widgets/metric_card.dart';

class RegionDashboardScreen extends StatelessWidget {
  const RegionDashboardScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Region')),
    body: ListView(padding: const EdgeInsets.all(16), children: [
      const Row(children: [Expanded(child: MetricCard(label: 'Lignes', value: '124')), SizedBox(width: 12), Expanded(child: MetricCard(label: 'Saturees', value: '7'))]),
      const SizedBox(height: 16),
      SizedBox(height: 220, child: BarChart(BarChartData(barGroups: [
        BarChartGroupData(x: 1, barRods: [BarChartRodData(toY: 42)]),
        BarChartGroupData(x: 2, barRods: [BarChartRodData(toY: 55)]),
        BarChartGroupData(x: 3, barRods: [BarChartRodData(toY: 38)]),
      ]))),
      const Card(child: ListTile(leading: Icon(Icons.insights), title: Text('Arrets peu frequentes'), subtitle: Text('Analyse hebdomadaire et annuelle'))),
    ]),
  );
}
