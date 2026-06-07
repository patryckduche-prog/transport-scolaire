import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart' show LatLng;
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
  Timer? simulationTimer;
  Position? last;
  LatLng? coachPoint;
  double coachHeading = 0;
  int simulationIndex = 0;
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
  bool loadingRoute = true;
  bool simulationActive = false;
  bool realGpsLocked = false;
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
      initializeCoachOnRoute();
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

  List<String> coordinateStops() {
    final rawStops = coachNavigation?['stops'];
    if (rawStops is! List) return [];
    return rawStops
        .whereType<Map<String, dynamic>>()
        .where((stop) => stop['latitude'] is num && stop['longitude'] is num)
        .map((stop) {
      final latitude = (stop['latitude'] as num).toDouble();
      final longitude = (stop['longitude'] as num).toDouble();
      return '$latitude,$longitude';
    }).toList();
  }

  List<LatLng> routeGeometry() {
    final rawGeometry = coachNavigation?['geometry'];
    if (rawGeometry is! List) return [];
    return rawGeometry.whereType<Map<String, dynamic>>().where((point) {
      return point['latitude'] is num && point['longitude'] is num;
    }).map((point) {
      return LatLng(
        (point['latitude'] as num).toDouble(),
        (point['longitude'] as num).toDouble(),
      );
    }).toList();
  }

  bool validCoordinate(double latitude, double longitude) =>
      latitude >= -90 &&
      latitude <= 90 &&
      longitude >= -180 &&
      longitude <= 180 &&
      !(latitude == 0 && longitude == 0);

  double headingBetween(LatLng from, LatLng to) {
    final lat1 = from.latitude * math.pi / 180;
    final lat2 = to.latitude * math.pi / 180;
    final deltaLng = (to.longitude - from.longitude) * math.pi / 180;
    final y = math.sin(deltaLng) * math.cos(lat2);
    final x = math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(deltaLng);
    return math.atan2(y, x);
  }

  int nearestGeometryIndex(LatLng point, List<LatLng> geometry) {
    var bestIndex = 0;
    var bestDistance = double.infinity;
    for (var index = 0; index < geometry.length; index++) {
      final candidate = geometry[index];
      final distance = Geolocator.distanceBetween(point.latitude,
          point.longitude, candidate.latitude, candidate.longitude);
      if (distance < bestDistance) {
        bestDistance = distance;
        bestIndex = index;
      }
    }
    return bestIndex;
  }

  double distanceFromRoute(LatLng point, List<LatLng> geometry) {
    if (geometry.isEmpty) return double.infinity;
    final index = nearestGeometryIndex(point, geometry);
    final candidate = geometry[index];
    return Geolocator.distanceBetween(point.latitude, point.longitude,
        candidate.latitude, candidate.longitude);
  }

  void initializeCoachOnRoute() {
    final geometry = routeGeometry();
    if (geometry.isEmpty || coachPoint != null) return;
    final startIndex = geometry.length > 2 ? 1 : 0;
    final nextIndex = math.min(startIndex + 1, geometry.length - 1);
    setState(() {
      simulationIndex = startIndex;
      coachPoint = geometry[startIndex];
      coachHeading = headingBetween(geometry[startIndex], geometry[nextIndex]);
      simulationActive = true;
      status = 'Simulation GPS active sur le circuit';
    });
  }

  void startSimulation() {
    simulationTimer?.cancel();
    final geometry = routeGeometry();
    if (geometry.length < 2) return;
    initializeCoachOnRoute();
    simulationTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (!mounted) return;
      if (realGpsLocked) return;
      final latestGeometry = routeGeometry();
      if (latestGeometry.length < 2) return;
      final step = math.max(1, (latestGeometry.length / 120).round());
      var nextIndex = simulationIndex + step;
      if (nextIndex >= latestGeometry.length - 1) nextIndex = 0;
      final previousPoint = latestGeometry[simulationIndex];
      final nextPoint = latestGeometry[nextIndex];
      setState(() {
        simulationIndex = nextIndex;
        coachPoint = nextPoint;
        coachHeading = headingBetween(previousPoint, nextPoint);
        simulationActive = true;
      });
    });
  }

  void updateVisibleCoachFromGps(Position position) {
    if (!validCoordinate(position.latitude, position.longitude)) return;
    final realPoint = LatLng(position.latitude, position.longitude);
    final geometry = routeGeometry();
    if (geometry.isEmpty) {
      setState(() {
        coachPoint = realPoint;
        simulationActive = false;
      });
      return;
    }

    if (distanceFromRoute(realPoint, geometry) <= 500) {
      final index = nearestGeometryIndex(realPoint, geometry);
      final nextIndex = math.min(index + 1, geometry.length - 1);
      setState(() {
        simulationIndex = index;
        coachPoint = geometry[index];
        coachHeading = headingBetween(geometry[index], geometry[nextIndex]);
        simulationActive = false;
        realGpsLocked = true;
      });
    } else {
      realGpsLocked = false;
      if (coachPoint == null) initializeCoachOnRoute();
    }
  }

  List<_MapStop> mapStops() {
    final rawStops = coachNavigation?['stops'];
    if (rawStops is! List) return [];
    return rawStops.whereType<Map<String, dynamic>>().where((stop) {
      return stop['latitude'] is num && stop['longitude'] is num;
    }).map((stop) {
      return _MapStop(
        sequence: (stop['sequence'] as num?)?.toInt() ?? 0,
        name: stop['name'] as String? ?? 'Arret',
        point: LatLng(
          (stop['latitude'] as num).toDouble(),
          (stop['longitude'] as num).toDouble(),
        ),
      );
    }).toList();
  }

  List<Map<String, dynamic>> navigationSteps() {
    final rawSteps = coachNavigation?['steps'];
    if (rawSteps is! List) return [];
    return rawSteps.whereType<Map<String, dynamic>>().toList();
  }

  Map<String, dynamic>? currentNavigationStep() {
    final steps = navigationSteps();
    if (steps.isEmpty) return null;
    return steps.firstWhere(
      (step) {
        final instruction =
            (step['instruction'] as String? ?? '').toLowerCase();
        return !instruction.startsWith('depart');
      },
      orElse: () => steps.first,
    );
  }

  String currentInstructionText() {
    final step = currentNavigationStep();
    return step?['instruction'] as String? ??
        'Continuez sur le circuit officiel.';
  }

  int? currentInstructionDistance() {
    final distance = currentNavigationStep()?['distanceMeters'];
    return distance is num ? distance.round() : null;
  }

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
    try {
      final current = await Geolocator.getCurrentPosition(
        locationSettings:
            const LocationSettings(accuracy: LocationAccuracy.best),
      ).timeout(const Duration(seconds: 5));
      updateVisibleCoachFromGps(current);
      await sendPosition(route, current);
    } catch (_) {
      initializeCoachOnRoute();
    }
    startSimulation();
    sub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best, distanceFilter: 10),
    ).listen((position) async {
      updateVisibleCoachFromGps(position);
      await sendPosition(route, position);
    });
  }

  Future<void> speakCoachPrompt() async {
    final provider = coachNavigation?['provider'] as String?;
    final instruction = currentInstructionText();
    final distance = currentInstructionDistance();
    final text = provider == null
        ? 'Navigation car scolaire active. $instruction'
        : 'Navigation car scolaire active avec moteur $provider. ${distance == null ? instruction : 'Dans $distance metres, $instruction'}';
    try {
      await tts.stop();
      await tts.speak(text);
    } catch (_) {}
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

  Future<void> openGoogleMapsGuidance() async {
    final route = fullRoute ?? context.read<AppState>().selectedDriverRoute;
    if (route == null) return;
    if (sub == null) await startTracking();

    final coordinateRouteStops = coordinateStops();
    final stops = coordinateRouteStops.isNotEmpty
        ? coordinateRouteStops
        : routeStops(route);
    if (stops.isEmpty) {
      setState(() => status = 'Aucun arret disponible pour ouvrir le guidage.');
      return;
    }

    final origin = stops.first;
    final destination = stops.last;
    final waypoints = stops.length <= 2
        ? <String>[]
        : stops.sublist(1, stops.length - 1).take(8).toList();
    final params = <String, String>{
      'api': '1',
      'travelmode': 'driving',
      'origin': origin,
      'destination': destination,
      if (waypoints.isNotEmpty) 'waypoints': waypoints.join('|'),
    };
    final uri = Uri.https('www.google.com', '/maps/dir/', params);
    await launchExternal(
      uri,
      coordinateRouteStops.isNotEmpty
          ? 'Google Maps ouvert avec les coordonnees des arrets du circuit.'
          : 'Google Maps ouvert avec les noms des arrets du circuit.',
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
    simulationTimer?.cancel();
    sub = null;
    if (mounted) {
      setState(() {
        simulationActive = false;
        realGpsLocked = false;
        status = 'GPS arrete';
      });
    }
  }

  @override
  void dispose() {
    sub?.cancel();
    simulationTimer?.cancel();
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
          _NavigationCommandCard(
            instruction: currentInstructionText(),
            distanceMeters: currentInstructionDistance(),
            onSpeak: speakCoachPrompt,
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
            instruction: currentInstructionText(),
            geometry: routeGeometry(),
            mapStops: mapStops(),
            coachPoint: coachPoint,
            coachHeading: coachHeading,
            simulationActive: simulationActive,
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
                label: const Text('Maps option'),
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
    required this.instruction,
    required this.geometry,
    required this.mapStops,
    required this.coachPoint,
    required this.coachHeading,
    required this.simulationActive,
  });

  final List<NomadStop> stops;
  final int currentStop;
  final bool tracking;
  final String status;
  final Position? last;
  final int sentCount;
  final int queuedCount;
  final String? lastStopMatchName;
  final String instruction;
  final List<LatLng> geometry;
  final List<_MapStop> mapStops;
  final LatLng? coachPoint;
  final double coachHeading;
  final bool simulationActive;

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
            height: 260,
            width: double.infinity,
            child: geometry.length > 1
                ? _CoachMap(
                    geometry: geometry,
                    stops: mapStops,
                    currentStop: currentStop,
                    primary: Theme.of(context).colorScheme.primary,
                    instruction: instruction,
                    coachPoint: coachPoint,
                    coachHeading: coachHeading,
                    simulationActive: simulationActive,
                  )
                : CustomPaint(
                    painter: _RoutePainter(
                      stopCount: stops.length,
                      currentIndex: stops.isEmpty
                          ? 0
                          : currentStop.clamp(0, stops.length - 1).toInt(),
                      tracking: tracking,
                      primary: Theme.of(context).colorScheme.primary,
                      instruction: instruction,
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

class _MapStop {
  const _MapStop({
    required this.sequence,
    required this.name,
    required this.point,
  });

  final int sequence;
  final String name;
  final LatLng point;
}

class _CoachMap extends StatelessWidget {
  const _CoachMap({
    required this.geometry,
    required this.stops,
    required this.currentStop,
    required this.primary,
    required this.instruction,
    required this.coachPoint,
    required this.coachHeading,
    required this.simulationActive,
  });

  final List<LatLng> geometry;
  final List<_MapStop> stops;
  final int currentStop;
  final Color primary;
  final String instruction;
  final LatLng? coachPoint;
  final double coachHeading;
  final bool simulationActive;

  IconData get instructionIcon {
    final lower = instruction.toLowerCase();
    if (lower.contains('droite')) return Icons.turn_right;
    if (lower.contains('gauche')) return Icons.turn_left;
    if (lower.contains('rond-point') || lower.contains('rond point')) {
      return Icons.roundabout_right;
    }
    return Icons.straight;
  }

  LatLng get mapCenter {
    if (coachPoint != null) return coachPoint!;
    if (geometry.isEmpty) return const LatLng(49.70, 1.65);
    final middle = geometry[geometry.length ~/ 2];
    return middle;
  }

  LatLng get fallbackCoachPoint {
    if (geometry.isEmpty) return mapCenter;
    final index = ((geometry.length - 1) *
            (stops.isEmpty
                ? .28
                : (currentStop / math.max(1, stops.length - 1)).clamp(.08, .9)))
        .round()
        .clamp(0, geometry.length - 1);
    return geometry[index];
  }

  double get fallbackCoachHeading {
    if (geometry.length < 2) return 0;
    final point = fallbackCoachPoint;
    final index = geometry.indexOf(point).clamp(0, geometry.length - 1);
    final nextIndex = math.min(index + 1, geometry.length - 1);
    return index == nextIndex ? 0 : _bearing(geometry[index], geometry[nextIndex]);
  }

  double _bearing(LatLng from, LatLng to) {
    final lat1 = from.latitude * math.pi / 180;
    final lat2 = to.latitude * math.pi / 180;
    final deltaLng = (to.longitude - from.longitude) * math.pi / 180;
    final y = math.sin(deltaLng) * math.cos(lat2);
    final x = math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(deltaLng);
    return math.atan2(y, x);
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Stack(children: [
        FlutterMap(
          key: ValueKey(
              '${mapCenter.latitude.toStringAsFixed(5)}-${mapCenter.longitude.toStringAsFixed(5)}'),
          options: MapOptions(
            initialCenter: mapCenter,
            initialZoom: 12.2,
            interactionOptions:
                const InteractionOptions(flags: InteractiveFlag.none),
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'fr.busscolaireconnect.mobile',
            ),
            PolylineLayer(
              polylines: [
                Polyline(
                  points: geometry,
                  strokeWidth: 7,
                  color: primary,
                ),
                Polyline(
                  points: geometry,
                  strokeWidth: 2,
                  color: Colors.white.withValues(alpha: .8),
                ),
              ],
            ),
            MarkerLayer(
              markers: [
                ...stops.map(
                  (stop) => Marker(
                    point: stop.point,
                    width: 34,
                    height: 34,
                    child: Container(
                      decoration: BoxDecoration(
                        color: stop.sequence <= currentStop + 1
                            ? Colors.green.shade700
                            : Colors.blueGrey.shade600,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 3),
                        boxShadow: const [
                          BoxShadow(
                              color: Colors.black26,
                              blurRadius: 5,
                              offset: Offset(0, 2)),
                        ],
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        stop.sequence.toString(),
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 12),
                      ),
                    ),
                  ),
                ),
                Marker(
                  point: coachPoint ?? fallbackCoachPoint,
                  width: 156,
                  height: 104,
                  child: Transform.rotate(
                    angle: coachPoint == null
                        ? fallbackCoachHeading
                        : coachHeading,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        DecoratedBox(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withValues(alpha: .92),
                            boxShadow: const [
                              BoxShadow(
                                  color: Colors.black26,
                                  blurRadius: 10,
                                  offset: Offset(0, 4)),
                            ],
                          ),
                          child: const SizedBox(width: 46, height: 46),
                        ),
                        Image.asset(
                          'assets/navigation/coach-marker.png',
                          fit: BoxFit.contain,
                          filterQuality: FilterQuality.high,
                          errorBuilder: (context, error, stackTrace) =>
                              Container(
                            width: 64,
                            height: 64,
                            decoration: BoxDecoration(
                              color: primary,
                              shape: BoxShape.circle,
                              border:
                                  Border.all(color: Colors.white, width: 4),
                              boxShadow: const [
                                BoxShadow(
                                    color: Colors.black26,
                                    blurRadius: 10,
                                    offset: Offset(0, 4)),
                              ],
                            ),
                            child: const Icon(Icons.directions_bus_filled,
                                color: Colors.white, size: 34),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
        Positioned(
          left: 10,
          top: 10,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .94),
              borderRadius: BorderRadius.circular(6),
              boxShadow: const [
                BoxShadow(color: Colors.black12, blurRadius: 8),
              ],
            ),
            child: Text(
              simulationActive ? 'Simulation GPS' : 'Position conducteur',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: simulationActive ? Colors.orange.shade900 : primary,
              ),
            ),
          ),
        ),
        Positioned(
          right: 12,
          top: 12,
          child: Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .95),
              shape: BoxShape.circle,
              boxShadow: const [
                BoxShadow(
                    color: Colors.black26,
                    blurRadius: 10,
                    offset: Offset(0, 4)),
              ],
            ),
            child: Icon(instructionIcon, size: 38, color: primary),
          ),
        ),
        Positioned(
          left: 10,
          bottom: 8,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .92),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Text(
              '© OpenStreetMap',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
            ),
          ),
        ),
      ]),
    );
  }
}

