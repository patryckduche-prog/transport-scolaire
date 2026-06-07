class NomadRoute {
  const NomadRoute({
    required this.id,
    required this.shortName,
    required this.longName,
    required this.stopCount,
    required this.tripCount,
    required this.highlighted,
    required this.stopsPreview,
    this.coachGuidance,
  });

  final String id;
  final String shortName;
  final String longName;
  final int stopCount;
  final int tripCount;
  final bool highlighted;
  final List<NomadStop> stopsPreview;
  final CoachGuidance? coachGuidance;

  factory NomadRoute.fromJson(Map<String, dynamic> json) => NomadRoute(
        id: json['id'] as String,
        shortName: json['shortName'] as String,
        longName: json['longName'] as String,
        stopCount: json['stopCount'] as int,
        tripCount: json['tripCount'] as int,
        highlighted: json['highlighted'] as bool,
        stopsPreview:
            (((json['stopsPreview'] as List?) ?? (json['stops'] as List?)) ??
                    [])
                .map((item) => NomadStop.fromJson(item))
                .toList(),
        coachGuidance: json['coachGuidance'] is Map<String, dynamic>
            ? CoachGuidance.fromJson(
                json['coachGuidance'] as Map<String, dynamic>)
            : null,
      );
}

class CoachGuidance {
  const CoachGuidance({
    required this.status,
    required this.safetyNotice,
    required this.externalNavigationNotice,
    required this.rules,
    this.corridor,
    this.vehicleProfile,
  });

  final String status;
  final String safetyNotice;
  final String externalNavigationNotice;
  final List<CoachRouteRule> rules;
  final String? corridor;
  final CoachVehicleProfile? vehicleProfile;

  factory CoachGuidance.fromJson(Map<String, dynamic> json) => CoachGuidance(
        status: json['status'] as String? ?? 'a_verifier',
        safetyNotice: json['safetyNotice'] as String? ?? '',
        externalNavigationNotice:
            json['externalNavigationNotice'] as String? ?? '',
        corridor: json['corridor'] as String?,
        vehicleProfile: json['vehicleProfile'] is Map<String, dynamic>
            ? CoachVehicleProfile.fromJson(
                json['vehicleProfile'] as Map<String, dynamic>)
            : null,
        rules: ((json['rules'] as List?) ?? [])
            .whereType<Map<String, dynamic>>()
            .map(CoachRouteRule.fromJson)
            .toList(),
      );
}

class CoachVehicleProfile {
  const CoachVehicleProfile({
    required this.label,
    this.lengthMeters,
    this.widthMeters,
    this.heightMeters,
    this.grossWeightTons,
  });

  final String label;
  final double? lengthMeters;
  final double? widthMeters;
  final double? heightMeters;
  final double? grossWeightTons;

  factory CoachVehicleProfile.fromJson(Map<String, dynamic> json) =>
      CoachVehicleProfile(
        label: json['label'] as String? ?? 'Autocar scolaire',
        lengthMeters: (json['lengthMeters'] as num?)?.toDouble(),
        widthMeters: (json['widthMeters'] as num?)?.toDouble(),
        heightMeters: (json['heightMeters'] as num?)?.toDouble(),
        grossWeightTons: (json['grossWeightTons'] as num?)?.toDouble(),
      );
}

class CoachRouteRule {
  const CoachRouteRule({
    required this.type,
    required this.label,
    required this.description,
  });

  final String type;
  final String label;
  final String description;

  factory CoachRouteRule.fromJson(Map<String, dynamic> json) => CoachRouteRule(
        type: json['type'] as String? ?? 'info',
        label: json['label'] as String? ?? 'Information',
        description: json['description'] as String? ?? '',
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
