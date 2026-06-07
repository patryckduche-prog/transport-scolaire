import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/api_service.dart';
import '../../services/app_state.dart';

class DelayScreen extends StatefulWidget {
  const DelayScreen({super.key});
  @override
  State<DelayScreen> createState() => _DelayScreenState();
}

class _DelayScreenState extends State<DelayScreen> {
  final statuses = [
    'Information',
    'Retard 5 minutes',
    'Retard 10 minutes',
    'Retard 15 minutes',
    'Retard 30 minutes',
    'Retard superieur a 30 minutes',
    'Alerte importante',
    'Transport interdit',
  ];
  final reasons = [
    'Neige',
    'Verglas',
    'Tempete',
    'Vent violent',
    'Arrete prefectoral',
    'Suspension transports scolaires',
    'Panne mecanique',
    'Accident',
    'Bouchon',
    'Route barree',
    'Conditions meteo',
    'Autre',
  ];
  String status = 'Retard 15 minutes';
  String reason = 'Verglas';
  bool sending = false;

  Future<void> submit() async {
    final route = context.read<AppState>().selectedDriverRoute;
    if (route == null || sending) return;
    setState(() => sending = true);
    try {
      await context.read<ApiService>().declareDelay(route.id, status, reason, routeName: '${route.shortName} - ${route.longName}');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Alerte transmise aux familles et services.')));
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final route = context.watch<AppState>().selectedDriverRoute;
    return Scaffold(
      appBar: AppBar(title: const Text('Declaration d alerte')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Card(
          child: ListTile(
            leading: const Icon(Icons.route_outlined),
            title: Text(route == null ? 'Aucune ligne active' : route.shortName),
            subtitle: Text(route?.longName ?? 'Retournez choisir une ligne avant d envoyer une alerte.'),
          ),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField(initialValue: status, items: statuses.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(), onChanged: (v) => setState(() => status = v!)),
        const SizedBox(height: 12),
        DropdownButtonFormField(initialValue: reason, items: reasons.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(), onChanged: (v) => setState(() => reason = v!)),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: route == null || sending ? null : submit,
          icon: const Icon(Icons.notifications_active_outlined),
          label: Text(sending ? 'Envoi...' : 'Envoyer l\'alerte'),
        ),
      ]),
    );
  }
}
