import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/user.dart';
import '../services/api_service.dart';
import '../services/app_state.dart';
import '../services/notification_service.dart';
import '../services/seasonal_theme.dart';
import 'admin/company_dashboard_screen.dart';
import 'admin/region_dashboard_screen.dart';
import 'driver/driver_dashboard_screen.dart';
import 'passenger/passenger_dashboard_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  static const currentAppVersion =
      String.fromEnvironment('APP_VERSION', defaultValue: '1.0.37');

  final driverCode = TextEditingController(text: 'AUMALE-2026');
  final adminEmail = TextEditingController(text: 'entreprise@demo.local');
  final adminPassword = TextEditingController(text: 'demo1234');
  List<dynamic> alerts = [];
  SeasonalTheme seasonal = SeasonalTheme.fromDate(DateTime.now());
  bool loading = false;
  bool alertsLoading = true;
  String? error;

  Future<String> passengerDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString('passenger_device_id');
    if (existing != null && existing.isNotEmpty) return existing;

    final random = Random.secure();
    final suffix = List<int>.generate(12, (_) => random.nextInt(256))
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
    final next = 'phone-${DateTime.now().microsecondsSinceEpoch}-$suffix';
    await prefs.setString('passenger_device_id', next);
    return next;
  }

  @override
  void initState() {
    super.initState();
    loadAlerts();
    WidgetsBinding.instance.addPostFrameCallback((_) => checkForUpdate());
  }

  bool isNewerVersion(String latest, String current) {
    final latestParts =
        latest.split('.').map((part) => int.tryParse(part) ?? 0).toList();
    final currentParts =
        current.split('.').map((part) => int.tryParse(part) ?? 0).toList();
    final maxLength = latestParts.length > currentParts.length
        ? latestParts.length
        : currentParts.length;
    for (var index = 0; index < maxLength; index++) {
      final latestValue = index < latestParts.length ? latestParts[index] : 0;
      final currentValue =
          index < currentParts.length ? currentParts[index] : 0;
      if (latestValue > currentValue) return true;
      if (latestValue < currentValue) return false;
    }
    return false;
  }

  Future<void> checkForUpdate() async {
    try {
      final version = await context.read<ApiService>().getAppVersion();
      if (!mounted) return;

      final latestVersion = version['latestVersion'] as String? ?? '';
      final apkUrl = version['apkUrl'] as String? ?? '';
      final title =
          version['title'] as String? ?? 'Nouvelle version disponible';
      final message = version['message'] as String? ??
          'Une nouvelle version de Bus Scolaire Connect est disponible.';
      if (latestVersion.isEmpty ||
          apkUrl.isEmpty ||
          !isNewerVersion(latestVersion, currentAppVersion)) {
        return;
      }

      await showDialog<void>(
        context: context,
        barrierDismissible: version['mandatory'] != true,
        builder: (dialogContext) => AlertDialog(
          title: Text(title),
          content: Text(
              '$message\n\nVersion installee : $currentAppVersion\nNouvelle version : $latestVersion'),
          actions: [
            if (version['mandatory'] != true)
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Plus tard'),
              ),
            FilledButton.icon(
              onPressed: () async {
                Navigator.of(dialogContext).pop();
                final uri = Uri.parse(apkUrl);
                final opened =
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                if (!mounted || opened) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text('Impossible d ouvrir le telechargement.')),
                );
              },
              icon: const Icon(Icons.download_outlined),
              label: const Text('Telecharger'),
            ),
          ],
        ),
      );
    } catch (_) {}
  }

  Future<void> loadAlerts() async {
    try {
      final data = await context.read<ApiService>().getPublicAlerts();
      final publicAlerts = data.where((item) {
        final alert = item as Map<String, dynamic>;
        return alert['broadcastToAll'] == true ||
            alert['category'] == 'safety' ||
            alert['severity'] == 'critical';
      }).toList();
      if (!mounted) return;
      setState(() {
        alerts = publicAlerts.isEmpty
            ? [
                {
                  'message': 'Aucune alerte prioritaire generale declaree.',
                  'severity': 'info',
                  'category': 'safety',
                  'broadcastToAll': false,
                }
              ]
            : publicAlerts;
        seasonal = SeasonalTheme.fromDate(DateTime.now(),
            weather: SeasonalTheme.weatherFromAlerts(publicAlerts));
        alertsLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        alerts = [
          {
            'message': 'Alertes indisponibles hors connexion.',
            'severity': 'warning',
          }
        ];
        seasonal =
            SeasonalTheme.fromDate(DateTime.now(), weather: WeatherState.fog);
        alertsLoading = false;
      });
    }
  }

  Future<void> registerNotifications(ApiService api) async {
    final fcmToken = await NotificationService.instance.getFcmToken();
    if (fcmToken == null) return;
    try {
      await api.registerFcmToken(fcmToken);
    } catch (_) {}
  }

  Future<void> openPassengerAccess() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final api = context.read<ApiService>();
      final data = await api.startPassengerAccess(await passengerDeviceId());
      final user = AppUser.fromJson(data['user'] as Map<String, dynamic>);
      final token = data['token'] as String;
      api.setToken(token);
      await registerNotifications(api);
      if (!mounted) return;
      context.read<AppState>().setSession(user, token);
      Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const PassengerDashboardScreen()));
    } catch (_) {
      setState(() =>
          error = 'Acces parent / eleve indisponible. Verifiez le serveur.');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> submitDriverCode() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final api = context.read<ApiService>();
      final data = await api.loginWithDriverCode(driverCode.text.trim());
      final user = AppUser.fromJson(data['user'] as Map<String, dynamic>);
      final token = data['token'] as String;
      api.setToken(token);
      await registerNotifications(api);
      if (!mounted) return;
      context.read<AppState>().setSession(user, token);
      Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const DriverDashboardScreen()));
    } catch (_) {
      setState(
          () => error = 'Code conducteur invalide ou serveur indisponible.');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> submitAdminLogin() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final api = context.read<ApiService>();
      final data = await api.login(adminEmail.text.trim(), adminPassword.text);
      final user = AppUser.fromJson(data['user'] as Map<String, dynamic>);
      final token = data['token'] as String;
      api.setToken(token);
      await registerNotifications(api);
      if (!mounted) return;
      context.read<AppState>().setSession(user, token);
      Navigator.of(context).pop();
      Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => _homeFor(user.role)));
    } catch (_) {
      setState(() => error = 'Acces gestion impossible.');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  void showAdminLogin() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: EdgeInsets.fromLTRB(
            20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Acces entreprise / region',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 14),
            TextField(
                controller: adminEmail,
                decoration: const InputDecoration(
                    labelText: 'Email', prefixIcon: Icon(Icons.mail_outline))),
            const SizedBox(height: 12),
            TextField(
                controller: adminPassword,
                obscureText: true,
                decoration: const InputDecoration(
                    labelText: 'Mot de passe',
                    prefixIcon: Icon(Icons.lock_outline))),
            const SizedBox(height: 18),
            FilledButton.icon(
                onPressed: loading ? null : submitAdminLogin,
                icon: const Icon(Icons.admin_panel_settings_outlined),
                label: const Text('Ouvrir la gestion')),
          ],
        ),
      ),
    );
  }

  Widget _homeFor(UserRole role) => switch (role) {
        UserRole.driver => const DriverDashboardScreen(),
        UserRole.parent || UserRole.student => const PassengerDashboardScreen(),
        UserRole.company => const CompanyDashboardScreen(),
        UserRole.region => const RegionDashboardScreen(),
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: loadAlerts,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              _BusHeader(theme: seasonal),
              const SizedBox(height: 16),
              _AlertsPanel(
                  alerts: alerts, loading: alertsLoading, theme: seasonal),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: loading ? null : openPassengerAccess,
                icon: const Icon(Icons.family_restroom),
                label: const Text('Acces direct parent / eleve'),
              ),
              const SizedBox(height: 18),
              Text('Conducteur',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              TextField(
                controller: driverCode,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                    labelText: 'Code conducteur',
                    prefixIcon: Icon(Icons.pin_outlined)),
              ),
              if (error != null)
                Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(error!,
                        style: const TextStyle(color: Colors.red))),
              const SizedBox(height: 20),
              OutlinedButton.icon(
                onPressed: loading ? null : submitDriverCode,
                icon: const Icon(Icons.directions_bus_filled_outlined),
                label:
                    Text(loading ? 'Ouverture...' : 'Ouvrir espace conducteur'),
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: showAdminLogin,
                icon: const Icon(Icons.manage_accounts_outlined),
                label: const Text('Entreprise / region'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BusHeader extends StatelessWidget {
  const _BusHeader({required this.theme});

  final SeasonalTheme theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 210,
      decoration: BoxDecoration(
        color: theme.primary,
        borderRadius: BorderRadius.circular(8),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(theme.asset, fit: BoxFit.cover),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.black.withValues(alpha: 0.62),
                  Colors.black.withValues(alpha: 0.1)
                ],
              ),
            ),
          ),
          const Positioned(
            left: 20,
            top: 20,
            right: 20,
            child: Text(
              'Bus Scolaire Connect',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 30,
                  fontWeight: FontWeight.w800),
            ),
          ),
          const Positioned(
            left: 22,
            top: 92,
            right: 22,
            child: Text(
              'Suivi des lignes, retards et alertes scolaires',
              style: TextStyle(color: Colors.white, fontSize: 16),
            ),
          ),
          Positioned(
            left: 20,
            bottom: 18,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                  color: theme.primary.withValues(alpha: 0.86),
                  borderRadius: BorderRadius.circular(8)),
              child: Row(
                children: [
                  Icon(theme.alertIcon, color: Colors.white, size: 18),
                  const SizedBox(width: 8),
                  Text(theme.label,
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AlertsPanel extends StatelessWidget {
  const _AlertsPanel(
      {required this.alerts, required this.loading, required this.theme});

  final List<dynamic> alerts;
  final bool loading;
  final SeasonalTheme theme;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.notifications_active_outlined, color: theme.primary),
                const SizedBox(width: 8),
                Text('Alertes en cours',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700)),
              ],
            ),
            const SizedBox(height: 10),
            if (loading)
              const LinearProgressIndicator()
            else
              ...alerts.take(3).map((item) {
                final alert = item as Map<String, dynamic>;
                final critical = alert['severity'] == 'critical' ||
                    alert['broadcastToAll'] == true;
                final warning = critical || alert['severity'] == 'warning';
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                          critical
                              ? Icons.crisis_alert_outlined
                              : warning
                                  ? theme.alertIcon
                                  : Icons.check_circle_outline,
                          size: 20,
                          color: critical
                              ? Colors.red.shade800
                              : warning
                                  ? Colors.orange.shade800
                                  : Colors.green.shade700),
                      const SizedBox(width: 8),
                      Expanded(
                          child: Text(alert['message'] as String? ??
                              'Aucune information disponible.')),
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}