class _NavigationCommandCard extends StatelessWidget {
  const _NavigationCommandCard({
    required this.instruction,
    required this.distanceMeters,
    required this.onSpeak,
  });

  final String instruction;
  final int? distanceMeters;
  final VoidCallback onSpeak;

  IconData get icon {
    final lower = instruction.toLowerCase();
    if (lower.contains('droite')) return Icons.turn_right;
    if (lower.contains('gauche')) return Icons.turn_left;
    if (lower.contains('rond-point') || lower.contains('rond point')) {
      return Icons.roundabout_right;
    }
    if (lower.contains('demi-tour')) return Icons.u_turn_left;
    return Icons.straight;
  }

  @override
  Widget build(BuildContext context) {
    final label = distanceMeters == null
        ? 'Maintenant'
        : distanceMeters! < 1000
            ? 'Dans $distanceMeters m'
            : 'Dans ${(distanceMeters! / 1000).toStringAsFixed(1)} km';
    return Card(
      color: Theme.of(context).colorScheme.primary,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(children: [
          Container(
            width: 62,
            height: 62,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.onPrimary,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon,
                size: 42, color: Theme.of(context).colorScheme.primary),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onPrimary,
                        fontWeight: FontWeight.w900)),
                const SizedBox(height: 4),
                Text(instruction,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onPrimary)),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Repeter',
            onPressed: onSpeak,
            icon: Icon(Icons.volume_up,
                color: Theme.of(context).colorScheme.onPrimary),
          ),
        ]),
      ),
    );
  }
}

