import 'dart:io';
import 'dart:convert';
import 'package:path_provider/path_provider.dart';
import 'local_db_service.dart';
import '../models/models.dart';

class ExportResult {
  final bool success;
  final String message;
  final String? filePath;
  ExportResult({required this.success, required this.message, this.filePath});
}

class ExportService {
  static final ExportService _i = ExportService._();
  factory ExportService() => _i;
  ExportService._();

  // ── Base directory ─────────────────────────────────────────────────────────
  Future<Directory> _baseDir() async {
    if (Platform.isAndroid) {
      final dl = Directory('/storage/emulated/0/Download/AgroSense');
      try {
        if (!await dl.exists()) await dl.create(recursive: true);
        final test = File('${dl.path}/.writetest');
        await test.writeAsString('ok');
        await test.delete();
        return dl;
      } catch (_) {}
    }
    final appDir = await getApplicationDocumentsDirectory();
    final dir    = Directory('${appDir.path}/AgroSense');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 1. All records — CSV (points + polygon centroids)
  // ═══════════════════════════════════════════════════════════════════════════
  Future<ExportResult> exportCsv() async {
    try {
      final records = await LocalDbService().getAllRecords();
      if (records.isEmpty) {
        return ExportResult(success: false, message: 'No records to export.');
      }
      final sb = StringBuffer();
      sb.writeln(
        'plot_id,geometry_type,present_crop,previous_crop,crop_stage,'
        'irrigation,soil_type,phone,observations,location_name,'
        'latitude,longitude,area_acres,vertex_count,photo_count,created_at',
      );
      for (final r in records) {
        sb.writeln([
          _q(r.plotId),
          _q(r.isPolygon ? 'polygon' : 'point'),
          _q(r.presentCrop), _q(r.previousCrop), _q(r.cropStage),
          _q(r.irrigation), _q(r.soilType), _q(r.phone),
          _q(r.observations), _q(r.locationName),
          r.latitude.toStringAsFixed(6),
          r.longitude.toStringAsFixed(6),
          r.areaAcres != null ? r.areaAcres!.toStringAsFixed(4) : '',
          r.isPolygon ? r.polygonPoints!.length.toString() : '1',
          r.photoPaths.length.toString(),
          _q(r.createdAt),
        ].join(','));
      }
      final base = await _baseDir();
      final file = File('${base.path}/records_${_ts()}.csv');
      await file.writeAsString(sb.toString(), encoding: utf8);
      return ExportResult(
        success: true,
        message: '${records.length} records saved.',
        filePath: file.path,
      );
    } catch (e) {
      return ExportResult(success: false, message: 'CSV export failed: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 2. All records — GeoJSON (Points and Polygons as proper geometry types)
  // ═══════════════════════════════════════════════════════════════════════════
  Future<ExportResult> exportGeoJson() async {
    try {
      final records = await LocalDbService().getAllRecords();
      if (records.isEmpty) {
        return ExportResult(success: false, message: 'No records to export.');
      }

      final features = records.map((r) {
        final Map<String, dynamic> geometry;
        if (r.isPolygon) {
          // GeoJSON polygon: [[[lng, lat], ...]] — close the ring
          final coords = r.polygonPoints!
              .map((pt) => [pt[1], pt[0]])   // [lng, lat]
              .toList();
          coords.add(coords.first);           // close ring
          geometry = {
            'type': 'Polygon',
            'coordinates': [coords],
          };
        } else {
          geometry = {
            'type': 'Point',
            'coordinates': [r.longitude, r.latitude],
          };
        }

        return {
          'type': 'Feature',
          'geometry': geometry,
          'properties': {
            'plot_id':       r.plotId,
            'geometry_type': r.isPolygon ? 'polygon' : 'point',
            'present_crop':  r.presentCrop,
            'previous_crop': r.previousCrop,
            'crop_stage':    r.cropStage,
            'irrigation':    r.irrigation,
            'soil_type':     r.soilType,
            'phone':         r.phone,
            'observations':  r.observations,
            'location_name': r.locationName,
            'latitude':      r.latitude,
            'longitude':     r.longitude,
            'area_acres':    r.areaAcres,
            'photo_count':   r.photoPaths.length,
            'created_at':    r.createdAt,
          },
        };
      }).toList();

      final base = await _baseDir();
      final file = File('${base.path}/records_${_ts()}.geojson');
      await file.writeAsString(
        const JsonEncoder.withIndent('  ').convert({
          'type': 'FeatureCollection', 'features': features,
        }),
        encoding: utf8,
      );
      return ExportResult(
        success: true,
        message: '${records.length} features saved.',
        filePath: file.path,
      );
    } catch (e) {
      return ExportResult(success: false, message: 'GeoJSON export failed: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 3. Single record folder — CSV + photos
  //    Downloads/AgroSense/Ground/<plotId>/record.csv + photos
  // ═══════════════════════════════════════════════════════════════════════════
  Future<ExportResult> exportGroundFolder(LocalRecord r) async {
    try {
      final base   = await _baseDir();
      final folder = Directory('${base.path}/Ground/${r.plotId}');
      if (!await folder.exists()) await folder.create(recursive: true);

      // CSV
      final sb = StringBuffer();
      sb.writeln(
        'plot_id,geometry_type,present_crop,previous_crop,crop_stage,'
        'irrigation,soil_type,phone,observations,location_name,'
        'latitude,longitude,area_acres,vertex_count,created_at',
      );
      sb.writeln([
        _q(r.plotId), _q(r.isPolygon ? 'polygon' : 'point'),
        _q(r.presentCrop), _q(r.previousCrop), _q(r.cropStage),
        _q(r.irrigation), _q(r.soilType), _q(r.phone),
        _q(r.observations), _q(r.locationName),
        r.latitude.toStringAsFixed(6), r.longitude.toStringAsFixed(6),
        r.areaAcres != null ? r.areaAcres!.toStringAsFixed(4) : '',
        r.isPolygon ? r.polygonPoints!.length.toString() : '1',
        _q(r.createdAt),
      ].join(','));
      await File('${folder.path}/record.csv')
          .writeAsString(sb.toString(), encoding: utf8);

      // GeoJSON for this single record
      final Map<String, dynamic> geometry;
      if (r.isPolygon) {
        final coords = r.polygonPoints!
            .map((pt) => [pt[1], pt[0]]).toList();
        coords.add(coords.first);
        geometry = {'type': 'Polygon', 'coordinates': [coords]};
      } else {
        geometry = {'type': 'Point', 'coordinates': [r.longitude, r.latitude]};
      }
      final geojson = {
        'type': 'Feature',
        'geometry': geometry,
        'properties': {
          'plot_id': r.plotId, 'present_crop': r.presentCrop,
          'area_acres': r.areaAcres, 'created_at': r.createdAt,
        },
      };
      await File('${folder.path}/boundary.geojson')
          .writeAsString(const JsonEncoder.withIndent('  ').convert(geojson),
              encoding: utf8);

      // Copy photos
      int copied = 0;
      for (int i = 0; i < r.photoPaths.length; i++) {
        final src = File(r.photoPaths[i]);
        if (await src.exists()) {
          final ext  = r.photoPaths[i].split('.').last;
          await src.copy('${folder.path}/photo_${i + 1}.$ext');
          copied++;
        }
      }

      return ExportResult(
        success: true,
        message: 'Saved record.csv + boundary.geojson'
            '${copied > 0 ? ' + $copied photo${copied == 1 ? '' : 's'}' : ''}.',
        filePath: folder.path,
      );
    } catch (e) {
      return ExportResult(success: false, message: 'Folder export failed: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 4. Field Analysis HTML report
  //    Downloads/AgroSense/Reports/<plotId>_report.html
  // ═══════════════════════════════════════════════════════════════════════════
  Future<ExportResult> exportAnalysisReport(FieldAnalysis a) async {
    try {
      final base = await _baseDir();
      final dir  = Directory('${base.path}/Reports');
      if (!await dir.exists()) await dir.create(recursive: true);
      final safeId = a.plotId.replaceAll(RegExp(r'[^\w\-]'), '_');
      final file   = File('${dir.path}/${safeId}_report.html');
      await file.writeAsString(_buildHtml(a), encoding: utf8);
      return ExportResult(
        success: true,
        message: 'Report saved for ${a.plotId}.',
        filePath: file.path,
      );
    } catch (e) {
      return ExportResult(success: false, message: 'Report export failed: $e');
    }
  }

  // ── HTML builder ──────────────────────────────────────────────────────────
  String _buildHtml(FieldAnalysis a) {
    final ndviColor = a.ndvi.health == 'Good'
        ? '#2E7D32' : a.ndvi.health == 'Moderate' ? '#F57C00' : '#C62828';
    final weatherRows = a.weather.map((w) => '''
      <tr>
        <td>${w.emoji} ${w.day}</td>
        <td>${w.tempMin.toStringAsFixed(0)}°–${w.tempMax.toStringAsFixed(0)}°C</td>
        <td>${w.rainMm.toStringAsFixed(1)} mm</td>
        <td>${w.desc}</td>
      </tr>''').join('\n');
    final ndviRows = a.ndvi.series.map((p) => '''
      <tr>
        <td>${p.month}</td>
        <td>${p.ndvi != null ? p.ndvi!.toStringAsFixed(3) : '—'}</td>
        <td style="width:120px">
          <div style="height:10px;background:#E8F5E9;border-radius:4px">
            <div style="height:10px;width:${((p.ndvi ?? 0) * 100).clamp(0, 100).toStringAsFixed(0)}%;background:#2E7D32;border-radius:4px"></div>
          </div>
        </td>
      </tr>''').join('\n');

    return '''<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1.0">
<title>AgroSense Report — ${a.plotId}</title>
<style>
  *{box-sizing:border-box;margin:0;padding:0}
  body{font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;
       background:#F9FAF7;color:#1C2B1A;padding:16px;font-size:14px}
  .header{background:linear-gradient(135deg,#1B5E20,#2E7D32);color:#fff;
          border-radius:14px;padding:20px;margin-bottom:16px}
  .header h1{font-size:20px;font-weight:800;margin-bottom:4px}
  .badge{display:inline-block;background:rgba(255,255,255,.2);
         border-radius:6px;padding:2px 8px;font-size:11px;margin-top:8px}
  .card{background:#fff;border-radius:12px;padding:16px;margin-bottom:14px;
        border:1px solid #E5E7EB;box-shadow:0 1px 3px rgba(0,0,0,.06)}
  .card h2{font-size:14px;font-weight:700;color:#374151;margin-bottom:12px;
           padding-bottom:8px;border-bottom:1px solid #F3F4F6}
  .grid2{display:grid;grid-template-columns:1fr 1fr;gap:10px}
  .kv{background:#F9FAF7;border-radius:8px;padding:10px}
  .kv .k{font-size:11px;color:#9CA3AF;margin-bottom:2px}
  .kv .v{font-size:14px;font-weight:600;color:#111827}
  .ndvi-badge{display:inline-block;padding:4px 12px;border-radius:20px;
              font-weight:700;font-size:15px;color:#fff;
              background:${ndviColor};margin-bottom:8px}
  table{width:100%;border-collapse:collapse;font-size:13px}
  th{text-align:left;padding:6px 8px;background:#F3F4F6;
     font-size:11px;color:#6B7280;font-weight:600}
  td{padding:7px 8px;border-bottom:1px solid #F9FAF7}
  tr:last-child td{border-bottom:none}
  .note{background:#FFFBEB;border:1px solid #FDE68A;border-radius:10px;
        padding:14px;font-size:13px;line-height:1.6;color:#78350F}
  .sow{background:#E8F5E9;border:1px solid #A5D6A7;border-radius:10px;padding:14px}
  .sow .row{display:flex;justify-content:space-between;margin-bottom:6px}
  .sow .label{font-size:12px;color:#4CAF50;font-weight:600}
  .sow .val{font-size:13px;font-weight:700}
  .sow .reason{font-size:12px;color:#374151;margin-top:8px;line-height:1.5}
  .footer{text-align:center;font-size:11px;color:#9CA3AF;margin-top:20px}
  .land-bar{height:12px;border-radius:6px;background:#E8F5E9;overflow:hidden;
            display:flex;margin-bottom:6px}
  .land-seg{height:12px}
</style>
</head>
<body>
<div class="header">
  <h1>🌾 ${a.plotId}</h1>
  <p>📍 ${a.locationName}</p>
  <p style="margin-top:6px">
    ${a.areaAcres.toStringAsFixed(2)} acres &nbsp;•&nbsp;
    ${a.areaHectares.toStringAsFixed(2)} ha &nbsp;•&nbsp;
    ${a.cropMask.cropPct.toStringAsFixed(0)}% cropland
  </p>
  <span class="badge">${a.gee ? '🛰 Sentinel-2 Live' : '🔬 Simulated'}</span>
  <span class="badge" style="margin-left:6px">📅 ${a.analysedAt}</span>
</div>
<div class="card">
  <h2>🛰 NDVI Crop Health</h2>
  <div class="ndvi-badge">${a.ndvi.health}</div>
  <p style="font-size:13px;color:#374151;margin-bottom:12px">${a.ndvi.interpretation}</p>
  <div class="grid2" style="margin-bottom:14px">
    <div class="kv"><div class="k">Peak NDVI</div><div class="v">${a.ndvi.peak.toStringAsFixed(3)}</div></div>
    <div class="kv"><div class="k">Peak Month</div><div class="v">${a.ndvi.peakMonth}</div></div>
  </div>
  <table><tr><th>Month</th><th>NDVI</th><th>Bar</th></tr>$ndviRows</table>
</div>
<div class="card">
  <h2>🗺 Land Cover</h2>
  <div class="land-bar">
    <div class="land-seg" style="width:${a.cropMask.cropPct.toStringAsFixed(0)}%;background:#2E7D32"></div>
    <div class="land-seg" style="width:${a.cropMask.treePct.toStringAsFixed(0)}%;background:#66BB6A"></div>
    <div class="land-seg" style="width:${a.cropMask.shrubPct.toStringAsFixed(0)}%;background:#A5D6A7"></div>
    <div class="land-seg" style="width:${a.cropMask.grassPct.toStringAsFixed(0)}%;background:#C8E6C9"></div>
    <div class="land-seg" style="width:${a.cropMask.builtupPct.toStringAsFixed(0)}%;background:#BDBDBD"></div>
  </div>
  <div class="grid2">
    <div class="kv"><div class="k">🌾 Cropland</div><div class="v">${a.cropMask.cropPct.toStringAsFixed(1)}%</div></div>
    <div class="kv"><div class="k">🌳 Trees</div><div class="v">${a.cropMask.treePct.toStringAsFixed(1)}%</div></div>
    <div class="kv"><div class="k">🌿 Shrubs</div><div class="v">${a.cropMask.shrubPct.toStringAsFixed(1)}%</div></div>
    <div class="kv"><div class="k">🏘 Built-up</div><div class="v">${a.cropMask.builtupPct.toStringAsFixed(1)}%</div></div>
  </div>
  <p style="font-size:11px;color:#9CA3AF;margin-top:10px">Source: ${a.cropMask.source}</p>
</div>
<div class="card">
  <h2>🌱 Sowing Window</h2>
  <div class="sow">
    <div class="row">
      <div><div class="label">Early</div><div class="val">${a.sowing.early}</div></div>
      <div><div class="label">Peak</div><div class="val">${a.sowing.peak}</div></div>
      <div><div class="label">Late</div><div class="val">${a.sowing.late}</div></div>
    </div>
    <div class="reason">${a.sowing.reason}</div>
  </div>
</div>
<div class="card">
  <h2>🌤 7-Day Weather</h2>
  <table><tr><th>Day</th><th>Temp</th><th>Rain</th><th>Condition</th></tr>$weatherRows</table>
</div>
<div class="card">
  <h2>📋 Farm Advisory</h2>
  <div class="note">${a.farmNote}</div>
</div>
<div class="footer">
  Generated by AgroSense &nbsp;•&nbsp; ${a.analysedAt}<br>
  Saved locally on device — no internet needed
</div>
</body>
</html>''';
  }

  // ── Helpers ────────────────────────────────────────────────────────────────
  String _q(String? v) {
    if (v == null || v.isEmpty) return '';
    return '"${v.replaceAll('"', '""')}"';
  }

  String _ts() {
    final n = DateTime.now();
    return '${n.year}${_p(n.month)}${_p(n.day)}_${_p(n.hour)}${_p(n.minute)}';
  }

  String _p(int n) => n.toString().padLeft(2, '0');
}
