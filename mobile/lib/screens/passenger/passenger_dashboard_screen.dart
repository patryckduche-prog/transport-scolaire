import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' show LatLng;
import 'package:provider/provider.dart';

import '../../models/nomad_route.dart';
import '../../services/api_service.dart';
import '../../services/app_state.dart';
import '../../widgets/root_back_guard.dart';
import '../login_screen.dart';

class PassengerDashboardScreen extends StatefulWidget {
  const PassengerDashboardScreen({super.key});

  @override
  State<PassengerDashboardScreen> createState() =>
      _PassengerDashboardScreenState();
}

class _PassengerDashboardScreenState extends State<PassengerDashboardScreen> {
  final search = TextEditingController();
  List<NomadRoute> routes = [];
  List<Map<String, dynamic>> favorites = [];
  Map<String, NomadRoute> favoriteDetails = {};
  List<dynamic> alerts = [];
  List<dynamic> absences = [];
  List<dynamic> livePositions = [];
  bool notificationsEnabled = true;
  bool premiumEnabled = false;
  bool loading = true;
  bool searching = false;
  String? error;
  int requestId = 0;
  Timer? alertTimer;
  Timer? liveTimer;
  final seenAlertIds = <String>{};

  List<dynamic> dedupeAlerts(List<dynamic> rawAlerts) {
    final keys = <String>{};
    final unique = <dynamic>[];
    for (final item in rawAlerts) {
      final alert = item as Map<String, dynamic>;
      final key = [
        alert['routeExternalId'] ?? '',
        alert['status'] ?? '',
        alert['reason'] ?? '',
        alert['severity'] ?? '',
        alert['broadcastToAll'] ?? '',
      ].join('|');
      if (keys.add(key)) unique.add(alert);
    }
    return unique;
  }

  void returnToLogin() {
    context.read<AppState>().logout();
    context.read<ApiService>().clearToken();
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }

  @override
  void initState() {
    super.initState();
    loadInitial();
    alertTimer = Timer.periodic(
        const Duration(seconds: 30), (_) => pollFavoriteAlerts());
    liveTimer =
        Timer.periodic(const Duration(seconds: 12), (_) => pollLivePositions());
  }

  @override
  void dispose() {
    alertTimer?.cancel();
    liveTimer?.cancel();
    search.dispose();
    super.dispose();
  }

