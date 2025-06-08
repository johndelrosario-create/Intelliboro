class GeofenceData {
  final String id;
  final double latitude;
  final double longitude;
  final double radiusMeters;
  final String fillColor;
  final double fillOpacity;
  final String strokeColor;
  final double strokeWidth;
  final String? task;

  GeofenceData({
    required this.id,
    required this.latitude,
    required this.longitude,
    required this.radiusMeters,
    required this.fillColor,
    required this.fillOpacity,
    required this.strokeColor,
    required this.strokeWidth,
    this.task,
  });

  factory GeofenceData.fromJson(Map<String, dynamic> json) {
    return GeofenceData(
      id: json['id'] as String,
      latitude: json['latitude'] as double,
      longitude: json['longitude'] as double,
      radiusMeters: json['radius_meters'] as double,
      fillColor: json['fill_color'] as String,
      fillOpacity: json['fill_opacity'] as double,
      strokeColor: json['stroke_color'] as String,
      strokeWidth: json['stroke_width'] as double,
      task: json['task'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'latitude': latitude,
      'longitude': longitude,
      'radius_meters': radiusMeters,
      'fill_color': fillColor,
      'fill_opacity': fillOpacity,
      'stroke_color': strokeColor,
      'stroke_width': strokeWidth,
      'task': task,
    };
  }
}
