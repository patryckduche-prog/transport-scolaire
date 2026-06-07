import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/app_state.dart';
import '../../services/api_service.dart';
import '../../widgets/metric_card.dart';
import '../../widgets/root_back_guard.dart';
import '../login_screen.dart';
import 'delay_screen.dart';
import 'driver_assistant_screen.dart';
import 'gps_screen.dart';
import 'nomad_routes_screen.dart';
import 'stops_screen.dart';

class DriverDashboardScreen extends StatelessWidget {
  const DriverDashboardScreen({super.key});

  void returnToLogin(BuildContext context) {
    context.read<AppState>().logout();
    context.read<ApiService>().clearToken();
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }

  void requireRoute(BuildContext context, Widget screen) {
    final route = context.read<AppState>().selectedDriverRoute;
    if (route == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Choisissez d abord votre ligne du jour.')));
      Navigator.push(context,
          MaterialPageRoute(builder: (_) => const NomadRoutesScreen()));
      return;
    }
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    final selectedRoute = context.watch<AppState>().selectedDriverRoute;
    return RootBackGuard(
      message: 'Vous etes sur le tableau de bord conducteur.',
      onBack: () => returnToLogin(context),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Conducteur'),
          actions: [
            IconButton(
              tooltip: 'Retour accueil',
              icon: const Icon(Icons.logout_outlined),
              onPressed: () => returnToLogin(context),
            ),
          ],
        ),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          Text('Tournee du jour',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: Icon(selectedRoute == null
                  ? Icons.route_outlined
                  : Icons.check_circle_outline),
              title: Text(selectedRoute == null
                  ? 'Aucune ligne selectionnee'
                  : '${selectedRoute.shortName} - ${selectedRoute.longName}'),
              subtitle: Text(selectedRoute == null
                  ? 'Choisissez votre ligne avant le depart.'
                  : '${selectedRoute.stopCount} arrets dans le parcours'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const NomadRoutesScreen())),
            ),
          ),
          const SizedBox(height: 12),
          const Row(children: [
            Expanded(child: MetricCard(label: 'Presents', value: '42')),
            SizedBox(width: 12),
            Expanded(child: MetricCard(label: 'Absents', value: '6'))
          ]),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: selectedRoute == null
                ? null
                : () => ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text(
                        'Depart depot declare pour ${selectedRoute.shortName}.'))),
            icon: const Icon(Icons.play_arrow),
            label: const Text('Declarer le depart du depot'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
              onPressed: () => requireRoute(context, const DelayScreen()),
              icon: const Icon(Icons.schedule),
              label: const Text('Declarer un retard')),
          OutlinedButton.icon(
              onPressed: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const NomadRoutesScreen())),
              icon: const Icon(Icons.route_outlined),
              label: const Text('Choisir / changer de ligne')),
          OutlinedButton.icon(
              onPressed: () => requireRoute(context, const StopsScreen()),
              icon: const Icon(Icons.location_on_outlined),
              label: const Text('Parcours et arrets')),
          OutlinedButton.icon(
              onPressed: () =>
                  requireRoute(context, const DriverAssistantScreen()),
              icon: const Icon(Icons.shield_outlined),
              label: const Text('Mode conduite')),
          OutlinedButton.icon(
              onPressed: () => requireRoute(context, const GpsScreen()),
              icon: const Icon(Icons.map_outlined),
              label: const Text('Suivi GPS')),
        ]),
      ),
    );
  }
}
