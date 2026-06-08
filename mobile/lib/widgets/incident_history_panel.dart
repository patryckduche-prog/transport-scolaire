import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/api_service.dart';

class IncidentHistoryPanel extends StatefulWidget {
  const IncidentHistoryPanel({super.key});

  @override
  State<IncidentHistoryPanel> createState() => _IncidentHistoryPanelState();
}

class _IncidentHistoryPanelState extends State<IncidentHistoryPanel> {
  late Future<List<dynamic>> _future = _load();

  Future<List<dynamic>> _load() =>
      context.read<ApiService>().getRunIncidents();

  Future<void> _refresh() async {
    setState(() => _future = _load());
    await _future;
  }

  Future<void> _updateStatus(int id, String status) async {
    await context.read<ApiService>().updateRunIncidentStatus(
          incidentId: id,
          status: status,
          comment: status == 'in_progress'
              ? 'Pris en charge depuis le back-office mobile'
              : 'Cloture depuis le back-office mobile',
        );
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.emergency_share_outlined,
                color: Theme.of(context).colorScheme.error),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Historique SOS conducteur',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
            IconButton(
              tooltip: 'Actualiser',
              icon: const Icon(Icons.refresh),
              onPressed: _refresh,
            ),
          ]),
          FutureBuilder<List<dynamic>>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.all(18),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              final incidents =
                  (snapshot.data ?? const <dynamic>[]).cast<Map<String, dynamic>>();
              if (incidents.isEmpty) {
                return const ListTile(
                  leading: Icon(Icons.verified_outlined),
                  title: Text('Aucun SOS enregistre'),
                  subtitle: Text('Les incidents conducteur apparaitront ici.'),
                );
              }
              return Column(
                children: incidents
                    .map((incident) => _IncidentTile(
                          incident: incident,
                          onTake: () => _updateStatus(
                              incident['id'] as int, 'in_progress'),
                          onClose: () =>
                              _updateStatus(incident['id'] as int, 'closed'),
                        ))
                    .toList(),
              );
            },
          ),
        ]),
      ),
    );
  }
}

class _IncidentTile extends StatelessWidget {
  const _IncidentTile({
    required this.incident,
    required this.onTake,
    required this.onClose,
  });

  final Map<String, dynamic> incident;
  final VoidCallback onTake;
  final VoidCallback onClose;

  String get status => incident['status'] as String? ?? 'received';

  String get statusLabel => switch (status) {
        'in_progress' => 'Pris en charge',
        'closed' => 'Cloture',
        _ => 'Recu',
      };

  Color statusColor(BuildContext context) => switch (status) {
        'in_progress' => Colors.orange,
        'closed' => Colors.green,
        _ => Theme.of(context).colorScheme.error,
      };

  @override
  Widget build(BuildContext context) {
    final route = incident['routeName'] as String? ?? 'Ligne non renseignee';
    final driver =
        incident['driverName'] as String? ?? 'Conducteur non renseigne';
    final vehicle =
        incident['vehiclePlate'] as String? ?? 'Vehicule non renseigne';
    final reason = incident['reason'] as String? ?? incident['message'] as String? ?? 'SOS';
    final lat = incident['latitude'];
    final lon = incident['longitude'];
    final position = lat != null && lon != null
        ? 'GPS : $lat, $lon'
        : 'GPS non disponible';

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.warning_amber_rounded,
              color: Theme.of(context).colorScheme.error),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(route,
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(fontWeight: FontWeight.w800)),
                  Text(reason),
                ]),
          ),
          _StatusPill(label: statusLabel, color: statusColor(context)),
        ]),
        const SizedBox(height: 8),
        Text('$driver - $vehicle'),
        Text(position),
        Text('Declenche le ${incident['createdAt'] ?? ''}'),
        if (status != 'closed') ...[
          const SizedBox(height: 8),
          Row(children: [
            if (status == 'received')
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onTake,
                  icon: const Icon(Icons.support_agent_outlined),
                  label: const Text('Prendre en charge'),
                ),
              ),
            if (status == 'received') const SizedBox(width: 8),
            Expanded(
              child: FilledButton.icon(
                onPressed: onClose,
                icon: const Icon(Icons.check_circle_outline),
                label: const Text('Cloturer'),
              ),
            ),
          ]),
        ],
      ]),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontWeight: FontWeight.w800),
      ),
    );
  }
}
