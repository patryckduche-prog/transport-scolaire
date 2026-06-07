import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/nomad_route.dart';
import '../../services/api_service.dart';
import '../../services/app_state.dart';
import '../../services/offline_event_queue.dart';

class GpsScreen extends StatefulWidget {
  const GpsScreen({super.key});

  @override
  State<GpsScreen> createState() => _GpsScreenState();
}

class _GpsScreenState extends State<GpsScreen> {
  StreamSubscription<Position>? sub;
  Position? last;
  NomadRoute? fullRoute;
  Map<String, dynamic>? coachNavigation;
  String? runId;
  String status = 'Chargement du circuit';
  String? routeError;
  String? lastStopMatchName;
  int sentCount = 0;
  int queuedCount = 0;
  int currentStop = 0;
  bool autoStartRequested = false;
  bool voiceNavigationOpened = false;
  bool loadingRoute = true;
  final FlutterTts tts = FlutterTts();

  OfflineEventQueue queue(BuildContext context) =>
      OfflineEventQueue(context.read<ApiService>());

  @override
  void initState() {
    super.initState();
    setupVoice();
    WidgetsBinding.instance.addPostFrameCallback((_) => prepareRouteAndGps());
  }

  Future<void> setupVoice() async {
    await tts.setLanguage('fr-FR');
    await tts.setSpeechRate(0.48);
    await tts.setVolume(1);
    await tts.setPitch(1);
  }

  Future<void> prepareRouteAndGps() async {
    final route = context.read<AppState>().selectedDriverRoute;
    if (route == null) {
      setState(() {
        loadingRoute = false;
        status = 'Choisissez une ligne avant le depart.';
      });
      return;
    }

    await loadFullRoute(route);
    await loadCoachNavigation(route);
    await ensureRun(route);
    if (!mounted || autoStartRequested) return;
    autoStartRequested = true;
    await startTracking();
  }

  Future<void> loadCoachNavigation(NomadRoute route) async {
    try {
      final data =
          await context.read<ApiService>().getCoachNavigation(route.id);
      if (!mounted) return;
      setState(() => coachNavigation = data);
    } catch (_) {
      if (!mounted) return;
      setState(() => coachNavigation = null);
    }
  }

  Future<void> loadFullRoute(NomadRoute route) async {
    try {
      final data = await context.read<ApiService>().getNomadRoute(route.id);
      if (!mounted) return;
      setState(() {
        fullRoute = NomadRoute.fromJson(data);
        routeError = null;
        loadingRoute = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        fullRoute = route;
        routeError =
            'Circuit complet indisponible, affichage de l apercu local.';
        loadingRoute = false;
      });
    }
  }

