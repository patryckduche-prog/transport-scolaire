import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/nomad_route.dart';
import '../../services/app_state.dart';
import '../../services/api_service.dart';

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
    final data = await context.read<ApiService>().getNomadRoutes(query: search.text, highlighted: false);
    if (currentRequest != requestId) return;
    final list = (data['routes'] as List).map((item) => NomadRoute.fromJson(item)).toList();
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

  Future<void> chooseRoute(NomadRoute route) async {
    NomadRoute selected = route;
    try {
      final detail = await context.read<ApiService>().getNomadRoute(route.id);
      selected = NomadRoute.fromJson(detail);
    } catch (_) {
      selected = route;
    }
    if (!mounted) return;
    context.read<AppState>().selectDriverRoute(selected);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ligne selectionnee : ${selected.shortName}')));
    Navigator.of(context).pop();
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
                      return Card(
                        child: ExpansionTile(
                          leading: CircleAvatar(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Padding(
                                padding: const EdgeInsets.all(3),
                                child: Text(route.shortName, textAlign: TextAlign.center),
                              ),
                            ),
                          ),
                          title: Text(route.longName),
                          subtitle: Text('${route.stopCount} arrets - ${route.tripCount} trajets'),
                          children: [
                            ...route.stopsPreview.map((stop) => ListTile(
                                    dense: true,
                                    leading: Text(stop.sequence.toString()),
                                    title: Text(stop.name),
                                    subtitle: stop.arrivalTime.isEmpty ? null : Text(stop.arrivalTime),
                                  )),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                              child: FilledButton.icon(
                                onPressed: () => chooseRoute(route),
                                icon: const Icon(Icons.check_circle_outline),
                                label: const Text('Choisir cette ligne'),
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
