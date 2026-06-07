import 'package:dio/dio.dart';

class ApiService {
  ApiService()
      : _dio = Dio(BaseOptions(
          baseUrl: const String.fromEnvironment('API_URL',
              defaultValue: 'http://10.0.2.2:3000/api'),
          connectTimeout: const Duration(seconds: 8),
          receiveTimeout: const Duration(seconds: 8),
        ));

  final Dio _dio;

  void setToken(String token) =>
      _dio.options.headers['Authorization'] = 'Bearer $token';
  void clearToken() => _dio.options.headers.remove('Authorization');

  Future<void> registerFcmToken(String fcmToken) async =>
      _dio.post('/auth/fcm-token', data: {'fcmToken': fcmToken});

  Future<Map<String, dynamic>> login(String email, String password) async =>
      (await _dio.post('/auth/login',
              data: {'email': email, 'password': password}))
          .data as Map<String, dynamic>;

  Future<Map<String, dynamic>> loginWithDriverCode(String code) async =>
      (await _dio.post('/auth/driver-code', data: {'code': code})).data
          as Map<String, dynamic>;

  Future<Map<String, dynamic>> startPassengerAccess(String deviceId) async =>
      (await _dio.post('/auth/guest/passenger', data: {'deviceId': deviceId}))
          .data as Map<String, dynamic>;

  Future<List<dynamic>> getRoutes() async =>
      (await _dio.get('/routes')).data as List<dynamic>;

  Future<Map<String, dynamic>> declareDelay(
          String routeId, String status, String reason,
          {String? routeName}) async =>
      (await _dio.post('/delays', data: {
        'routeId': routeId,
        'routeName': routeName,
        'status': status,
        'reason': reason
      }))
          .data as Map<String, dynamic>;

  Future<void> sendPresence(
          String routeId, String stopId, bool present) async =>
      _dio.post('/presence',
          data: {'routeId': routeId, 'stopId': stopId, 'present': present});

  Future<void> sendGps(
          String routeId, double latitude, double longitude, double speed,
          {String? routeName}) async =>
      _dio.post('/gps', data: {
        'routeId': routeId,
        'routeName': routeName,
        'latitude': latitude,
        'longitude': longitude,
        'speed': speed
      });

  Future<Map<String, dynamic>> startRun({
    required String routeId,
    required String routeName,
  }) async =>
      (await _dio.post('/runs/start',
              data: {'routeId': routeId, 'routeName': routeName}))
          .data as Map<String, dynamic>;

  Future<Map<String, dynamic>?> getCurrentRun() async =>
      (await _dio.get('/runs/current')).data as Map<String, dynamic>?;

  Future<List<dynamic>> getRunStudents(String runId) async =>
      (await _dio.get('/runs/$runId/students')).data as List<dynamic>;

  Future<Map<String, dynamic>> sendRunGps({
    required String runId,
    required double latitude,
    required double longitude,
    required double speed,
    String? recordedAt,
  }) async =>
      (await _dio.post('/runs/$runId/gps', data: {
        'latitude': latitude,
        'longitude': longitude,
        'speed': speed,
        if (recordedAt != null) 'recordedAt': recordedAt,
      }))
          .data as Map<String, dynamic>;

  Future<Map<String, dynamic>> updateRunStudentPresence({
    required String runId,
    required String studentId,
    required bool present,
    String? status,
  }) async =>
      (await _dio.post('/runs/$runId/students/$studentId/presence', data: {
        'present': present,
        if (status != null) 'status': status,
      }))
          .data as Map<String, dynamic>;

  Future<Map<String, dynamic>> sendRunIncident({
    required String runId,
    required String type,
    required String message,
    String severity = 'warning',
  }) async =>
      (await _dio.post('/runs/$runId/incidents',
              data: {'type': type, 'message': message, 'severity': severity}))
          .data as Map<String, dynamic>;

  Future<Map<String, dynamic>> sendFinishCheck({
    required String runId,
    required bool allStudentsChecked,
    required bool busEmptyConfirmed,
    String comment = '',
  }) async =>
      (await _dio.post('/runs/$runId/finish-check', data: {
        'allStudentsChecked': allStudentsChecked,
        'busEmptyConfirmed': busEmptyConfirmed,
        'comment': comment,
      }))
          .data as Map<String, dynamic>;

  Future<Map<String, dynamic>> dashboard() async =>
      (await _dio.get('/reports/dashboard')).data as Map<String, dynamic>;

  Future<Map<String, dynamic>> getAppVersion() async =>
      (await _dio.get('/app-version')).data as Map<String, dynamic>;

  Future<List<dynamic>> getPublicAlerts() async =>
      ((await _dio.get('/public/alerts')).data['alerts'] as List<dynamic>);

  Future<Map<String, dynamic>> getNomadRoutes(
      {String query = '', bool highlighted = false}) async {
    final response = await _dio.get('/nomad/routes',
        queryParameters: {'q': query, 'highlighted': highlighted});
    return response.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getNomadRoute(String routeId) async =>
      (await _dio.get('/nomad/routes/$routeId')).data as Map<String, dynamic>;

  Future<Map<String, dynamic>> getCoachNavigation(String routeId) async =>
      (await _dio.get('/navigation/coach-route/$routeId')).data
          as Map<String, dynamic>;

  Future<Map<String, dynamic>> getPassengerSettings() async =>
      (await _dio.get('/passenger/settings')).data as Map<String, dynamic>;

  Future<Map<String, dynamic>> updatePassengerSettings(bool enabled,
          {bool? premiumTestEnabled}) async =>
      (await _dio.put('/passenger/settings', data: {
        'enabled': enabled,
        if (premiumTestEnabled != null)
          'premiumTestEnabled': premiumTestEnabled,
      }))
          .data as Map<String, dynamic>;

  Future<List<dynamic>> getPassengerFavorites() async =>
      (await _dio.get('/passenger/favorites')).data as List<dynamic>;

  Future<Map<String, dynamic>> addPassengerFavorite({
    required String routeExternalId,
    required String routeName,
    required String routeShortName,
  }) async =>
      (await _dio.post('/passenger/favorites', data: {
        'routeExternalId': routeExternalId,
        'routeName': routeName,
        'routeShortName': routeShortName,
      }))
          .data as Map<String, dynamic>;

  Future<void> removePassengerFavorite(String routeExternalId) async =>
      _dio.delete('/passenger/favorites/$routeExternalId');

  Future<List<dynamic>> getPassengerAlerts() async =>
      ((await _dio.get('/passenger/alerts')).data['alerts'] as List<dynamic>);

  Future<List<dynamic>> getPassengerAbsences() async =>
      ((await _dio.get('/passenger/absences')).data['absences']
          as List<dynamic>);

  Future<Map<String, dynamic>> sendPassengerAbsence({
    required String routeExternalId,
    required String routeName,
    required bool absent,
  }) async =>
      (await _dio.post('/passenger/absence', data: {
        'routeExternalId': routeExternalId,
        'routeName': routeName,
        'absent': absent,
      }))
          .data as Map<String, dynamic>;

  Future<Map<String, dynamic>> getPassengerLivePositions() async =>
      (await _dio.get('/passenger/live-positions')).data
          as Map<String, dynamic>;
}