  Future<void> ensureRun(NomadRoute route) async {
    try {
      final api = context.read<ApiService>();
      final current = await api.getCurrentRun();
      final sameRoute = current?['route_external_id'] == route.id ||
          current?['routeExternalId'] == route.id;
      final run = sameRoute
          ? current!
          : await api.startRun(
              routeId: route.id,
              routeName: '${route.shortName} - ${route.longName}',
            );
      if (!mounted) return;
      setState(() {
        runId = run['id'] as String;
        status = 'Tournee GPS ouverte';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => status =
          'Tournee serveur indisponible, suivi local en attente reseau.');
    }
  }

  String cleanStopName(String name) {
    final withoutTime = name.replaceAll(RegExp(r'\s*\([^)]*\)'), '').trim();
    return '$withoutTime, Normandie, France';
  }

  List<String> routeStops(NomadRoute route) => route.stopsPreview
      .map((stop) => cleanStopName(stop.name))
      .where((name) => name.trim().isNotEmpty)
      .toList();

  Future<bool> ensureLocationReady() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      setState(() => status = 'Activez la localisation du telephone.');
      return false;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      setState(() => status = 'Autorisation GPS refusee.');
      return false;
    }
    return true;
  }

  Future<void> startTracking() async {
    final route = context.read<AppState>().selectedDriverRoute;
    if (route == null) return;
    if (!await ensureLocationReady()) return;

    await sub?.cancel();
    setState(() => status = 'Suivi GPS actif automatiquement');
    await speakCoachPrompt();
    sub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best, distanceFilter: 10),
    ).listen((position) => sendPosition(route, position));
    await openGoogleMapsGuidance(auto: true);
  }

  Future<void> speakCoachPrompt() async {
    final route = fullRoute ?? context.read<AppState>().selectedDriverRoute;
    final provider = coachNavigation?['provider'] as String?;
    final text = provider == null
        ? 'Navigation car scolaire active. Suivez le circuit officiel.'
        : 'Navigation car scolaire active avec moteur $provider. Suivez le circuit officiel valide par l exploitation.';
    try {
      await tts.stop();
      await tts.speak(text);
    } catch (_) {}
    if (route == null) return;
  }

  Future<void> sendPosition(NomadRoute route, Position position) async {
    if (!mounted) return;
    setState(() => last = position);

    final id = runId;
    final recordedAt = DateTime.now().toIso8601String();
    final api = context.read<ApiService>();
    final offlineQueue = queue(context);

    try {
      if (id == null) {
        await api.sendGps(
          route.id,
          position.latitude,
          position.longitude,
          position.speed,
          routeName: '${route.shortName} - ${route.longName}',
        );
      } else {
        final result = await api.sendRunGps(
          runId: id,
          latitude: position.latitude,
          longitude: position.longitude,
          speed: position.speed,
          recordedAt: recordedAt,
        );
        updateStopFromMatch(result['stopMatch']);
      }
      final flushed = await offlineQueue.flush();
      final pending = await offlineQueue.pendingCount();
      if (!mounted) return;
      setState(() {
        sentCount++;
        queuedCount = pending;
        status = flushed > 0
            ? '$flushed position(s) hors ligne synchronisee(s)'
            : 'Position envoyee au serveur';
      });
    } catch (_) {
      if (id != null) {
        await offlineQueue.enqueue({
          'type': 'runGps',
          'runId': id,
          'latitude': position.latitude,
          'longitude': position.longitude,
          'speed': position.speed,
          'recordedAt': recordedAt,
        });
      }
      final pending = await offlineQueue.pendingCount();
      if (mounted) {
        setState(() {
          queuedCount = pending;
          status = 'Position gardee sur le telephone, serveur indisponible';
        });
      }
    }
  }

  void updateStopFromMatch(dynamic match) {
    if (match is! Map<String, dynamic>) return;
    final route = fullRoute ?? context.read<AppState>().selectedDriverRoute;
    final stops = route?.stopsPreview ?? [];
    if (stops.isEmpty) return;

    final stopExternalId = match['stopExternalId'] as String? ?? '';
    final stopName = match['stopName'] as String? ?? '';
    var nextIndex = -1;
    final sequence = int.tryParse(stopExternalId.split('-').last);
    if (sequence != null) {
      nextIndex = stops.indexWhere((stop) => stop.sequence == sequence);
    }
    if (nextIndex < 0 && stopName.isNotEmpty) {
      final normalizedMatch = normalize(stopName);
      nextIndex = stops.indexWhere(
        (stop) =>
            normalize(stop.name).contains(normalizedMatch) ||
            normalizedMatch.contains(normalize(stop.name)),
      );
    }
    if (nextIndex < 0) return;
    setState(() {
      currentStop = nextIndex;
      lastStopMatchName = stopName;
    });
    if (stopName.isNotEmpty) {
      tts.speak('Arret detecte : $stopName');
    }
  }

  String normalize(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'\s*\([^)]*\)'), '')
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .trim();

  Future<void> openGoogleMapsGuidance({bool auto = false}) async {
    final route = fullRoute ?? context.read<AppState>().selectedDriverRoute;
    if (route == null) return;
    if (auto && voiceNavigationOpened) return;
    if (!auto && sub == null) await startTracking();

    final stops = routeStops(route);
    if (stops.isEmpty) {
      setState(() => status = 'Aucun arret disponible pour ouvrir le guidage.');
      return;
    }

    final destination = stops.last;
    final waypoints = stops.length <= 2
        ? <String>[]
        : stops.sublist(0, stops.length - 1).take(8).toList();
    final params = <String, String>{
      'api': '1',
      'travelmode': 'driving',
      'destination': destination,
      if (waypoints.isNotEmpty) 'waypoints': waypoints.join('|'),
    };
    final uri = Uri.https('www.google.com', '/maps/dir/', params);
    voiceNavigationOpened = true;
    await launchExternal(
      uri,
      auto
          ? 'Navigation vocale Google Maps ouverte avec les arrets du circuit.'
          : 'Google Maps ouvert avec les arrets du circuit.',
    );
  }

  Future<void> openWazeGuidance() async {
    final route = fullRoute ?? context.read<AppState>().selectedDriverRoute;
    if (route == null) return;
    if (sub == null) await startTracking();

    final stops = routeStops(route);
    if (stops.isEmpty) {
      setState(() => status = 'Aucun arret disponible pour ouvrir Waze.');
      return;
    }

    final destination = stops.last;
    final appUri =
        Uri.parse('waze://?q=${Uri.encodeComponent(destination)}&navigate=yes');
    final webUri =
        Uri.https('waze.com', '/ul', {'q': destination, 'navigate': 'yes'});
    try {
      final opened =
          await launchUrl(appUri, mode: LaunchMode.externalApplication);
      if (!opened) {
        await launchExternal(webUri, 'Waze ouvert en secours voiture.');
      }
      if (mounted) {
        setState(() =>
            status = 'Waze ouvert en secours voiture et suivi serveur actif.');
      }
    } catch (_) {
      await launchExternal(webUri, 'Waze ouvert en secours voiture.');
    }
  }

  Future<void> launchExternal(Uri uri, String successMessage) async {
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!mounted) return;
    setState(() => status = opened
        ? '$successMessage Suivi serveur actif.'
        : 'Impossible d ouvrir le guidage.');
  }

  Future<void> stop() async {
    await sub?.cancel();
    sub = null;
    if (mounted) setState(() => status = 'GPS arrete');
  }

  @override
  void dispose() {
    sub?.cancel();
    tts.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selectedRoute = context.watch<AppState>().selectedDriverRoute;
    final route = fullRoute ?? selectedRoute;
    final stops = route?.stopsPreview ?? [];
    final guidance = route?.coachGuidance;
    final vehicle = guidance?.vehicleProfile;
    final provider =
        coachNavigation?['provider'] as String? ?? 'reference locale';
    final distance = coachNavigation?['distanceMeters'] is num
        ? ((coachNavigation!['distanceMeters'] as num) / 1000)
            .toStringAsFixed(1)
        : null;
    final tracking = sub != null;
    final safeStopIndex =
        stops.isEmpty ? 0 : currentStop.clamp(0, stops.length - 1).toInt();
    final nextStop = stops.isEmpty ? null : stops[safeStopIndex];
    return Scaffold(
      appBar: AppBar(title: const Text('Suivi GPS')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: Icon(tracking
                  ? Icons.directions_bus_filled
                  : Icons.directions_bus_filled_outlined),
              title: Text(route == null
                  ? 'Aucune ligne active'
                  : '${route.shortName} - ${route.longName}'),
              subtitle: Text(route == null
                  ? 'Choisissez une ligne avant le depart.'
                  : loadingRoute
                      ? 'Chargement du circuit officiel'
                      : '${stops.length} arrets charges - suivi automatique'),
            ),
          ),
          if (routeError != null)
            Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: ListTile(
                leading: Icon(Icons.warning_amber_outlined,
                    color: Theme.of(context).colorScheme.onErrorContainer),
                title: Text(routeError!,
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.onErrorContainer)),
              ),
            ),
          const SizedBox(height: 12),
          _RouteProgressCard(
            stops: stops,
            currentStop: currentStop,
            tracking: tracking,
            status: status,
            last: last,
            sentCount: sentCount,
            queuedCount: queuedCount,
            lastStopMatchName: lastStopMatchName,
          ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const Icon(Icons.alt_route_outlined),
              title: Text('Moteur GPS : $provider'),
              subtitle: Text(distance == null
                  ? 'Profil autocar avec regles locales et arrets officiels'
                  : 'Itineraire calcule : $distance km - voix Android active'),
              trailing: IconButton(
                tooltip: 'Ecouter',
                icon: const Icon(Icons.volume_up_outlined),
                onPressed: speakCoachPrompt,
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (nextStop != null)
            Card(
              child: ListTile(
                leading:
                    CircleAvatar(child: Text(nextStop.sequence.toString())),
                title: const Text('Arret suivi automatiquement'),
                subtitle: Text(nextStop.name),
                trailing: Icon(
                  tracking ? Icons.gps_fixed : Icons.gps_not_fixed,
                  color: tracking ? Colors.green : null,
                ),
              ),
            ),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: route == null ? null : openGoogleMapsGuidance,
                icon: const Icon(Icons.navigation_outlined),
                label: const Text('GPS vocal'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: route == null ? null : openWazeGuidance,
                icon: const Icon(Icons.assistant_direction_outlined),
                label: const Text('Waze'),
              ),
            ),
          ]),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: tracking ? stop : startTracking,
            icon: Icon(tracking
                ? Icons.stop_circle_outlined
                : Icons.play_circle_outline),
            label: Text(tracking ? 'Arreter le suivi' : 'Relancer le GPS'),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.privacy_tip_outlined,
                          color: Theme.of(context).colorScheme.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Mode car scolaire',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    vehicle == null
                        ? 'Profil vehicule : autocar scolaire a verifier.'
                        : 'Profil vehicule : ${vehicle.label} - ${vehicle.lengthMeters?.toStringAsFixed(1) ?? '?'} m x ${vehicle.widthMeters?.toStringAsFixed(2) ?? '?'} m.',
                  ),
                  if (guidance?.corridor != null) ...[
                    const SizedBox(height: 6),
                    Text('Couloir : ${guidance!.corridor}'),
                  ],
                  const SizedBox(height: 8),
                  Text(
                    guidance?.safetyNotice.isNotEmpty == true
                        ? guidance!.safetyNotice
                        : 'Suivre le circuit officiel valide par l exploitation.',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  Text(guidance?.externalNavigationNotice.isNotEmpty == true
                      ? guidance!.externalNavigationNotice
                      : 'Google Maps est ouvert pour le guidage vocal. Le circuit officiel reste la reference car scolaire.'),
                  if ((guidance?.rules ?? []).isNotEmpty) ...[
                    const SizedBox(height: 10),
                    ...guidance!.rules.take(8).map(
                          (rule) => Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(Icons.check_circle_outline,
                                    size: 18),
                                const SizedBox(width: 8),
                                Expanded(
                                    child: Text(
                                        '${rule.label} : ${rule.description}')),
                              ],
                            ),
                          ),
                        ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text('Parcours officiel',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          if (stops.isEmpty)
            const Card(
                child: ListTile(
                    leading: Icon(Icons.info_outline),
                    title: Text('Aucun arret charge pour cette ligne')))
          else
            ...stops.map((stop) {
              final index = stops.indexOf(stop);
              final active = index == currentStop;
              final passed = index < currentStop;
              return Card(
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: active
                        ? Theme.of(context).colorScheme.primary
                        : passed
                            ? Colors.green.shade700
                            : null,
                    foregroundColor: active || passed ? Colors.white : null,
                    child: Text(stop.sequence.toString()),
                  ),
                  title: Text(stop.name),
                  subtitle:
                      stop.arrivalTime.isEmpty ? null : Text(stop.arrivalTime),
                  trailing: active
                      ? const Icon(Icons.directions_bus_outlined)
                      : passed
                          ? const Icon(Icons.check)
                          : null,
                ),
              );
            }),
        ],
      ),
    );
  }
}

