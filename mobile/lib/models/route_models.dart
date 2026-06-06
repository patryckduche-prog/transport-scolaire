class SchoolRoute {
  const SchoolRoute({required this.id, required this.name, required this.vehicle, required this.stops});
  final String id;
  final String name;
  final String vehicle;
  final List<RouteStop> stops;

  factory SchoolRoute.fromJson(Map<String, dynamic> json) => SchoolRoute(
        id: json['id'].toString(),
        name: json['name'] as String,
        vehicle: json['vehicle'] as String? ?? 'Non affecte',
        stops: ((json['stops'] as List?) ?? []).map((item) => RouteStop.fromJson(item)).toList(),
      );
}

class RouteStop {
  const RouteStop({required this.id, required this.name, required this.scheduledTime, required this.latitude, required this.longitude, this.presentCount = 0, this.absentCount = 0});
  final String id;
  final String name;
  final String scheduledTime;
  final double latitude;
  final double longitude;
  final int presentCount;
  final int absentCount;

  factory RouteStop.fromJson(Map<String, dynamic> json) => RouteStop(
        id: json['id'].toString(),
        name: json['name'] as String,
        scheduledTime: json['scheduledTime'] as String,
        latitude: (json['latitude'] as num).toDouble(),
        longitude: (json['longitude'] as num).toDouble(),
        presentCount: json['presentCount'] as int? ?? 0,
        absentCount: json['absentCount'] as int? ?? 0,
      );
}
