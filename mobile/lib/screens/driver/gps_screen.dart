import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/nomad_route.dart';
import '../../services/api_service.dart';
import '../../services/app_state.dart';

class GpsScreen extends StatefulWidget {
  const GpsScreen({super.key});
  @override
  State<GpsScreen> createState() => _GpsScreenState();
}

class _GpsScreenState extends State<GpsScreen> {
  StreamSubscription<Position>? sub;
  Position? last;
  NomadRoute? fullRoute;
  String status = 'GPS inactif';
  String? routeError;
  int sentCount = 0;
  int currentStop = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => loadFullRoute());
  }

  Future<void> loadFullRoute() async {
    final route = context.read<AppState>().selectedDriverRoute;
    if (route == null) return;
    try {
      final data = await context.read<ApiService>().getNomadRoute(route.id);
      if (!mounted) return;
      setState(() {
        fullRoute = NomadRoute.fromJson(data);
        routeError = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        fullRoute = route;
        routeError =
            'Circuit complet indisponible, affichage de l apercu local.';
      });
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

  Future<void> startTrackingOnly() async {
    final route = context.read<AppState>().selectedDriverRoute;
    if (route == null) return;
    if (!await ensureLocationReady()) return;

    await sub?.cancel();
    setState(() => status = 'Suivi GPS actif');
    sub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best, distanceFilter: 10),
    ).listen((position) async {
      if (!mounted) return;
      setState(() => last = position);
      try {
        await context.read<ApiService>().sendGps(
              route.id,
              position.latitude,
              position.longitude,
              position.speed,
              routeName: '${route.shortName} - ${route.longName}',
            );
        if (!mounted) return;
        setState(() {
          sentCount++;
          status = 'Position envoyee au serveur';
        });
      } catch (_) {
        if (mounted) {
          setState(() => status =
              'Position gardee sur le telephone, serveur indisponible');
        }
      }
    });
  }

  Future<void> openGoogleMapsGuidance() async {
    final route = fullRoute ?? context.read<AppState>().selectedDriverRoute;
    if (route == null) return;
    if (sub == null) await startTrackingOnly();

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
    await launchExternal(uri, 'Google Maps ouvert en secours voiture.');
  }

  Future<void> openWazeGuidance() async {
    final route = fullRoute ?? context.read<AppState>().selectedDriverRoute;
    if (route == null) return;
    if (sub == null) await startTrackingOnly();

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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selectedRoute = context.watch<AppState>().selectedDriverRoute;
    final route = fullRoute ?? selectedRoute;
    final stops = route?.stopsPreview ?? [];
    final guidance = route?.coachGuidance;
    final vehicle = guidance?.vehicleProfile;
    final tracking = sub != null;
    return Scaffold(
      appBar: AppBar(title: const Text('Suivi GPS')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.route_outlined),
              title: Text(route == null
                  ? 'Aucune ligne active'
                  : '${route.shortName} - ${route.longName}'),
              subtitle: Text(route == null
                  ? 'Choisissez une ligne avant le depart.'
                  : '${stops.length} arrets charges - mode car scolaire'),
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
          FilledButton.icon(
            onPressed: route == null || tracking ? null : startTrackingOnly,
            icon: const Icon(Icons.directions_bus_filled_outlined),
            label: const Text('Demarrer suivi car scolaire'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: route == null ? null : openGoogleMapsGuidance,
            icon: const Icon(Icons.navigation_outlined),
            label: const Text('Google Maps secours voiture'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: route == null ? null : openWazeGuidance,
            icon: const Icon(Icons.assistant_direction_outlined),
            label: const Text('Waze secours destination'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: tracking ? stop : null,
            icon: const Icon(Icons.stop_circle_outlined),
            label: const Text('Arreter le suivi'),
          ),
          const SizedBox(height: 16),
          Card(
            child: ListTile(
              leading: Icon(tracking
                  ? Icons.satellite_alt_outlined
                  : Icons.gps_not_fixed),
              title: Text(status),
              subtitle: Text(last == null
                  ? 'Position en attente'
                  : 'Lat ${last!.latitude.toStringAsFixed(6)}, Lon ${last!.longitude.toStringAsFixed(6)} - envois $sentCount'),
            ),
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
                      : 'Google Maps et Waze restent des trajets voiture, a utiliser seulement en secours.'),
                  if ((guidance?.rules ?? []).isNotEmpty) ...[
                    const SizedBox(height: 10),
                    ...guidance!.rules.take(4).map(
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
          Text('Parcours de reference',
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
            Card(
              child: ListTile(
                leading: CircleAvatar(
                    child: Text(stops[currentStop].sequence.toString())),
                title: const Text('Prochain arret officiel'),
                subtitle: Text(stops[currentStop].name),
                trailing: FilledButton(
                  onPressed: currentStop >= stops.length - 1
                      ? null
                      : () => setState(() => currentStop++),
                  child: const Text('Suivant'),
                ),
              ),
            ),
          if (stops.isNotEmpty)
            ...stops.map((stop) => Card(
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: stops.indexOf(stop) == currentStop
                          ? Theme.of(context).colorScheme.primary
                          : null,
                      foregroundColor: stops.indexOf(stop) == currentStop
                          ? Theme.of(context).colorScheme.onPrimary
                          : null,
                      child: Text(stop.sequence.toString()),
                    ),
                    title: Text(stop.name),
                    subtitle: stop.arrivalTime.isEmpty
                        ? null
                        : Text(stop.arrivalTime),
                    trailing: stops.indexOf(stop) == currentStop
                        ? const Icon(Icons.directions_bus_outlined)
                        : null,
                    onTap: () =>
                        setState(() => currentStop = stops.indexOf(stop)),
                  ),
                )),
        ],
      ),
    );
  }
}