class _RouteProgressCard extends StatelessWidget {
  const _RouteProgressCard({
    required this.stops,
    required this.currentStop,
    required this.tracking,
    required this.status,
    required this.last,
    required this.sentCount,
    required this.queuedCount,
    required this.lastStopMatchName,
  });

  final List<NomadStop> stops;
  final int currentStop;
  final bool tracking;
  final String status;
  final Position? last;
  final int sentCount;
  final int queuedCount;
  final String? lastStopMatchName;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(tracking ? Icons.gps_fixed : Icons.gps_not_fixed,
                color: tracking ? Colors.green.shade700 : null),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                tracking
                    ? 'GPS actif automatiquement'
                    : 'GPS en attente autorisation',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
          ]),
          const SizedBox(height: 8),
          Text(status),
          const SizedBox(height: 12),
          SizedBox(
            height: 170,
            width: double.infinity,
            child: CustomPaint(
              painter: _RoutePainter(
                stopCount: stops.length,
                currentIndex: stops.isEmpty
                    ? 0
                    : currentStop.clamp(0, stops.length - 1).toInt(),
                tracking: tracking,
                primary: Theme.of(context).colorScheme.primary,
              ),
              child: Center(
                child: Icon(
                  Icons.directions_bus_filled,
                  size: 46,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: _GpsMetric(
                label: 'Envois',
                value: sentCount.toString(),
                icon: Icons.cloud_done_outlined,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _GpsMetric(
                label: 'En attente',
                value: queuedCount.toString(),
                icon: Icons.cloud_off_outlined,
              ),
            ),
          ]),
          if (last != null) ...[
            const SizedBox(height: 10),
            Text(
              'Derniere position : ${last!.latitude.toStringAsFixed(6)}, ${last!.longitude.toStringAsFixed(6)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          if (lastStopMatchName != null) ...[
            const SizedBox(height: 6),
            Text(
              'Georepere detecte : $lastStopMatchName',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ]),
      ),
    );
  }
}

