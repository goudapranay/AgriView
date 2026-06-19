import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;
import '../../services/location_service.dart';
import 'crop_mask_screen.dart';

class AnalysisMapScreen extends StatefulWidget {
  const AnalysisMapScreen({super.key});
  @override
  State<AnalysisMapScreen> createState() => _AnalysisMapScreenState();
}

class _AnalysisMapScreenState extends State<AnalysisMapScreen> {
  final List<LatLng> _points = [];
  final MapController _ctrl  = MapController();
  final _searchCtrl          = TextEditingController();
  bool _locating  = false;
  bool _searching = false;
  List<Map<String, dynamic>> _results = [];

  @override
  void initState() { super.initState(); _goToMyLocation(init: true); }

  Future<void> _goToMyLocation({bool init = false}) async {
    setState(() => _locating = true);
    final pos = await LocationService().getCurrentLocation();
    if (pos != null) _ctrl.move(pos, 15);
    setState(() => _locating = false);
  }

  Future<void> _search(String q) async {
    if (q.trim().isEmpty) { setState(() => _results = []); return; }
    setState(() => _searching = true);
    try {
      final uri = Uri.parse('https://nominatim.openstreetmap.org/search'
          '?q=${Uri.encodeComponent(q)}&format=json&limit=5');
      final res = await http.get(uri, headers: {'User-Agent': 'AgroSense/5.0'})
          .timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        setState(() => _results = (jsonDecode(res.body) as List).map((e) => {
          'name': e['display_name'],
          'lat':  double.parse(e['lat']),
          'lng':  double.parse(e['lon']),
        }).toList());
      }
    } catch (_) {} finally { setState(() => _searching = false); }
  }

  void _flyTo(double lat, double lng) {
    _ctrl.move(LatLng(lat, lng), 15);
    setState(() { _results = []; _searchCtrl.clear(); });
    FocusScope.of(context).unfocus();
  }

  double _areaAcres() {
    if (_points.length < 3) return 0;
    double area = 0; int n = _points.length;
    for (int i = 0; i < n; i++) {
      int j = (i+1) % n;
      area += _points[i].longitude * _points[j].latitude;
      area -= _points[j].longitude * _points[i].latitude;
    }
    area = area.abs() / 2;
    return area * 111.32 * 111.32 * 247.105 *
        (3.14159265/180 * _points[0].latitude).abs().clamp(0.1, 1.0);
  }

  double _areaHectares() => _areaAcres() * 0.404686;

  void _confirm() {
    if (_points.length < 3) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Mark at least 3 corner points')));
      return;
    }
    final polygon = _points.map((p) => [p.latitude, p.longitude]).toList();
    Navigator.push(context, MaterialPageRoute(
        builder: (_) => CropMaskScreen(polygon: polygon)));
  }

  @override
  Widget build(BuildContext context) {
    final area    = _areaAcres();
    final hectare = _areaHectares();
    final markers = _points.asMap().entries.map((e) => Marker(
      point: e.value, width: 34, height: 34,
      child: Container(
        decoration: BoxDecoration(color: const Color(0xFF2E7D32),
            shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)),
        child: Center(child: Text('${e.key+1}',
            style: const TextStyle(color: Colors.white, fontSize: 11,
                fontWeight: FontWeight.w700))),
      ),
    )).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Draw Field Boundary'),
        actions: [
          if (_points.isNotEmpty)
            IconButton(icon: const Icon(Icons.undo),
                onPressed: () => setState(() => _points.removeLast())),
        ],
      ),
      body: Stack(children: [
        FlutterMap(
          mapController: _ctrl,
          options: MapOptions(
            initialCenter: const LatLng(17.385, 78.4867),
            initialZoom: 14,
            onTap: (_, pos) => setState(() => _points.add(pos)),
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
              userAgentPackageName: 'com.agrosense.app',
            ),
            if (_points.length >= 3)
              PolygonLayer<Object>(polygons: [
                Polygon(
                  points: [..._points, _points.first],
                  color: const Color(0x332E7D32),
                  borderColor: const Color(0xFF2E7D32),
                  borderStrokeWidth: 2.5,
                ),
              ]),
            MarkerLayer(markers: markers),
          ],
        ),

        // Search bar
        Positioned(top: 12, left: 12, right: 12, child: Column(children: [
          Container(
            decoration: BoxDecoration(color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.12),
                    blurRadius: 8, offset: const Offset(0, 2))]),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: 'Search village, district...',
                hintStyle: const TextStyle(fontSize: 13),
                prefixIcon: const Icon(Icons.search, color: Color(0xFF2E7D32), size: 20),
                suffixIcon: _searching
                    ? const Padding(padding: EdgeInsets.all(12),
                        child: SizedBox(width: 16, height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2,
                                color: Color(0xFF2E7D32))))
                    : null,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
              ),
              onChanged: _search,
            ),
          ),
          if (_results.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(top: 4),
              decoration: BoxDecoration(color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1),
                      blurRadius: 8, offset: const Offset(0, 2))]),
              child: Column(children: _results.take(5).map((r) => InkWell(
                onTap: () => _flyTo(r['lat'], r['lng']),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: Row(children: [
                    const Icon(Icons.location_on, size: 16, color: Color(0xFF2E7D32)),
                    const SizedBox(width: 8),
                    Expanded(child: Text(r['name'], style: const TextStyle(fontSize: 12),
                        maxLines: 2, overflow: TextOverflow.ellipsis)),
                  ]),
                ),
              )).toList()),
            ),
        ])),

        // Info banner
        if (_results.isEmpty)
          Positioned(top: 74, left: 12, right: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.92),
                  borderRadius: BorderRadius.circular(8)),
              child: Text(
                _points.isEmpty ? 'Tap field corners to draw boundary'
                    : _points.length < 3 ? 'Add ${3-_points.length} more point(s)'
                    : '${_points.length} pts  •  ${area.toStringAsFixed(2)} ac  •  ${hectare.toStringAsFixed(2)} ha',
                style: TextStyle(fontSize: 12,
                    color: _points.length >= 3 ? const Color(0xFF2E7D32) : const Color(0xFF374151),
                    fontWeight: _points.length >= 3 ? FontWeight.w600 : FontWeight.normal),
                textAlign: TextAlign.center,
              ),
            ),
          ),

        // Controls
        Positioned(right: 12, bottom: 90, child: Column(children: [
          _MapBtn(icon: Icons.my_location, loading: _locating, onTap: _goToMyLocation),
          const SizedBox(height: 6),
          _MapBtn(icon: Icons.add, onTap: () =>
              _ctrl.move(_ctrl.camera.center, _ctrl.camera.zoom + 1)),
          const SizedBox(height: 4),
          _MapBtn(icon: Icons.remove, onTap: () =>
              _ctrl.move(_ctrl.camera.center, _ctrl.camera.zoom - 1)),
        ])),
      ]),

      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            if (_points.isNotEmpty) ...[
              Expanded(child: OutlinedButton(
                onPressed: () => setState(() => _points.clear()),
                style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                    side: const BorderSide(color: Color(0xFFBDBDBD)),
                    foregroundColor: const Color(0xFF6B7280),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                child: const Text('Clear'),
              )),
              const SizedBox(width: 10),
            ],
            Expanded(flex: 2, child: ElevatedButton(
              onPressed: _points.length >= 3 ? _confirm : null,
              child: Text(_points.length < 3
                  ? 'Add ${3-_points.length} more point(s)'
                  : 'Check This Field →'),
            )),
          ]),
        ),
      ),
    );
  }
}

class _MapBtn extends StatelessWidget {
  final IconData icon; final VoidCallback onTap; final bool loading;
  const _MapBtn({required this.icon, required this.onTap, this.loading = false});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 40, height: 40,
      decoration: BoxDecoration(color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.15),
              blurRadius: 6, offset: const Offset(0, 2))]),
      child: loading
          ? const Center(child: SizedBox(width: 16, height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF2E7D32))))
          : Icon(icon, size: 20, color: const Color(0xFF374151)),
    ),
  );
}
