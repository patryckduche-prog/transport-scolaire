import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';

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
  String status = 'GPS inactif';
  int sentCount = 0;

  Future<void> start() async {
    final route = context.read<AppState>().selectedDriverRoute;
    if (route == null) return;

    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      setState(() => status = 'Activez la localisation du telephone.');
      return;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
      setState(() => status = 'Autorisation GPS refusee.');
      return;
    }

    await sub?.cancel();
    setState(() => status = 'Suivi GPS actif');
    sub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.best, distanceFilter: 10),
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
        if (mounted) setState(() => status = 'Position gardee sur le telephone, serveur indisponible');
      }
    });
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
    final route = context.watch<AppState>().selectedDriverRoute;
    final stops = route?.stopsPreview ?? [];
    final tracking = sub != null;
    return Scaffold(
      appBar: AppBar(title: const Text('Suivi GPS')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.route_outlined),
              title: Text(route == null ? 'Aucune ligne active' : '${route.shortName} - ${route.longName}'),
              subtitle: Text(route == null ? 'Choisissez une ligne avant le depart.' : '${stops.length} arrets dans le parcours'),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: route == null || tracking ? null : start,
            icon: const Icon(Icons.gps_fixed),
            label: const Text('Activer le suivi GPS'),
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
              leading: Icon(tracking ? Icons.satellite_alt_outlined : Icons.gps_not_fixed),
              title: Text(status),
              subtitle: Text(last == null
                  ? 'Position en attente'
                  : 'Lat ${last!.latitude.toStringAsFixed(6)}, Lon ${last!.longitude.toStringAsFixed(6)} - envois $sentCount'),
            ),
          ),
          const SizedBox(height: 12),
          Text('Parcours de reference', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          if (stops.isEmpty)
            const Card(child: ListTile(leading: Icon(Icons.info_outline), title: Text('Aucun arret charge pour cette ligne')))
          else
            ...stops.map((stop) => Card(
                  child: ListTile(
                    leading: CircleAvatar(child: Text(stop.sequence.toString())),
                    title: Text(stop.name),
                    subtitle: stop.arrivalTime.isEmpty ? null : Text(stop.arrivalTime),
                  ),
                )),
        ],
      ),
    );
  }
}
