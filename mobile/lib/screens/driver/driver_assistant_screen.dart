import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/nomad_route.dart';
import '../../services/api_service.dart';
import '../../services/app_state.dart';
import '../../services/offline_event_queue.dart';

class DriverAssistantScreen extends StatefulWidget {
  const DriverAssistantScreen({super.key});

  @override
  State<DriverAssistantScreen> createState() => _DriverAssistantScreenState();
}

class _DriverAssistantScreenState extends State<DriverAssistantScreen> {
  String? runId;
  List<Map<String, dynamic>> students = [];
  bool loading = true;
  bool busEmptyConfirmed = false;
  int queued = 0;
  String status = 'Initialisation assistant conduite';

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
        students = data.cast<Map<String, dynamic>>();
        queued = pending;
        loading = false;
        status = 'Tournee active - ${students.length} eleves attendus';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        loading = false;
        status = 'Mode hors ligne : les actions seront synchronisees ensuite.';
      });
    }
  }

  Future<void> markPresence(Map<String, dynamic> student, bool present) async {
    final id = runId;
    if (id == null) return;
    final nextStatus = present ? 'present' : 'not_seen';
    setState(() {
      student['present'] = present;
      student['status'] = nextStatus;
    });
    final event = {
      'type': 'presence',
      'runId': id,
      'studentId': student['id'],
      'present': present,
      'status': nextStatus,
    };
    final api = context.read<ApiService>();
    final offlineQueue = queue(context);
    try {
      await api.updateRunStudentPresence(
        runId: id,
        studentId: student['id'] as String,
        present: present,
        status: nextStatus,
      );
      await flushQueue();
      if (!mounted) return;
      setState(() =>
          status = present ? 'Presence envoyee' : 'Eleve non vu enregistre');
    } catch (_) {
      await offlineQueue.enqueue(event);
      final pending = await offlineQueue.pendingCount();
      if (!mounted) return;
      setState(() {
        queued = pending;
        status = 'Action gardee hors ligne';
      });
    }
  }

  Future<void> sendSos() async {
    final id = runId;
    if (id == null) return;
    final event = {
      'type': 'incident',
      'runId': id,
      'incidentType': 'sos',
      'message': 'Demande assistance conducteur',
      'severity': 'critical',
    };
    final api = context.read<ApiService>();
    final offlineQueue = queue(context);
    try {
      await api.sendRunIncident(
        runId: id,
        type: 'sos',
        message: 'Demande assistance conducteur',
        severity: 'critical',
      );
      if (!mounted) return;
      setState(() => status = 'SOS envoye a la regulation');
    } catch (_) {
      await offlineQueue.enqueue(event);
      final pending = await offlineQueue.pendingCount();
      if (!mounted) return;
      setState(() {
        queued = pending;
        status = 'SOS garde hors ligne, envoi des retour reseau';
      });
    }
  }

  Future<void> finishCheck() async {
    final id = runId;
    if (id == null) return;
    final allChecked =
        students.every((student) => student['status'] != 'expected');
    final event = {
      'type': 'finishCheck',
      'runId': id,
      'allStudentsChecked': allChecked,
      'busEmptyConfirmed': busEmptyConfirmed,
      'comment': '',
    };
    if (!allChecked || !busEmptyConfirmed) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Validez tous les eleves et confirmez bus vide.')),
      );
      return;
    }
    final api = context.read<ApiService>();
    final offlineQueue = queue(context);
    try {
      await api.sendFinishCheck(
        runId: id,
        allStudentsChecked: allChecked,
        busEmptyConfirmed: busEmptyConfirmed,
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
            seedColor: const Color(0xFF0F6F78), brightness: Brightness.dark),
      ),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Assistant conduite'),
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
                      minimumSize: const Size.fromHeight(58),
                      backgroundColor: Colors.red.shade700,
                    ),
                    onPressed: sendSos,
                    icon: const Icon(Icons.sos),
                    label: const Text('SOS / Incident regulation'),
                  ),
                  const SizedBox(height: 12),
                  Text('Trombinoscope tournee',
                      style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  if (students.isEmpty)
                    const Card(
                        child: ListTile(
                            leading: Icon(Icons.people_outline),
                            title:
                                Text('Aucun eleve charge pour cette tournee')))
                  else
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        childAspectRatio: .88,
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 10,
                      ),
                      itemCount: students.length,
                      itemBuilder: (context, index) => _StudentTile(
                        student: students[index],
                        onPresent: () => markPresence(students[index], true),
                        onNotSeen: () => markPresence(students[index], false),
                      ),
                    ),
                  const SizedBox(height: 14),
                  Card(
                    child: SwitchListTile(
                      value: busEmptyConfirmed,
                      onChanged: (value) =>
                          setState(() => busEmptyConfirmed = value),
                      title: const Text('Bus vide confirme'),
                      subtitle: const Text(
                          'Verification obligatoire pour eviter tout oubli d enfant'),
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
              const Icon(Icons.cloud_off_outlined, color: Colors.orange),
              const SizedBox(width: 8),
              Text('$queued action(s) en attente de synchronisation'),
            ]),
          ],
        ]),
      ),
    );
  }
}

class _StudentTile extends StatelessWidget {
  const _StudentTile(
      {required this.student,
      required this.onPresent,
      required this.onNotSeen});

  final Map<String, dynamic> student;
  final VoidCallback onPresent;
  final VoidCallback onNotSeen;

  @override
  Widget build(BuildContext context) {
    final status = student['status'] as String? ?? 'expected';
    final present = status == 'present';
    final notSeen = status == 'not_seen' || status == 'absent';
    final color = present
        ? Colors.green.shade700
        : (notSeen ? Colors.orange.shade700 : Colors.blueGrey.shade700);
    final firstName = student['firstName'] as String? ?? '?';
    final lastName = student['lastName'] as String? ?? '';
    final initials =
        '${firstName.isEmpty ? '?' : firstName[0]}${lastName.isEmpty ? '' : lastName[0]}';
    return Card(
      color: color.withValues(alpha: .18),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CircleAvatar(
              radius: 28,
              backgroundColor: color,
              child: Text(initials,
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 20)),
            ),
            const SizedBox(height: 8),
            Text('${student['firstName']} ${student['lastName']}',
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
            Text(student['stopName'] as String? ?? '',
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall),
            const Spacer(),
            Row(children: [
              Expanded(
                child: IconButton.filled(
                  tooltip: 'Present',
                  onPressed: onPresent,
                  icon: const Icon(Icons.check),
                  style: IconButton.styleFrom(
                      backgroundColor: Colors.green.shade700),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: IconButton.filledTonal(
                  tooltip: 'Non vu',
                  onPressed: onNotSeen,
                  icon: const Icon(Icons.close),
                ),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}