  Future<void> loadInitial() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final api = context.read<ApiService>();
      final settings = await api.getPassengerSettings();
      final favoriteData = await api.getPassengerFavorites();
      final alertData = await api.getPassengerAlerts();
      final absenceData = await api.getPassengerAbsences();
      final liveData = await api.getPassengerLivePositions();
      final details = <String, NomadRoute>{};
      for (final item in favoriteData) {
        final favorite = item as Map<String, dynamic>;
        final routeId = favorite['routeExternalId'] as String?;
        if (routeId == null) continue;
        try {
          details[routeId] =
              NomadRoute.fromJson(await api.getNomadRoute(routeId));
        } catch (_) {}
      }
      if (!mounted) return;
      setState(() {
        notificationsEnabled =
            settings['notificationsEnabled'] as bool? ?? true;
        premiumEnabled = settings['premiumEnabled'] as bool? ?? false;
        favorites = favoriteData.cast<Map<String, dynamic>>();
        favoriteDetails = details;
        alerts = dedupeAlerts(alertData);
        absences = absenceData;
        livePositions = (liveData['positions'] as List?) ?? [];
        seenAlertIds.addAll(alertData
            .map((item) =>
                ((item as Map<String, dynamic>)['id'] ?? '').toString())
            .where((id) => id.isNotEmpty));
        loading = false;
      });
      await searchRoutes();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        error = 'Informations indisponibles. Verifiez le serveur.';
        loading = false;
      });
    }
  }

  Future<void> pollLivePositions() async {
    if (!mounted || !premiumEnabled) return;
    try {
      final liveData =
          await context.read<ApiService>().getPassengerLivePositions();
      if (!mounted) return;
      setState(() {
        premiumEnabled = liveData['premium'] as bool? ?? premiumEnabled;
        livePositions = (liveData['positions'] as List?) ?? [];
      });
    } catch (_) {}
  }

  Future<void> pollFavoriteAlerts() async {
    if (!mounted || !notificationsEnabled) return;
    try {
      final alertData = await context.read<ApiService>().getPassengerAlerts();
      if (!mounted) return;

      for (final item in alertData) {
        final alert = item as Map<String, dynamic>;
        final id = (alert['id'] ?? '').toString();
        if (id.isEmpty || seenAlertIds.contains(id)) continue;
        seenAlertIds.add(id);
      }

      setState(() => alerts = dedupeAlerts(alertData));
    } catch (_) {}
  }

  Future<void> searchRoutes() async {
    final currentRequest = ++requestId;
    setState(() => searching = true);
    try {
      final data = await context
          .read<ApiService>()
          .getNomadRoutes(query: search.text.trim(), highlighted: false);
      if (!mounted || currentRequest != requestId) return;
      setState(() {
        routes = ((data['routes'] as List?) ?? [])
            .map((item) => NomadRoute.fromJson(item))
            .take(40)
            .toList();
        searching = false;
      });
    } catch (_) {
      if (!mounted || currentRequest != requestId) return;
      setState(() => searching = false);
    }
  }

  bool isFavorite(String routeId) =>
      favorites.any((item) => item['routeExternalId'] == routeId);

  Future<void> toggleFavorite(NomadRoute route) async {
    final api = context.read<ApiService>();
    if (isFavorite(route.id)) {
      await api.removePassengerFavorite(route.id);
    } else {
      await api.addPassengerFavorite(
          routeExternalId: route.id,
          routeName: route.longName,
          routeShortName: route.shortName);
    }
    await loadInitial();
  }

  Future<void> toggleNotifications(bool enabled) async {
    setState(() => notificationsEnabled = enabled);
    await context.read<ApiService>().updatePassengerSettings(enabled);
    if (enabled) await pollFavoriteAlerts();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(enabled
              ? 'Notifications activees.'
              : 'Notifications desactivees.')),
    );
  }

  Future<void> togglePremiumTest(bool enabled) async {
    setState(() => premiumEnabled = enabled);
    final settings = await context.read<ApiService>().updatePassengerSettings(
          notificationsEnabled,
          premiumTestEnabled: enabled,
        );
    if (!mounted) return;
    setState(
        () => premiumEnabled = settings['premiumEnabled'] as bool? ?? enabled);
    await pollLivePositions();
  }

  Future<void> reportAbsence(Map<String, dynamic> favorite, bool absent) async {
    final routeId = favorite['routeExternalId'] as String;
    final routeName = favorite['routeName'] as String? ?? 'Ligne favorite';
    final api = context.read<ApiService>();
    await api.sendPassengerAbsence(
      routeExternalId: routeId,
      routeName: routeName,
      absent: absent,
    );
    final absenceData = await api.getPassengerAbsences();
    if (!mounted) return;
    setState(() => absences = absenceData);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(absent
          ? 'Absence enregistree sur $routeName.'
          : 'Absence annulee sur $routeName.'),
    ));
  }

  bool isAbsentToday(String routeId) => absences.any((item) {
        final absence = item as Map<String, dynamic>;
        return absence['routeExternalId'] == routeId &&
            absence['absent'] == true;
      });

  Map<String, dynamic>? liveForRoute(String routeId) {
    for (final item in livePositions) {
      final position = item as Map<String, dynamic>;
      if (position['routeExternalId'] == routeId) return position;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return RootBackGuard(
      message: 'Vous etes sur l accueil Parent / Eleve.',
      onBack: returnToLogin,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Parent / Eleve'),
          actions: [
            IconButton(
              tooltip: 'Retour accueil',
              icon: const Icon(Icons.logout_outlined),
              onPressed: returnToLogin,
            ),
          ],
        ),
        body: RefreshIndicator(
          onRefresh: loadInitial,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Notifications'),
                subtitle: const Text(
                    'Favoris uniquement, sauf alerte securite prioritaire'),
                value: notificationsEnabled,
                onChanged: toggleNotifications,
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Premium test'),
                subtitle: const Text(
                    'Mode developpeur sans paiement, pour valider le suivi GPS parent'),
                value: premiumEnabled,
                onChanged: togglePremiumTest,
              ),
              _PassengerPlanCard(premiumEnabled: premiumEnabled),
              const SizedBox(height: 8),
              TextField(
                controller: search,
                decoration: InputDecoration(
                  labelText: 'Chercher une ligne',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: searching
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : null,
                ),
                onChanged: (_) => searchRoutes(),
                onSubmitted: (_) => searchRoutes(),
              ),
              if (error != null)
                Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(error!,
                        style: const TextStyle(color: Colors.red))),
              const SizedBox(height: 16),
              Text('Mes lignes favorites',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              if (loading)
                const LinearProgressIndicator()
              else if (favorites.isEmpty)
                const Card(
                    child: ListTile(
                        leading: Icon(Icons.star_outline),
                        title: Text('Aucune ligne favorite'),
                        subtitle: Text(
                            'Cherchez une ligne puis ajoutez-la en favori.')))
              else
                ...favorites.map((favorite) {
                  final routeId = favorite['routeExternalId'] as String;
                  final detail = favoriteDetails[routeId];
                  final absentToday = isAbsentToday(routeId);
                  final live = liveForRoute(routeId);
                  return _FavoriteRouteCard(
                    favorite: favorite,
                    detail: detail,
                    premiumEnabled: premiumEnabled,
                    livePosition: live,
                    absentToday: absentToday,
                    onRemove: () async {
                      await context
                          .read<ApiService>()
                          .removePassengerFavorite(routeId);
                      await loadInitial();
                    },
                    onAbsence: () => reportAbsence(favorite, !absentToday),
                  );
                }),
              const SizedBox(height: 16),
              Text('Suivi GPS parent',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              if (!premiumEnabled)
                const Card(
                  child: ListTile(
                    leading: Icon(Icons.lock_outline),
                    title: Text('Suivi GPS du car disponible avec Premium'),
                    subtitle: Text(
                        'En gratuit, vous gardez les horaires, favoris, absences et alertes importantes.'),
                  ),
                )
              else if (favorites.isEmpty)
                const Card(
                  child: ListTile(
                    leading: Icon(Icons.star_outline),
                    title: Text('Ajoutez une ligne favorite'),
                    subtitle: Text(
                        'Le GPS Premium ne s affiche que sur vos circuits favoris.'),
                  ),
                )
              else if (livePositions.isEmpty)
                const Card(
                  child: ListTile(
                    leading: Icon(Icons.gps_not_fixed),
                    title: Text('Aucune tournee active detectee'),
                    subtitle: Text(
                        'Le car apparaitra quand un conducteur lancera le suivi sur une ligne favorite.'),
                  ),
                )
              else
                ...livePositions.map((item) => _PremiumLiveCard(
                      position: item as Map<String, dynamic>,
                    )),
              const SizedBox(height: 16),
              Text('Alertes sur mes favoris',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              if (alerts.isEmpty)
                const Card(
                    child: ListTile(
                        leading: Icon(Icons.notifications_none),
                        title: Text('Aucune alerte sur vos lignes favorites')))
              else
                ...alerts.take(5).map((item) {
                  final alert = item as Map<String, dynamic>;
                  return Card(
                    child: ListTile(
                      leading: Icon(Icons.notification_important_outlined,
                          color: alert['severity'] == 'critical'
                              ? Colors.red.shade800
                              : Colors.orange.shade800),
                      title: Text(alert['broadcastToAll'] == true
                          ? 'Alerte securite prioritaire'
                          : alert['routeName'] as String? ?? 'Ligne favorite'),
                      subtitle: Text(alert['message'] as String? ?? ''),
                    ),
                  );
                }),
              const SizedBox(height: 16),
              Text('Resultats de recherche',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              ...routes.map((route) => Card(
                    child: ExpansionTile(
                      leading: CircleAvatar(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Padding(
                            padding: const EdgeInsets.all(3),
                            child: Text(route.shortName,
                                textAlign: TextAlign.center),
                          ),
                        ),
                      ),
                      title: Text(route.longName),
                      subtitle: Text('${route.stopCount} arrets'),
                      trailing: IconButton(
                        tooltip: isFavorite(route.id)
                            ? 'Retirer des favoris'
                            : 'Ajouter aux favoris',
                        icon: Icon(
                            isFavorite(route.id)
                                ? Icons.star
                                : Icons.star_outline,
                            color: isFavorite(route.id) ? Colors.orange : null),
                        onPressed: () => toggleFavorite(route),
                      ),
                      children: route.stopsPreview
                          .map((stop) => ListTile(
                                dense: true,
                                leading: Text(stop.sequence.toString()),
                                title: Text(stop.name),
                              ))
                          .toList(),
                    ),
                  )),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}

class _FavoriteRouteCard extends StatelessWidget {
  const _FavoriteRouteCard({
    required this.favorite,
    required this.detail,
    required this.premiumEnabled,
    required this.livePosition,
    required this.absentToday,
    required this.onRemove,
    required this.onAbsence,
  });

  final Map<String, dynamic> favorite;
  final NomadRoute? detail;
  final bool premiumEnabled;
  final Map<String, dynamic>? livePosition;
  final bool absentToday;
  final VoidCallback onRemove;
  final VoidCallback onAbsence;

  @override
  Widget build(BuildContext context) {
    final routeName = favorite['routeName'] as String? ?? 'Ligne favorite';
    final shortName = favorite['routeShortName'] as String? ?? '';
    final stops = detail?.stopsPreview ?? const <NomadStop>[];
    final nextTimes = stops
        .where((stop) => stop.arrivalTime.isNotEmpty)
        .take(4)
        .map((stop) => '${stop.arrivalTime} ${stop.name}')
        .join('\n');
    return Card(
      child: ExpansionTile(
        leading: const Icon(Icons.star, color: Colors.orange),
        title: Text(routeName),
        subtitle: Text([
          if (shortName.isNotEmpty) shortName,
          if (absentToday) 'Absent aujourd hui',
          if (premiumEnabled && livePosition != null) 'Car en approche',
          if (!premiumEnabled) 'GPS Premium masque',
        ].join(' - ')),
        trailing: IconButton(
          tooltip: 'Retirer des favoris',
          icon: const Icon(Icons.delete_outline),
          onPressed: onRemove,
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.schedule_outlined),
            title: const Text('Horaires'),
            subtitle: Text(nextTimes.isEmpty
                ? 'Horaires detailles en cours de chargement.'
                : nextTimes),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(absentToday
                ? Icons.cancel_outlined
                : Icons.check_circle_outline),
            title: Text(absentToday
                ? 'Absence enfant declaree aujourd hui'
                : 'Absence enfant'),
            subtitle: const Text(
                'Declaration sans nom d eleve, rattachee a cette ligne favorite.'),
            trailing: OutlinedButton(
              onPressed: onAbsence,
              child: Text(absentToday ? 'Annuler' : 'Absent'),
            ),
          ),
          if (!premiumEnabled)
            const ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.lock_outline),
              title: Text('Suivi GPS du car disponible avec Premium'),
            ),
        ],
      ),
    );
  }
}

