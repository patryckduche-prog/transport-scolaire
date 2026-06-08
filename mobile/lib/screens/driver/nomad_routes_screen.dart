import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/nomad_route.dart';
import '../../services/app_state.dart';
import '../../services/api_service.dart';
import '../../theme.dart';
import 'gps_screen.dart';

class NomadRoutesScreen extends StatefulWidget {
  const NomadRoutesScreen({super.key});

  @override
  State<NomadRoutesScreen> createState() => _NomadRoutesScreenState();
}

class _NomadRoutesScreenState extends State<NomadRoutesScreen> {
  final search = TextEditingController();
  List<NomadRoute> routes = [];
  String summary = '';
  String sectorName = '';
  bool loading = true;
  int requestId = 0;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final currentRequest = ++requestId;
    setState(() => loading = true);
    final data = await context
        .read<ApiService>()
        .getNomadRoutes(query: search.text, highlighted: false);
    if (currentRequest != requestId) return;
    final list = (data['routes'] as List)
        .map((item) => NomadRoute.fromJson(item))
        .toList();
    final meta = data['summary'] as Map<String, dynamic>;
    final sector = data['sector'] as Map<String, dynamic>?;
    if (!mounted) return;
    setState(() {
      routes = list;
      sectorName = sector?['name'] as String? ?? '';
      summary = sectorName.isEmpty
          ? '${list.length} / ${meta['routeCount']} lignes Nomad Car affichees'
          : '${list.length} ligne(s) autorisee(s) pour le secteur $sectorName';
      loading = false;
    });
  }

  Future<void> chooseRoute(NomadRoute route, {bool openGps = false}) async {
    if (route.suspended) {
      showSuspension(route);
      return;
    }
    NomadRoute selected = route;
    try {
      final detail = await context.read<ApiService>().getNomadRoute(route.id);
      selected = NomadRoute.fromJson(detail);
    } catch (_) {
      selected = route;
    }
    if (!mounted) return;
    if (selected.suspended) {
      showSuspension(selected);
      return;
    }
    context.read<AppState>().selectDriverRoute(selected);
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ligne selectionnee : ${selected.shortName}')));
    if (openGps) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const GpsScreen()),
      );
      return;
    }
    Navigator.of(context).pop();
  }

  bool isPreferredAumaleForges(NomadRoute route) => route.id == 'SCHOOL-5010A0';

  void showSuspension(NomadRoute route) {
    final suspension = route.suspension;
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Transports interdits'),
        content: Text(
          '${route.shortName} - ${route.longName}\n\n'
          '${suspension?.message ?? 'TRANSPORTS INTERDITS'}\n'
          '${suspension?.legalBasis ?? 'Arrete prefectoral'}',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Compris'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selectedRoute = context.watch<AppState>().selectedDriverRoute;
    return Scaffold(
      appBar: AppBar(title: const Text('Circuits Nomad')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: search,
                  decoration: const InputDecoration(
                    labelText: 'Rechercher une ligne ou un arret',
                    prefixIcon: Icon(Icons.search),
                  ),
                  onChanged: (_) => load(),
                  onSubmitted: (_) => load(),
                ),
                const SizedBox(height: 8),
                if (sectorName.isNotEmpty)
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.lock_outline),
                      title: const Text('Circuits limites par votre code'),
                      subtitle: Text(sectorName),
                    ),
                  ),
                if (selectedRoute != null)
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.check_circle_outline),
                      title: Text('Ligne active : ${selectedRoute.shortName}'),
                      subtitle: Text(selectedRoute.longName),
                    ),
                  ),
                Text(summary),
              ],
            ),
          ),
          Expanded(
            child: loading
                ? const Center(child: CircularProgressIndicator())
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    itemCount: routes.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final route = routes[index];
                      final preferred = isPreferredAumaleForges(route);
                      final suspended = route.suspended;
                      return Card(
                        color: suspended
                            ? AppTheme.emergencyRedLight
                            : preferred
                                ? Theme.of(context).colorScheme.primaryContainer
                                : null,
                        child: ExpansionTile(
                          leading: CircleAvatar(
                            backgroundColor: suspended
                                ? AppTheme.emergencyRed
                                : preferred
                                    ? Theme.of(context).colorScheme.primary
                                    : null,
                            foregroundColor: suspended || preferred
                                ? Theme.of(context).colorScheme.onPrimary
                                : null,
                            child: suspended
                                ? const Icon(Icons.block)
                                : FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Padding(
                                      padding: const EdgeInsets.all(3),
                                      child: Text(route.shortName,
                                          textAlign: TextAlign.center),
                                    ),
                                  ),
                          ),
                          title: Text(route.longName),
                          subtitle: Text(suspended
                              ? 'TRANSPORTS INTERDITS - ${route.suspension?.legalBasis ?? 'Arrete prefectoral'}'
                              : preferred
                                  ? 'Ton circuit Aumale 07:00 vers Forges 07:45'
                                  : '${route.stopCount} arrets - ${route.tripCount} trajets'),
                          children: [
                            if (suspended)
                              Container(
                                width: double.infinity,
                                margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: AppTheme.emergencyRed,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  'TRANSPORTS INTERDITS\n${route.suspension?.legalBasis ?? 'Arrete prefectoral'}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                            ...route.stopsPreview.map((stop) => ListTile(
                                  dense: true,
                                  leading: Text(stop.sequence.toString()),
                                  title: Text(stop.name),
                                  subtitle: stop.arrivalTime.isEmpty
                                      ? null
                                      : Text(stop.arrivalTime),
                                )),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  FilledButton.icon(
                                    onPressed: suspended
                                        ? null
                                        : () => chooseRoute(route),
                                    icon:
                                        const Icon(Icons.check_circle_outline),
                                    label: const Text('Choisir cette ligne'),
                                  ),
                                  const SizedBox(height: 8),
                                  OutlinedButton.icon(
                                    onPressed: suspended
                                        ? null
                                        : () =>
                                            chooseRoute(route, openGps: true),
                                    icon: const Icon(Icons.navigation_outlined),
                                    label: const Text(
                                        'Choisir et lancer le GPS vocal'),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
