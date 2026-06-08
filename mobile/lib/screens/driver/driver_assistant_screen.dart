import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';

import '../../models/nomad_route.dart';
import '../../services/api_service.dart';
import '../../services/app_state.dart';
import '../../services/offline_event_queue.dart';
import '../../theme.dart';

class DriverAssistantScreen extends StatefulWidget {
  const DriverAssistantScreen({super.key});

  @override
  State<DriverAssistantScreen> createState() => _DriverAssistantScreenState();
}

class _DriverAssistantScreenState extends State<DriverAssistantScreen> {
  String? runId;
  List<Map<String, dynamic>> passengers = [];
  bool loading = true;
  bool busEmptyConfirmed = false;
  int queued = 0;
  String status = 'Initialisation du mode conduite';

  OfflineEventQueue queue(BuildContext context) =>
      OfflineEventQueue(context.read<ApiService>());

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => initRun());
  }

  Future<void> initRun() async {
    final route = context.read<AppState>().selectedDriverRoute;
    if (route == null) {
      setState(() {
        loading = false;
        status = 'Aucune ligne selectionnee.';
      });
      return;
    }
    if (route.suspended) {
      setState(() {
        loading = false;
        status =
            'TRANSPORTS INTERDITS - ${route.suspension?.legalBasis ?? 'Arrete prefectoral'}';
      });
      return;
    }

    try {
      final api = context.read<ApiService>();
      final offlineQueue = queue(context);
      final current = await api.getCurrentRun();
      final run = current ??
          await api.startRun(
            routeId: route.id,
            routeName: '${route.shortName} - ${route.longName}',
          );
      final data = await api.getRunStudents(run['id'] as String);
      final pending = await offlineQueue.pendingCount();
      if (!mounted) return;
      setState(() {
        runId = run['id'] as String;
        passengers = data.cast<Map<String, dynamic>>();
        queued = pending;
        loading = false;
        status = 'Tournee active - donnees anonymisees';
      });
    } on DioException catch (error) {
      final data = error.response?.data;
      final suspended = data is Map && data['error'] == 'route_suspended';
      if (!mounted) return;
      setState(() {
        loading = false;
        status = suspended
            ? 'TRANSPORTS INTERDITS - depart bloque par le serveur.'
            : 'Mode hors ligne : les actions seront synchronisees ensuite.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        loading = false;
        status = 'Mode hors ligne : les actions seront synchronisees ensuite.';
      });
    }
  }

  int get expectedCount => passengers.length;
  int get absentCount =>
      passengers.where((item) => item['status'] == 'absent').length;
  int get presentCount =>
      passengers.where((item) => item['status'] == 'present').length;
  int get remainingCount {
    final remaining = expectedCount - absentCount - presentCount;
    return remaining < 0 ? 0 : remaining;
  }

  List<_StopLoad> get stopLoads {
    final grouped = <String, _StopLoad>{};
    for (final item in passengers) {
      final stopName = item['stopName'] as String? ?? 'Arret non renseigne';
      final current = grouped.putIfAbsent(stopName, () => _StopLoad(stopName));
      current.expected++;
      if (item['status'] == 'absent') current.absent++;
      if (item['status'] == 'present') current.present++;
    }
    final values = grouped.values.toList()
      ..sort((a, b) => a.stopName.compareTo(b.stopName));
    return values;
  }

  Future<void> sendSos() async {
    final id = runId;
    if (id == null) return;
    final api = context.read<ApiService>();
    final offlineQueue = queue(context);
    final reason = await _selectSosReason();
    if (reason == null) return;
    final position = await _currentPositionOrNull();
    final event = {
      'type': 'incident',
      'runId': id,
      'incidentType': 'sos',
      'reason': reason,
      'message': 'SOS conducteur - $reason',
      'severity': 'critical',
      if (position != null) 'latitude': position.latitude,
      if (position != null) 'longitude': position.longitude,
      if (position != null) 'speed': position.speed,
    };
    try {
      await api.sendRunIncident(
        runId: id,
        type: 'sos',
        reason: reason,
        message: 'SOS conducteur - $reason',
        severity: 'critical',
        latitude: position?.latitude,
        longitude: position?.longitude,
        speed: position?.speed,
      );
      if (!mounted) return;
      setState(() => status = 'SOS envoye au depot / exploitation');
    } catch (_) {
      await offlineQueue.enqueue(event);
      final pending = await offlineQueue.pendingCount();
      if (!mounted) return;
      setState(() {
        queued = pending;
        status = 'SOS garde hors ligne, envoi au retour reseau';
      });
    }
  }

  Future<String?> _selectSosReason() async {
    const reasons = [
      'SOS conducteur',
      'Malaise ou blessure',
      'Accident',
      'Panne immobilisante',
      'Agression ou menace',
      'Enfant manquant',
      'Autre incident',
    ];
    return showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 18),
          children: [
            Text('SOS conducteur',
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w900)),
            const SizedBox(height: 4),
            const Text(
                'Choisir le motif puis le depot est alerte immediatement.'),
            const SizedBox(height: 12),
            ...reasons.map(
              (reason) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(56),
                    backgroundColor: reason == 'SOS conducteur'
                        ? AppTheme.emergencyRed
                        : Theme.of(context).colorScheme.surfaceContainerHighest,
                    foregroundColor: reason == 'SOS conducteur'
                        ? Colors.white
                        : Theme.of(context).colorScheme.onSurface,
                  ),
                  icon: const Icon(Icons.warning_amber_outlined),
                  label: Text(reason),
                  onPressed: () => Navigator.of(context).pop(reason),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<Position?> _currentPositionOrNull() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return null;
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return null;
      }
      return Geolocator.getCurrentPosition(
        locationSettings:
            const LocationSettings(accuracy: LocationAccuracy.high),
      ).timeout(const Duration(seconds: 6));
    } catch (_) {
      return null;
    }
  }

  Future<void> finishCheck() async {
    final id = runId;
    if (id == null) return;
    final event = {
      'type': 'finishCheck',
      'runId': id,
      'allStudentsChecked': true,
      'busEmptyConfirmed': busEmptyConfirmed,
      'comment': 'Mode conduite anonyme : fin de service confirmee.',
    };
    if (!busEmptyConfirmed) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Confirmez le bus vide avant de cloturer.')),
      );
      return;
    }
    final api = context.read<ApiService>();
    final offlineQueue = queue(context);
    try {
      await api.sendFinishCheck(
        runId: id,
        allStudentsChecked: true,
        busEmptyConfirmed: busEmptyConfirmed,
        comment: 'Mode conduite anonyme : fin de service confirmee.',
      );
      if (!mounted) return;
      setState(() => status = 'Fin de service securisee');
    } catch (_) {
      await offlineQueue.enqueue(event);
      final pending = await offlineQueue.pendingCount();
      if (!mounted) return;
      setState(() {
        queued = pending;
        status = 'Check fin de service garde hors ligne';
      });
    }
  }

  Future<void> flushQueue() async {
    final offlineQueue = queue(context);
    final sent = await offlineQueue.flush();
    final pending = await offlineQueue.pendingCount();
    if (!mounted) return;
    setState(() {
      queued = pending;
      if (sent > 0) status = '$sent evenement(s) synchronise(s)';
    });
  }

  @override
  Widget build(BuildContext context) {
    final route = context.watch<AppState>().selectedDriverRoute;
    return Theme(
      data: ThemeData.dark(useMaterial3: true).copyWith(
        colorScheme: ColorScheme.fromSeed(
            seedColor: AppTheme.primaryBlue, brightness: Brightness.dark),
      ),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Mode conduite'),
          actions: [
            IconButton(
              tooltip: 'Synchroniser',
              icon: const Icon(Icons.sync),
              onPressed: flushQueue,
            ),
          ],
        ),
        body: loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(14),
                children: [
                  _RunHeader(route: route, status: status, queued: queued),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(76),
                      backgroundColor: AppTheme.emergencyRed,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: sendSos,
                    icon: const Icon(Icons.sos, size: 34),
                    label: const Text(
                      'SOS conducteur',
                      style:
                          TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _PrivacyPanel(
                    expected: expectedCount,
                    absent: absentCount,
                    present: presentCount,
                    remaining: remainingCount,
                  ),
                  const SizedBox(height: 12),
                  Text('Charge par arret',
                      style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  if (stopLoads.isEmpty)
                    const Card(
                      child: ListTile(
                        leading: Icon(Icons.route_outlined),
                        title: Text('Aucune donnee de charge pour la tournee'),
                      ),
                    )
                  else
                    ...stopLoads.map((load) => _StopLoadTile(load: load)),
                  const SizedBox(height: 14),
                  Card(
                    child: SwitchListTile(
                      value: busEmptyConfirmed,
                      onChanged: (value) =>
                          setState(() => busEmptyConfirmed = value),
                      title: const Text('Bus vide confirme'),
                      subtitle: const Text(
                          'Verification fin de service sans affichage nominatif'),
                    ),
                  ),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(56)),
                    onPressed: finishCheck,
                    icon: const Icon(Icons.verified_user_outlined),
                    label: const Text('Cloturer la tournee en securite'),
                  ),
                ],
              ),
      ),
    );
  }
}

