import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/nomad_route.dart';
import '../../services/api_service.dart';
import '../../services/app_state.dart';
import '../../services/notification_service.dart';
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
  List<dynamic> alerts = [];
  bool notificationsEnabled = true;
  bool premiumEnabled = false;
  bool loading = true;
  bool searching = false;
  String? error;
  int requestId = 0;
  Timer? alertTimer;
  final seenAlertIds = <String>{};

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
  }

  @override
  void dispose() {
    alertTimer?.cancel();
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
      if (!mounted) return;
      setState(() {
        notificationsEnabled =
            settings['notificationsEnabled'] as bool? ?? true;
        premiumEnabled = settings['premiumEnabled'] as bool? ?? false;
        favorites = favoriteData.cast<Map<String, dynamic>>();
        alerts = alertData;
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

  Future<void> pollFavoriteAlerts() async {
    if (!mounted || !notificationsEnabled) return;
    try {
      final alertData = await context.read<ApiService>().getPassengerAlerts();
      if (!mounted) return;

      final newAlerts = <Map<String, dynamic>>[];
      for (final item in alertData) {
        final alert = item as Map<String, dynamic>;
        final id = (alert['id'] ?? '').toString();
        if (id.isEmpty || seenAlertIds.contains(id)) continue;
        seenAlertIds.add(id);
        newAlerts.add(alert);
      }

      setState(() => alerts = alertData);
      for (final alert in newAlerts.reversed) {
        final critical = alert['severity'] == 'critical' ||
            alert['broadcastToAll'] == true;
        final title = critical
            ? 'Alerte securite transport'
            : alert['routeName'] as String? ?? 'Alerte bus scolaire';
        final body = alert['message'] as String? ??
            (critical
                ? 'Alerte prioritaire transport scolaire.'
                : 'Nouvelle alerte sur une ligne favorite.');
        final id = int.tryParse((alert['id'] ?? '').toString());
        if (critical) {
          await NotificationService.instance
              .showCriticalSafetyAlert(title: title, body: body, id: id);
        } else {
          await NotificationService.instance
              .showBusAlert(title: title, body: body, id: id);
        }
      }
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

  Future<void> presence(BuildContext context, bool present) async {
    await context.read<ApiService>().sendPresence(
        '20000000-0000-0000-0000-000000000001',
        '30000000-0000-0000-0000-000000000002',
        present);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content:
            Text(present ? 'Presence enregistree.' : 'Absence enregistree.')));
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
                ...favorites.map((favorite) => Card(
                      child: ListTile(
                        leading: const Icon(Icons.star, color: Colors.orange),
                        title: Text(favorite['routeName'] as String? ??
                            'Ligne favorite'),
                        subtitle:
                            Text(favorite['routeShortName'] as String? ?? ''),
                        trailing: IconButton(
                          tooltip: 'Retirer des favoris',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () async {
                            await context
                                .read<ApiService>()
                                .removePassengerFavorite(
                                    favorite['routeExternalId'] as String);
                            await loadInitial();
                          },
                        ),
                      ),
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
              FilledButton.icon(
                  onPressed: () => presence(context, true),
                  icon: const Icon(Icons.check_circle_outline),
                  label: const Text('Present a l\'arret')),
              OutlinedButton.icon(
                  onPressed: () => presence(context, false),
                  icon: const Icon(Icons.cancel_outlined),
                  label: const Text('Absent aujourd\'hui')),
            ],
          ),
        ),
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
                    label: premiumEnabled ? 'GPS bus actif' : 'GPS bus premium'),
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
