import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/api_service.dart';
import '../../services/app_state.dart';
import '../../widgets/metric_card.dart';
import '../../widgets/root_back_guard.dart';
import '../login_screen.dart';

class RegionDashboardScreen extends StatelessWidget {
  const RegionDashboardScreen({super.key});

  void returnToLogin(BuildContext context) {
    context.read<AppState>().logout();
    context.read<ApiService>().clearToken();
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) => RootBackGuard(
        message: 'Vous etes sur le tableau de bord region.',
        onBack: () => returnToLogin(context),
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Region'),
            actions: [
              IconButton(
                tooltip: 'Retour accueil',
                icon: const Icon(Icons.logout_outlined),
                onPressed: () => returnToLogin(context),
              ),
            ],
          ),
          body: ListView(padding: const EdgeInsets.all(16), children: [
            const Row(children: [
              Expanded(child: MetricCard(label: 'Lignes', value: '124')),
              SizedBox(width: 12),
              Expanded(child: MetricCard(label: 'Saturees', value: '7')),
            ]),
            const SizedBox(height: 16),
            SizedBox(
              height: 220,
              child: BarChart(BarChartData(barGroups: [
                BarChartGroupData(x: 1, barRods: [BarChartRodData(toY: 42)]),
                BarChartGroupData(x: 2, barRods: [BarChartRodData(toY: 55)]),
                BarChartGroupData(x: 3, barRods: [BarChartRodData(toY: 38)]),
              ])),
            ),
            const Card(
                child: ListTile(
                    leading: Icon(Icons.insights),
                    title: Text('Arrets peu frequentes'),
                    subtitle: Text('Analyse hebdomadaire et annuelle'))),
          ]),
        ),
      );
}