class _PremiumLiveCard extends StatelessWidget {
  const _PremiumLiveCard({required this.position});

  final Map<String, dynamic> position;

  @override
  Widget build(BuildContext context) {
    final latitude = (position['latitude'] as num?)?.toDouble();
    final longitude = (position['longitude'] as num?)?.toDouble();
    final speed = ((position['speed'] as num?)?.toDouble() ?? 0) * 3.6;
    final routeName = position['routeName'] as String? ?? 'Ligne favorite';
    final recordedAt = position['recordedAt']?.toString() ?? '';
    final eta = position['etaMinutes'] as int?;
    if (latitude == null || longitude == null) {
      return const SizedBox.shrink();
    }
    final point = LatLng(latitude, longitude);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.workspace_premium_outlined,
                color: Colors.green.shade700),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                routeName,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
          ]),
          const SizedBox(height: 8),
          Text(eta == null
              ? 'Derniere position recue - vitesse ${speed.round()} km/h'
              : 'Car en approche - ETA estimee $eta min - vitesse ${speed.round()} km/h'),
          const SizedBox(height: 10),
          SizedBox(
            height: 220,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: FlutterMap(
                options: MapOptions(
                  initialCenter: point,
                  initialZoom: 15.8,
                  interactionOptions: const InteractionOptions(
                    flags: InteractiveFlag.drag |
                        InteractiveFlag.pinchZoom |
                        InteractiveFlag.doubleTapZoom,
                  ),
                ),
                children: [
                  TileLayer(
                    urlTemplate:
                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'fr.busscolaireconnect.mobile',
                  ),
                  MarkerLayer(markers: [
                    Marker(
                      point: point,
                      width: 86,
                      height: 64,
                      child: Image.asset(
                        'assets/navigation/coach-marker.png',
                        fit: BoxFit.contain,
                        errorBuilder: (context, error, stackTrace) =>
                            DecoratedBox(
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primary,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.directions_bus_filled,
                              color: Colors.white),
                        ),
                      ),
                    ),
                  ]),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Derniere position : ${latitude.toStringAsFixed(6)}, ${longitude.toStringAsFixed(6)}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (recordedAt.isNotEmpty)
            Text('Recu : $recordedAt',
                style: Theme.of(context).textTheme.bodySmall),
        ]),
      ),
    );
  }
}