class _GpsMetric extends StatelessWidget {
  const _GpsMetric({
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
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(children: [
        Icon(icon, size: 18),
        const SizedBox(width: 8),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(value,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w900)),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ]),
      ]),
    );
  }
}

class _RoutePainter extends CustomPainter {
  const _RoutePainter({
    required this.stopCount,
    required this.currentIndex,
    required this.tracking,
    required this.primary,
  });

  final int stopCount;
  final int currentIndex;
  final bool tracking;
  final Color primary;

  @override
  void paint(Canvas canvas, Size size) {
    final road = Paint()
      ..color = const Color(0xFFE6ECEE)
      ..strokeWidth = 18
      ..strokeCap = StrokeCap.round;
    final progress = Paint()
      ..color = primary
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round;
    final path = Path()
      ..moveTo(24, size.height - 28)
      ..quadraticBezierTo(size.width * .35, 28, size.width * .62, 80)
      ..quadraticBezierTo(size.width * .82, 118, size.width - 24, 34);
    canvas.drawPath(path, road);
    if (stopCount > 1) {
      final progressEnd = currentIndex / (stopCount - 1);
      final metric = path.computeMetrics().first;
      final extract = metric.extractPath(0, metric.length * progressEnd);
      canvas.drawPath(extract, progress);
    }

    final points = _samplePath(path, stopCount == 0 ? 5 : stopCount);
    final dotPaint = Paint()..color = Colors.white;
    final borderPaint = Paint()
      ..color = const Color(0xFF607177)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;
    final activePaint = Paint()..color = primary;
    final donePaint = Paint()..color = Colors.green.shade700;
    for (var index = 0; index < points.length; index++) {
      final point = points[index];
      canvas.drawCircle(point, 11, dotPaint);
      if (index < currentIndex) {
        canvas.drawCircle(point, 10, donePaint);
      } else if (index == currentIndex && tracking) {
        canvas.drawCircle(point, 12, activePaint);
      } else {
        canvas.drawCircle(point, 10, dotPaint);
        canvas.drawCircle(point, 10, borderPaint);
      }
    }
  }

  List<Offset> _samplePath(Path path, int count) {
    final metric = path.computeMetrics().first;
    if (count <= 1) return [metric.getTangentForOffset(0)!.position];
    return List<Offset>.generate(count, (index) {
      final offset = metric.length * (index / (count - 1));
      return metric.getTangentForOffset(offset)!.position;
    });
  }

  @override
  bool shouldRepaint(covariant _RoutePainter oldDelegate) =>
      stopCount != oldDelegate.stopCount ||
      currentIndex != oldDelegate.currentIndex ||
      tracking != oldDelegate.tracking ||
      primary != oldDelegate.primary;
}