class _RoutePainter extends CustomPainter {
  const _RoutePainter({
    required this.stopCount,
    required this.currentIndex,
    required this.tracking,
    required this.primary,
    required this.instruction,
  });

  final int stopCount;
  final int currentIndex;
  final bool tracking;
  final Color primary;
  final String instruction;

  @override
  void paint(Canvas canvas, Size size) {
    final background = Paint()..color = const Color(0xFFE7F0EF);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(10)),
      background,
    );

    final localRoad = Paint()
      ..color = Colors.white.withValues(alpha: .78)
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round;
    for (var index = 0; index < 5; index++) {
      final y = 26.0 + index * 34;
      canvas.drawLine(
          Offset(-20, y), Offset(size.width + 20, y - 64), localRoad);
      canvas.drawLine(Offset(-18, size.height - y),
          Offset(size.width + 18, size.height - y + 48), localRoad);
    }

    final road = Paint()
      ..color = const Color(0xFFFFFFFF)
      ..strokeWidth = 24
      ..strokeCap = StrokeCap.round;
    final progress = Paint()
      ..color = primary
      ..strokeWidth = 10
      ..strokeCap = StrokeCap.round;
    final path = Path()
      ..moveTo(24, size.height - 28)
      ..cubicTo(size.width * .28, size.height * .55, size.width * .34,
          size.height * .17, size.width * .58, size.height * .35)
      ..cubicTo(size.width * .75, size.height * .48, size.width * .72,
          size.height * .16, size.width - 24, 30);
    canvas.drawPath(path, road);
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xFFB7C8CC)
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke,
    );
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
    final metric = path.computeMetrics().first;
    final busOffset = stopCount <= 1
        ? .38
        : (currentIndex / math.max(1, stopCount - 1)).clamp(.08, .92);
    final tangent = metric.getTangentForOffset(metric.length * busOffset);
    if (tangent != null) {
      final point = tangent.position;
      final angle = tangent.angle;
      _drawCoach(canvas, point, angle, primary);
    }

    final lower = instruction.toLowerCase();
    final arrowIcon = lower.contains('droite')
        ? Icons.turn_right
        : lower.contains('gauche')
            ? Icons.turn_left
            : lower.contains('rond')
                ? Icons.roundabout_right
                : Icons.straight;
    final textPainter = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(arrowIcon.codePoint),
        style: TextStyle(
          fontFamily: arrowIcon.fontFamily,
          package: arrowIcon.fontPackage,
          fontSize: 34,
          color: primary,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final arrowCenter = Offset(size.width - 52, 24);
    canvas.drawCircle(
      arrowCenter + const Offset(17, 17),
      24,
      Paint()..color = Colors.white.withValues(alpha: .92),
    );
    textPainter.paint(canvas, arrowCenter);
  }

  void _drawCoach(Canvas canvas, Offset center, double angle, Color primary) {
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(angle);
    final shadow = Paint()..color = Colors.black.withValues(alpha: .22);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          const Rect.fromLTWH(-35, 15, 70, 12), const Radius.circular(8)),
      shadow,
    );
    final body = RRect.fromRectAndRadius(
        const Rect.fromLTWH(-42, -18, 84, 36), const Radius.circular(9));
    canvas.drawRRect(body, Paint()..color = Colors.white);
    canvas.drawRRect(
      body,
      Paint()
        ..color = primary
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          const Rect.fromLTWH(-32, -11, 48, 12), const Radius.circular(4)),
      Paint()..color = const Color(0xFF18343A),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          const Rect.fromLTWH(18, -11, 16, 12), const Radius.circular(4)),
      Paint()..color = const Color(0xFF18343A),
    );
    canvas.drawRect(
      const Rect.fromLTWH(-39, 3, 78, 6),
      Paint()..color = primary.withValues(alpha: .18),
    );
    canvas.drawCircle(
        const Offset(-24, 19), 6, Paint()..color = const Color(0xFF17262A));
    canvas.drawCircle(
        const Offset(25, 19), 6, Paint()..color = const Color(0xFF17262A));
    canvas.restore();
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
      primary != oldDelegate.primary ||
      instruction != oldDelegate.instruction;
}