class _PassengerPlanCard extends StatelessWidget {
  const _PassengerPlanCard({required this.premiumEnabled});

  final bool premiumEnabled;

  @override
  Widget build(BuildContext context) {
    final color = premiumEnabled ? Colors.green.shade700 : Colors.teal.shade700;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  premiumEnabled
                      ? Icons.workspace_premium_outlined
                      : Icons.lock_open_outlined,
                  color: color,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    premiumEnabled
                        ? 'Premium famille actif'
                        : 'Gratuit aujourd hui',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              premiumEnabled
                  ? 'Position du bus, estimation d arrivee et alertes avancees sur vos lignes favorites.'
                  : 'Favoris, retards, absences et alertes securite prioritaires restent accessibles gratuitement.',
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _PlanChip(icon: Icons.star_outline, label: 'Favoris inclus'),
                _PlanChip(
                    icon: Icons.warning_amber_outlined,
                    label: 'Securite gratuite'),
                _PlanChip(
                    icon: Icons.location_on_outlined,
                    label:
                        premiumEnabled ? 'GPS bus actif' : 'GPS bus premium'),
              ],
            ),
            if (!premiumEnabled) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                        'Abonnement premium a connecter plus tard via Play Store / App Store.'),
                  ),
                ),
                icon: const Icon(Icons.workspace_premium_outlined),
                label: const Text('Voir Premium famille'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PlanChip extends StatelessWidget {
  const _PlanChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: Icon(icon, size: 16),
      label: Text(label),
      visualDensity: VisualDensity.compact,
    );
  }
}