class _StopLoad {
  _StopLoad(this.stopName);

  final String stopName;
  int expected = 0;
  int absent = 0;
  int present = 0;

  int get remaining {
    final value = expected - absent - present;
    return value < 0 ? 0 : value;
  }
}

class _RunHeader extends StatelessWidget {
  const _RunHeader(
      {required this.route, required this.status, required this.queued});

  final NomadRoute? route;
  final String status;
  final int queued;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
              route == null
                  ? 'Tournee non selectionnee'
                  : '${route!.shortName} - ${route!.longName}',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Row(children: [
            const Icon(Icons.directions_bus_filled_outlined),
            const SizedBox(width: 8),
            Expanded(child: Text(status)),
          ]),
          if (queued > 0) ...[
            const SizedBox(height: 8),
            Row(children: [
              const Icon(Icons.cloud_off_outlined,
                  color: AppTheme.warningOrange),
              const SizedBox(width: 8),
              Text('$queued action(s) en attente de synchronisation'),
            ]),
          ],
        ]),
      ),
    );
  }
}

class _PrivacyPanel extends StatelessWidget {
  const _PrivacyPanel({
    required this.expected,
    required this.absent,
    required this.present,
    required this.remaining,
  });

  final int expected;
  final int absent;
  final int present;
  final int remaining;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.shield_outlined,
                color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Suivi anonyme',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
          ]),
          const SizedBox(height: 8),
          const Text(
              'Aucun nom, aucune photo et aucun badgeage eleve dans le poste conducteur. Les absences parent/eleve se synchronisent automatiquement.'),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: _MetricPill(
                label: 'Prevus',
                value: expected.toString(),
                icon: Icons.groups_outlined,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _MetricPill(
                label: 'Absents',
                value: absent.toString(),
                icon: Icons.event_busy_outlined,
              ),
            ),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: _MetricPill(
                label: 'Confirmes',
                value: present.toString(),
                icon: Icons.check_circle_outline,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _MetricPill(
                label: 'A surveiller',
                value: remaining.toString(),
                icon: Icons.visibility_outlined,
              ),
            ),
          ]),
        ]),
      ),
    );
  }
}

class _MetricPill extends StatelessWidget {
  const _MetricPill({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 20),
        const SizedBox(height: 6),
        Text(value,
            style: Theme.of(context)
                .textTheme
                .headlineSmall
                ?.copyWith(fontWeight: FontWeight.w900)),
        Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      ]),
    );
  }
}

class _StopLoadTile extends StatelessWidget {
  const _StopLoadTile({required this.load});

  final _StopLoad load;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          child: Text(load.expected.toString()),
        ),
        title: Text(load.stopName),
        subtitle: Text(
            '${load.remaining} a verifier - ${load.absent} absence(s) declaree(s)'),
        trailing: load.remaining == 0
            ? const Icon(Icons.check_circle_outline,
                color: AppTheme.serviceGreen)
            : const Icon(Icons.more_horiz),
      ),
    );
  }
}
