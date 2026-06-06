import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/app_state.dart';

class StopsScreen extends StatefulWidget {
  const StopsScreen({super.key});

  @override
  State<StopsScreen> createState() => _StopsScreenState();
}

class _StopsScreenState extends State<StopsScreen> {
  int currentStop = 0;

  @override
  Widget build(BuildContext context) {
    final route = context.watch<AppState>().selectedDriverRoute;
    final stops = route?.stopsPreview ?? [];
    return Scaffold(
      appBar: AppBar(title: const Text('Parcours et arrets')),
      body: route == null
          ? const Center(child: Text('Choisissez une ligne avant de consulter le parcours.'))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.route_outlined),
                    title: Text('${route.shortName} - ${route.longName}'),
                    subtitle: Text('${stops.length} arrets charges pour guider un remplacant'),
                  ),
                ),
                if (stops.isNotEmpty)
                  Card(
                    child: ListTile(
                      leading: CircleAvatar(child: Text(stops[currentStop].sequence.toString())),
                      title: Text('Prochain arret'),
                      subtitle: Text(stops[currentStop].name),
                      trailing: FilledButton(
                        onPressed: currentStop >= stops.length - 1 ? null : () => setState(() => currentStop++),
                        child: const Text('Suivant'),
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                ...stops.map((stop) {
                  final isCurrent = stops.indexOf(stop) == currentStop;
                  return Card(
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: isCurrent ? Theme.of(context).colorScheme.primary : null,
                        foregroundColor: isCurrent ? Theme.of(context).colorScheme.onPrimary : null,
                        child: Text(stop.sequence.toString()),
                      ),
                      title: Text(stop.name),
                      subtitle: stop.arrivalTime.isEmpty ? const Text('Horaire non renseigne') : Text(stop.arrivalTime),
                      trailing: isCurrent ? const Icon(Icons.navigation_outlined) : null,
                      onTap: () => setState(() => currentStop = stops.indexOf(stop)),
                    ),
                  );
                }),
              ],
            ),
    );
  }
}
