class NomadRoute {
  const NomadRoute({
    required this.id,
    required this.shortName,
    required this.longName,
    required this.stopCount,
    required this.tripCount,
    required this.highlighted,
    required this.stopsPreview,
  });

  final String id;
  final String shortName;
  final String longName;
  final int stopCount;
  final int tripCount;
  final bool highlighted;
  final List<NomadStop> stopsPreview;

  factory NomadRoute.fromJson(Map<String, dynamic> json) => NomadRoute(
        id: json['id'] as String,
        shortName: json['shortName'] as String,
        longName: json['longName'] as String,
        stopCount: json['stopCount'] as int,
        tripCount: json['tripCount'] as int,
        highlighted: json['highlighted'] as bool,
        stopsPreview: (((json['stopsPreview'] as List?) ?? (json['stops'] as List?)) ?? []).map((item) => NomadStop.fromJson(item)).toList(),
      );
}

class NomadStop {
  const NomadStop({
    required this.id,
    required this.name,
    required this.sequence,
    this.arrivalTime = '',
  });

  final String id;
  final String name;
  final int sequence;
  final String arrivalTime;

  factory NomadStop.fromJson(Map<String, dynamic> json) => NomadStop(
        id: json['id'] as String,
        name: json['name'] as String,
        sequence: (json['sequence'] as num).toInt(),
        arrivalTime: json['arrivalTime'] as String? ?? '',
      );
}
