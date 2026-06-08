import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/app_state.dart';
import '../../services/api_service.dart';
import '../../theme.dart';
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
    if (route.suspended) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            'TRANSPORTS INTERDITS : ${route.suspension?.legalBasis ?? 'Arrete prefectoral'}'),
      ));
      return;
    }
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    final selectedRoute = context.watch<AppState>().selectedDriverRoute;
    final routeSuspended = selectedRoute?.suspended == true;
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
          Text('Poste conducteur',
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w900)),
          const SizedBox(height: 12),
          Card(
            color: routeSuspended ? AppTheme.emergencyRedLight : null,
            child: ListTile(
              minVerticalPadding: 18,
              leading: CircleAvatar(
                backgroundColor: routeSuspended
                    ? AppTheme.emergencyRed
                    : selectedRoute == null
                        ? Theme.of(context).colorScheme.primaryContainer
                        : AppTheme.serviceGreen,
                foregroundColor: routeSuspended || selectedRoute != null
                    ? Colors.white
                    : Theme.of(context).colorScheme.onPrimaryContainer,
                child: Icon(selectedRoute == null
                    ? Icons.route_outlined
                    : routeSuspended
                        ? Icons.block
                        : Icons.check_circle_outline),
              ),
              title: Text(selectedRoute == null
                  ? 'Aucune ligne selectionnee'
                  : '${selectedRoute.shortName} - ${selectedRoute.longName}'),
              subtitle: Text(selectedRoute == null
                  ? 'Choisissez votre ligne avant le depart.'
                  : routeSuspended
                      ? 'TRANSPORTS INTERDITS - ${selectedRoute.suspension?.legalBasis ?? 'Arrete prefectoral'}'
                      : '${selectedRoute.stopCount} arrets dans le parcours'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const NomadRoutesScreen())),
            ),
          ),
          const SizedBox(height: 12),
          const Row(children: [
            Expanded(child: MetricCard(label: 'A verifier', value: '42')),
            SizedBox(width: 12),
            Expanded(child: MetricCard(label: 'Absences', value: '6'))
          ]),
          const SizedBox(height: 16),
          if (routeSuspended)
            _EmergencyBanner(
              message:
                  'TRANSPORTS INTERDITS\n${selectedRoute?.suspension?.legalBasis ?? 'Arrete prefectoral'}',
            ),
          if (routeSuspended) const SizedBox(height: 12),
          _PrimaryDriverAction(
            icon: Icons.map_outlined,
            label: 'Lancer GPS',
            detail: 'Suivi automatique du circuit',
            color: AppTheme.primaryBlue,
            onPressed: selectedRoute == null || routeSuspended
                ? null
                : () => requireRoute(context, const GpsScreen()),
          ),
          const SizedBox(height: 10),
          _PrimaryDriverAction(
            icon: Icons.shield_outlined,
            label: 'Mode conduite',
            detail: 'SOS, charges par arret, fin de service',
            color: AppTheme.serviceGreen,
            onPressed: selectedRoute == null || routeSuspended
                ? null
                : () => requireRoute(context, const DriverAssistantScreen()),
          ),
          const SizedBox(height: 14),
          Text('Actions rapides',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          GridView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: 1.45,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
            ),
            children: [
              _DriverActionTile(
                icon: Icons.play_arrow,
                label: routeSuspended ? 'Depart bloque' : 'Depart depot',
                color: AppTheme.serviceGreen,
                onPressed: selectedRoute == null || routeSuspended
                    ? null
                    : () => ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text(
                            'Depart depot declare pour ${selectedRoute.shortName}.'))),
              ),
              _DriverActionTile(
                icon: Icons.schedule,
                label: 'Retard',
                color: AppTheme.warningOrange,
                onPressed: () => requireRoute(context, const DelayScreen()),
              ),
              _DriverActionTile(
                icon: Icons.route_outlined,
                label: 'Ligne',
                color: AppTheme.primaryBlue,
                onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const NomadRoutesScreen())),
              ),
              _DriverActionTile(
                icon: Icons.location_on_outlined,
                label: 'Arrets',
                color: AppTheme.primaryBlue,
                onPressed: () => requireRoute(context, const StopsScreen()),
              ),
            ],
          ),
        ]),
      ),
    );
  }
}

class _PrimaryDriverAction extends StatelessWidget {
  const _PrimaryDriverAction({
    required this.icon,
    required this.label,
    required this.detail,
    required this.color,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final String detail;
  final Color color;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(74),
        backgroundColor: color,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
      child: Row(children: [
        Icon(icon, size: 30),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(label,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w900)),
              Text(detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13)),
            ],
          ),
        ),
        const Icon(Icons.chevron_right),
      ]),
    );
  }
}

class _DriverActionTile extends StatelessWidget {
  const _DriverActionTile({
    required this.icon,
    required this.label,
    required this.color,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: onPressed == null ? null : color,
        side: BorderSide(color: onPressed == null ? Colors.grey : color),
        padding: const EdgeInsets.all(12),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 30),
          const SizedBox(height: 8),
          Text(label,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

class _EmergencyBanner extends StatelessWidget {
  const _EmergencyBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.emergencyRed,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        message,
        style: const TextStyle(
            color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16),
      ),
    );
  }
}
