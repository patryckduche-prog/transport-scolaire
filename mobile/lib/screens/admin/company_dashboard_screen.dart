import 'package:flutter/material.dart';
import '../../widgets/metric_card.dart';

class CompanyDashboardScreen extends StatelessWidget {
  const CompanyDashboardScreen({super.key});
  @override
  Widget build(BuildContext context) => const Scaffold(

    body: SafeArea(child: Padding(padding: EdgeInsets.all(16), child: Column(children: [
      Row(children: [Expanded(child: MetricCard(label: 'Vehicules actifs', value: '18')), SizedBox(width: 12), Expanded(child: MetricCard(label: 'Retards', value: '3'))]),
      SizedBox(height: 12),
      Card(child: ListTile(leading: Icon(Icons.map_outlined), title: Text('Carte temps reel'), subtitle: Text('Positions GPS des vehicules'))),
      Card(child: ListTile(leading: Icon(Icons.assignment_outlined), title: Text('Rapports'), subtitle: Text('Tournees realisees et motifs'))),
    ]))),
  );
}
