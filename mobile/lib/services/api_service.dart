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

  Future<Map<String, dynamic>> startPassengerAccess() async =>
      (await _dio.post('/auth/guest/passenger')).data as Map<String, dynamic>;

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

  Future<Map<String, dynamic>> dashboard() async =>
      (await _dio.get('/reports/dashboard')).data as Map<String, dynamic>;

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

  Future<Map<String, dynamic>> getPassengerSettings() async =>
      (await _dio.get('/passenger/settings')).data as Map<String, dynamic>;

  Future<Map<String, dynamic>> updatePassengerSettings(bool enabled) async =>
      (await _dio.put('/passenger/settings', data: {'enabled': enabled})).data
          as Map<String, dynamic>;

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
}
