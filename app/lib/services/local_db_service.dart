import 'dart:io';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

const kPending = 'pending';
const kSynced  = 'synced';
const kFailed  = 'failed';

// ── LocalRecord — supports both point and polygon geometry ───────────────────
class LocalRecord {
  final int? id;
  final String plotId;
  final String presentCrop;
  final String? previousCrop, cropStage, irrigation, soilType;
  final String? phone, observations, locationName;
  // Point geometry (always present — centroid for polygons)
  final double latitude, longitude;
  // Polygon geometry (null = point-only record)
  final List<List<double>>? polygonPoints;   // [[lat,lng], ...]
  final double? areaAcres;
  final List<String> photoPaths;
  final List<String> photoLabels;
  final String syncStatus;
  final String? syncError;
  final String createdAt;
  final String? syncedAt;

  LocalRecord({
    this.id,
    required this.plotId,
    required this.presentCrop,
    this.previousCrop, this.cropStage, this.irrigation, this.soilType,
    this.phone, this.observations, this.locationName,
    required this.latitude, required this.longitude,
    this.polygonPoints,
    this.areaAcres,
    this.photoPaths = const [],
    this.photoLabels = const [],
    this.syncStatus = kPending,
    this.syncError,
    required this.createdAt,
    this.syncedAt,
  });

  bool get isPolygon => polygonPoints != null && polygonPoints!.length >= 3;

  Map<String, dynamic> toMap() => {
    'plot_id':        plotId,
    'present_crop':   presentCrop,
    'previous_crop':  previousCrop,
    'crop_stage':     cropStage,
    'irrigation':     irrigation,
    'soil_type':      soilType,
    'phone':          phone,
    'observations':   observations,
    'location_name':  locationName,
    'latitude':       latitude,
    'longitude':      longitude,
    'polygon_points': polygonPoints != null
        ? polygonPoints!.map((pt) => '${pt[0]},${pt[1]}').join('|')
        : null,
    'area_acres':     areaAcres,
    'photo_paths':    photoPaths.join('|'),
    'photo_labels':   photoLabels.join('|'),
    'sync_status':    syncStatus,
    'sync_error':     syncError,
    'created_at':     createdAt,
    'synced_at':      syncedAt,
  };

  factory LocalRecord.fromMap(Map<String, dynamic> m) {
    List<List<double>>? poly;
    final raw = m['polygon_points'] as String?;
    if (raw != null && raw.isNotEmpty) {
      poly = raw.split('|').map((s) {
        final parts = s.split(',');
        return [double.parse(parts[0]), double.parse(parts[1])];
      }).toList();
    }
    return LocalRecord(
      id:             m['id'],
      plotId:         m['plot_id'],
      presentCrop:    m['present_crop'],
      previousCrop:   m['previous_crop'],
      cropStage:      m['crop_stage'],
      irrigation:     m['irrigation'],
      soilType:       m['soil_type'],
      phone:          m['phone'],
      observations:   m['observations'],
      locationName:   m['location_name'],
      latitude:       m['latitude'],
      longitude:      m['longitude'],
      polygonPoints:  poly,
      areaAcres:      m['area_acres'] as double?,
      photoPaths:     (m['photo_paths'] as String? ?? '').isEmpty
          ? [] : (m['photo_paths'] as String).split('|'),
      photoLabels:    (m['photo_labels'] as String? ?? '').isEmpty
          ? [] : (m['photo_labels'] as String).split('|'),
      syncStatus:     m['sync_status'] ?? kPending,
      syncError:      m['sync_error'],
      createdAt:      m['created_at'],
      syncedAt:       m['synced_at'],
    );
  }
}

class LocalDbService {
  static final LocalDbService _i = LocalDbService._();
  factory LocalDbService() => _i;
  LocalDbService._();

  Database? _db;

  Future<Database> get db async {
    if (_db != null) return _db!;
    final dir  = await getDatabasesPath();
    final path = p.join(dir, 'agrosense_local.db');
    _db = await openDatabase(
      path,
      version: 2,
      onCreate: (db, v) async { await _createTables(db); },
      onUpgrade: (db, oldV, newV) async {
        if (oldV < 2) {
          // Add polygon columns to existing installs
          await db.execute(
              'ALTER TABLE ground_records ADD COLUMN polygon_points TEXT');
          await db.execute(
              'ALTER TABLE ground_records ADD COLUMN area_acres REAL');
        }
      },
    );
    return _db!;
  }

  Future<void> _createTables(Database db) async {
    await db.execute('''
      CREATE TABLE ground_records (
        id             INTEGER PRIMARY KEY AUTOINCREMENT,
        plot_id        TEXT UNIQUE NOT NULL,
        present_crop   TEXT NOT NULL,
        previous_crop  TEXT,
        crop_stage     TEXT,
        irrigation     TEXT,
        soil_type      TEXT,
        phone          TEXT,
        observations   TEXT,
        location_name  TEXT,
        latitude       REAL,
        longitude      REAL,
        polygon_points TEXT,
        area_acres     REAL,
        photo_paths    TEXT DEFAULT '',
        photo_labels   TEXT DEFAULT '',
        sync_status    TEXT DEFAULT 'pending',
        sync_error     TEXT,
        created_at     TEXT,
        synced_at      TEXT
      )
    ''');
  }

  Future<void> insertRecord(LocalRecord r) async {
    final d = await db;
    await d.insert('ground_records', r.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> updateSyncStatus(String plotId, String status,
      {String? error, String? syncedAt}) async {
    final d = await db;
    await d.update(
      'ground_records',
      {
        'sync_status': status,
        'sync_error':  error,
        'synced_at':   syncedAt ?? (status == kSynced
            ? DateTime.now().toIso8601String() : null),
      },
      where: 'plot_id = ?', whereArgs: [plotId],
    );
  }

  Future<List<LocalRecord>> getAllRecords() async {
    final d    = await db;
    final rows = await d.query('ground_records', orderBy: 'created_at DESC');
    return rows.map(LocalRecord.fromMap).toList();
  }

  Future<List<LocalRecord>> getPendingRecords() async {
    final d    = await db;
    final rows = await d.query('ground_records',
        where: 'sync_status = ?', whereArgs: [kPending],
        orderBy: 'created_at ASC');
    return rows.map(LocalRecord.fromMap).toList();
  }

  Future<int> getPendingCount() async {
    final d   = await db;
    final res = await d.rawQuery(
        "SELECT COUNT(*) as c FROM ground_records WHERE sync_status = 'pending'");
    return (res.first['c'] as int?) ?? 0;
  }

  Future<void> deleteRecord(String plotId) async {
    final d = await db;
    await d.delete('ground_records', where: 'plot_id = ?', whereArgs: [plotId]);
  }

  Future<Directory> get photoDir async {
    final appDir = await getApplicationDocumentsDirectory();
    final dir    = Directory('${appDir.path}/agrosense_photos');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<String> savePhoto(String sourcePath, String plotId, int index) async {
    final dir  = await photoDir;
    final dest = '${dir.path}/${plotId}_${index.toString().padLeft(2, '0')}.jpg';
    await File(sourcePath).copy(dest);
    return dest;
  }

  Future<void> deletePhotos(List<String> paths) async {
    for (final path in paths) {
      try {
        final f = File(path);
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
  }
}
