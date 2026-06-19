import 'package:flutter/material.dart';
import '../../services/local_db_service.dart';
import '../../services/sync_service.dart';
import '../../services/export_service.dart';

class GroundRecordsScreen extends StatefulWidget {
  const GroundRecordsScreen({super.key});
  @override
  State<GroundRecordsScreen> createState() => _GroundRecordsScreenState();
}

class _GroundRecordsScreenState extends State<GroundRecordsScreen> {
  List<LocalRecord> _records = [];
  bool _loading   = true;
  bool _exporting = false;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    final records = await LocalDbService().getAllRecords();
    setState(() { _records = records; _loading = false; });
  }

  Future<void> _delete(LocalRecord r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete record?'),
        content: const Text(
            'This will delete the record and its photos from this device.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete',
                  style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (ok == true) {
      await LocalDbService().deleteRecord(r.plotId);
      await LocalDbService().deletePhotos(r.photoPaths);
      _load();
    }
  }

  Future<void> _exportCsv() async {
    setState(() => _exporting = true);
    _showResult(await ExportService().exportCsv());
    setState(() => _exporting = false);
  }

  Future<void> _exportGeoJson() async {
    setState(() => _exporting = true);
    _showResult(await ExportService().exportGeoJson());
    setState(() => _exporting = false);
  }

  Future<void> _exportFolder(LocalRecord r) async {
    setState(() => _exporting = true);
    _showResult(await ExportService().exportGroundFolder(r),
        title: 'Folder Saved');
    setState(() => _exporting = false);
  }

  void _showResult(ExportResult result, {String? title}) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Row(children: [
          Icon(
            result.success ? Icons.check_circle : Icons.error_outline,
            color: result.success ? const Color(0xFF2E7D32) : Colors.red,
            size: 20,
          ),
          const SizedBox(width: 8),
          Text(title ?? (result.success ? 'Saved' : 'Failed'),
              style: const TextStyle(fontSize: 15)),
        ]),
        content: Column(mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(result.message, style: const TextStyle(fontSize: 13)),
          if (result.filePath != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                  color: const Color(0xFFF1F8E9),
                  borderRadius: BorderRadius.circular(6)),
              child: Row(children: [
                const Icon(Icons.folder_open,
                    size: 14, color: Color(0xFF558B2F)),
                const SizedBox(width: 6),
                Expanded(child: Text(result.filePath!,
                    style: const TextStyle(
                        fontSize: 10, color: Color(0xFF558B2F),
                        fontFamily: 'monospace'))),
              ]),
            ),
          ],
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context),
              child: const Text('OK')),
        ],
      ),
    );
  }

  void _showExportSheet() {
    if (_records.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No records to export yet.')));
      return;
    }
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 36, height: 4,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2)),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(children: [
                Icon(Icons.download, size: 18, color: Color(0xFF1565C0)),
                SizedBox(width: 8),
                Text('Export All Records',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              ]),
            ),
            const Divider(),
            ListTile(
              leading: _iconBox(Icons.table_chart,
                  const Color(0xFF2E7D32), const Color(0xFFE8F5E9)),
              title: const Text('Export as CSV',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(
                '${_records.length} records  •  Points + Field centroids',
                style: const TextStyle(fontSize: 12),
              ),
              onTap: () { Navigator.pop(context); _exportCsv(); },
            ),
            ListTile(
              leading: _iconBox(Icons.map,
                  const Color(0xFF1565C0), const Color(0xFFE3F2FD)),
              title: const Text('Export as GeoJSON',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(
                '${_records.length} features  •  Points & Polygons  •  QGIS / ArcGIS',
                style: const TextStyle(fontSize: 12),
              ),
              onTap: () { Navigator.pop(context); _exportGeoJson(); },
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'Saved to Downloads/AgroSense/ on your device.',
                style: TextStyle(fontSize: 11, color: Colors.grey[600]),
              ),
            ),
            const SizedBox(height: 12),
          ]),
        ),
      ),
    );
  }

  Widget _iconBox(IconData icon, Color fg, Color bg) => Container(
    width: 36, height: 36,
    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
    child: Icon(icon, size: 18, color: fg),
  );

  String _relDate(String s) {
    try {
      final diff = DateTime.now().difference(DateTime.parse(s));
      if (diff.inMinutes < 1) return 'Just now';
      if (diff.inHours < 1)   return '${diff.inMinutes}m ago';
      if (diff.inDays == 0)   return '${diff.inHours}h ago';
      if (diff.inDays == 1)   return 'Yesterday';
      return '${diff.inDays}d ago';
    } catch (_) { return s; }
  }

  @override
  Widget build(BuildContext context) {
    final points   = _records.where((r) => !r.isPolygon).length;
    final polygons = _records.where((r) => r.isPolygon).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ground Records'),
        actions: [
          if (_exporting)
            const Padding(
              padding: EdgeInsets.all(14),
              child: SizedBox(width: 20, height: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Color(0xFF2E7D32))),
            ),
          if (!_exporting)
            IconButton(
              icon: const Icon(Icons.download),
              tooltip: 'Export CSV / GeoJSON',
              onPressed: _showExportSheet,
            ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF1565C0)))
          : RefreshIndicator(
              color: const Color(0xFF1565C0),
              onRefresh: _load,
              child: _records.isEmpty
                  ? const Center(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Text('📷', style: TextStyle(fontSize: 48)),
                        SizedBox(height: 12),
                        Text('No records yet',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w700)),
                        SizedBox(height: 6),
                        Text('Collect ground data to see records here',
                            style: TextStyle(
                                fontSize: 13, color: Color(0xFF9E9E9E))),
                      ]))
                  : Column(children: [

                      // ── Summary banner ──────────────────────────────────
                      Container(
                        margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F8E9),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: const Color(0xFFA5D6A7)),
                        ),
                        child: Row(children: [
                          const Icon(Icons.storage,
                              size: 16, color: Color(0xFF2E7D32)),
                          const SizedBox(width: 8),
                          Expanded(child: Text(
                            '$points point${points == 1 ? '' : 's'}  •  '
                            '$polygons field${polygons == 1 ? '' : 's'}  •  '
                            '${_records.length} total',
                            style: const TextStyle(
                                fontSize: 13, color: Color(0xFF2E7D32),
                                fontWeight: FontWeight.w600),
                          )),
                          GestureDetector(
                            onTap: _showExportSheet,
                            child: const Row(children: [
                              Icon(Icons.download,
                                  size: 15, color: Color(0xFF2E7D32)),
                              SizedBox(width: 4),
                              Text('Export',
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: Color(0xFF2E7D32),
                                      fontWeight: FontWeight.w700)),
                            ]),
                          ),
                        ]),
                      ),

                      // ── List ───────────────────────────────────────────
                      Expanded(
                        child: ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _records.length,
                          itemBuilder: (_, i) => _RecordCard(
                            record:   _records[i],
                            relDate:  _relDate(_records[i].createdAt),
                            onDelete: () => _delete(_records[i]),
                            onSave:   () => _exportFolder(_records[i]),
                          ),
                        ),
                      ),
                    ]),
            ),
    );
  }
}

