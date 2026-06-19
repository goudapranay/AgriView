// ── Ground Record ─────────────────────────────────────────────────────────────
class GroundRecord {
  final String plotId, presentCrop;
  final String? previousCrop, cropStage, irrigation, soilType, phone, observations, locationName;
  final double latitude, longitude;
  final int photoCount;
  final String createdAt;

  GroundRecord({
    required this.plotId, required this.presentCrop,
    this.previousCrop, this.cropStage, this.irrigation,
    this.soilType, this.phone, this.observations,
    this.locationName,
    required this.latitude, required this.longitude,
    this.photoCount = 0, required this.createdAt,
  });

  factory GroundRecord.fromJson(Map<String, dynamic> j) => GroundRecord(
    plotId:       j['plot_id'] ?? '',
    presentCrop:  j['present_crop'] ?? '',
    previousCrop: j['previous_crop'],
    cropStage:    j['crop_stage'],
    irrigation:   j['irrigation'],
    soilType:     j['soil_type'],
    phone:        j['phone'],
    observations: j['observations'],
    locationName: j['location_name'],
    latitude:     (j['latitude'] ?? 0).toDouble(),
    longitude:    (j['longitude'] ?? 0).toDouble(),
    photoCount:   j['photo_count'] ?? 0,
    createdAt:    j['created_at'] ?? '',
  );
}

// ── NDVI ──────────────────────────────────────────────────────────────────────
class NdviPoint {
  final String month;
  final double? ndvi;
  NdviPoint({required this.month, this.ndvi});
  factory NdviPoint.fromJson(Map<String, dynamic> j) =>
      NdviPoint(month: j['month'], ndvi: j['ndvi']?.toDouble());
}

class NdviResult {
  final List<NdviPoint> series;
  final double peak;
  final String peakMonth, health, interpretation;
  NdviResult({required this.series, required this.peak,
      required this.peakMonth, required this.health,
      required this.interpretation});
  factory NdviResult.fromJson(Map<String, dynamic> j) => NdviResult(
    series:         (j['series'] as List).map((e) => NdviPoint.fromJson(e)).toList(),
    peak:           (j['peak'] ?? 0).toDouble(),
    peakMonth:      j['peak_month'] ?? '—',
    health:         j['health'] ?? '—',
    interpretation: j['interpretation'] ?? '',
  );
}

// ── Weather ───────────────────────────────────────────────────────────────────
class WeatherDay {
  final String date, day, desc, emoji;
  final double tempMin, tempMax, rainMm;
  WeatherDay({required this.date, required this.day, required this.desc,
      required this.emoji, required this.tempMin,
      required this.tempMax, required this.rainMm});
  factory WeatherDay.fromJson(Map<String, dynamic> j) => WeatherDay(
    date: j['date'], day: j['day'], desc: j['desc'],
    emoji: j['emoji'] ?? '🌤',
    tempMin: (j['temp_min'] as num).toDouble(),
    tempMax: (j['temp_max'] as num).toDouble(),
    rainMm:  (j['rain_mm'] as num).toDouble(),
  );
}

// ── Sowing Window ─────────────────────────────────────────────────────────────
class SowingWindow {
  final String early, peak, late, reason;
  SowingWindow({required this.early, required this.peak,
      required this.late, required this.reason});
  factory SowingWindow.fromJson(Map<String, dynamic> j) => SowingWindow(
    early:  j['early'] ?? '—',
    peak:   j['peak']  ?? '—',
    late:   j['late']  ?? '—',
    reason: j['reason'] ?? '',
  );
}

// ── Crop Mask ─────────────────────────────────────────────────────────────────
class CropMask {
  final bool isCropland;
  final double cropPct, treePct, shrubPct, grassPct, builtupPct;
  final String source;
  CropMask({required this.isCropland, required this.cropPct,
      required this.treePct, required this.shrubPct,
      required this.grassPct, required this.builtupPct,
      required this.source});
  factory CropMask.fromJson(Map<String, dynamic> j) => CropMask(
    isCropland: j['is_cropland'] ?? false,
    cropPct:    (j['crop_pct'] ?? 0).toDouble(),
    treePct:    (j['tree_pct'] ?? 0).toDouble(),
    shrubPct:   (j['shrub_pct'] ?? 0).toDouble(),
    grassPct:   (j['grass_pct'] ?? 0).toDouble(),
    builtupPct: (j['buildup_pct'] ?? 0).toDouble(),
    source:     j['source'] ?? '',
  );
}

// ── Field Analysis ────────────────────────────────────────────────────────────
class FieldAnalysis {
  final String plotId, locationName;
  final double areaAcres, areaHectares;
  final String? phone;
  final CropMask cropMask;
  final NdviResult ndvi;
  final List<WeatherDay> weather;
  final String farmNote;
  final SowingWindow sowing;
  final bool gee;
  final String analysedAt;

  FieldAnalysis({
    required this.plotId, required this.locationName,
    required this.areaAcres, required this.areaHectares,
    this.phone,
    required this.cropMask, required this.ndvi,
    required this.weather, required this.farmNote,
    required this.sowing, required this.gee,
    required this.analysedAt,
  });

  factory FieldAnalysis.fromJson(Map<String, dynamic> j) => FieldAnalysis(
    plotId:        j['plot_id'] ?? '',
    locationName:  j['location_name'] ?? '',
    areaAcres:     (j['area_acres'] ?? 0).toDouble(),
    areaHectares:  (j['area_hectares'] ?? 0).toDouble(),
    phone:         j['phone'],
    cropMask:      CropMask.fromJson(j['crop_mask'] ?? {}),
    ndvi:          NdviResult.fromJson(j['ndvi'] ?? {}),
    weather:       (j['weather'] as List? ?? []).map((e) => WeatherDay.fromJson(e)).toList(),
    farmNote:      j['farm_note'] ?? '',
    sowing:        SowingWindow.fromJson(j['sowing'] ?? {}),
    gee:           j['gee'] ?? false,
    analysedAt:    j['analysed_at'] ?? '',
  );
}
