import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/api_service.dart';
import '../../services/app_state.dart';
import '../../widgets/incident_history_panel.dart';
import '../../widgets/metric_card.dart';
import '../../widgets/root_back_guard.dart';
import '../login_screen.dart';

class CompanyDashboardScreen extends StatelessWidget {
  const CompanyDashboardScreen({super.key});

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
        message: 'Vous etes sur le tableau de bord entreprise.',
        onBack: () => returnToLogin(context),
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Entreprise'),
            actions: [
              IconButton(
                tooltip: 'Retour accueil',
                icon: const Icon(Icons.logout_outlined),
                onPressed: () => returnToLogin(context),
              ),
            ],
          ),
          body: const SafeArea(
            child: SingleChildScrollView(
              padding: EdgeInsets.all(16),
              child: Column(children: [
                Row(children: [
                  Expanded(
                      child:
                          MetricCard(label: 'Vehicules actifs', value: '18')),
                  SizedBox(width: 12),
                  Expanded(child: MetricCard(label: 'Retards', value: '3')),
                ]),
                SizedBox(height: 12),
                Card(
                    child: ListTile(
                        leading: Icon(Icons.map_outlined),
                        title: Text('Carte temps reel'),
                        subtitle: Text('Positions GPS des vehicules'))),
                Card(
                    child: ListTile(
                        leading: Icon(Icons.assignment_outlined),
                        title: Text('Rapports'),
                        subtitle: Text('Tournees realisees et motifs'))),
                SizedBox(height: 12),
                IncidentHistoryPanel(),
              ]),
            ),
          ),
        ),
      );
}