// ── Record Card ───────────────────────────────────────────────────────────────

class _RecordCard extends StatelessWidget {
  final LocalRecord record;
  final String relDate;
  final VoidCallback onDelete, onSave;
  const _RecordCard({required this.record, required this.relDate,
      required this.onDelete, required this.onSave});

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 10),
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        Row(children: [
          // Geometry icon
          Container(
            width: 42, height: 42,
            decoration: BoxDecoration(
              color: record.isPolygon
                  ? const Color(0xFFE8F5E9)
                  : const Color(0xFFE3F2FD),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              record.isPolygon ? Icons.crop_free : Icons.location_on,
              color: record.isPolygon
                  ? const Color(0xFF2E7D32)
                  : const Color(0xFF1565C0),
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(record.plotId, style: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.w700)),
            Text(
              '${record.presentCrop}  •  ${record.cropStage ?? "—"}  •  '
              '${record.irrigation ?? "—"}',
              style: const TextStyle(
                  fontSize: 12, color: Color(0xFF6B7280)),
            ),
            Text(
              record.isPolygon
                  ? '${record.polygonPoints!.length} vertices  •  '
                    '${record.areaAcres!.toStringAsFixed(2)} acres'
                  : record.locationName ??
                    '${record.latitude.toStringAsFixed(4)}°N',
              style: TextStyle(
                  fontSize: 11,
                  color: record.isPolygon
                      ? const Color(0xFF2E7D32)
                      : const Color(0xFF9E9E9E)),
            ),
          ])),

          // Save folder button
          GestureDetector(
            onTap: onSave,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F8E9),
                borderRadius: BorderRadius.circular(7),
                border: Border.all(color: const Color(0xFFA5D6A7)),
              ),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.folder_zip, size: 14, color: Color(0xFF2E7D32)),
                SizedBox(width: 4),
                Text('Save', style: TextStyle(
                    fontSize: 11, color: Color(0xFF2E7D32),
                    fontWeight: FontWeight.w600)),
              ]),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(onTap: onDelete,
              child: const Icon(Icons.delete_outline,
                  size: 18, color: Color(0xFFBDBDBD))),
        ]),

        const SizedBox(height: 10),

        Row(children: [
          // Geometry type badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: record.isPolygon
                  ? const Color(0xFFE8F5E9)
                  : const Color(0xFFE3F2FD),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: record.isPolygon
                    ? const Color(0xFFA5D6A7)
                    : const Color(0xFF90CAF9),
              ),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(
                record.isPolygon ? Icons.crop_free : Icons.location_on,
                size: 12,
                color: record.isPolygon
                    ? const Color(0xFF2E7D32)
                    : const Color(0xFF1565C0),
              ),
              const SizedBox(width: 4),
              Text(
                record.isPolygon ? 'Field Boundary' : 'Point',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: record.isPolygon
                        ? const Color(0xFF2E7D32)
                        : const Color(0xFF1565C0)),
              ),
            ]),
          ),
          const SizedBox(width: 8),

          if (record.photoPaths.isNotEmpty) ...[
            const Icon(Icons.photo_camera, size: 13,
                color: Color(0xFF9E9E9E)),
            const SizedBox(width: 3),
            Text('${record.photoPaths.length} photos',
                style: const TextStyle(
                    fontSize: 11, color: Color(0xFF9E9E9E))),
          ],

          const Spacer(),
          Text(relDate, style: const TextStyle(
              fontSize: 11, color: Color(0xFF9E9E9E))),
        ]),
      ]),
    ),
  );
}
