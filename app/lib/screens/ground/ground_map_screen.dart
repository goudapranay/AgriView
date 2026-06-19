import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;
import '../../services/location_service.dart';
import 'ground_form_screen.dart';

class GroundMapScreen extends StatefulWidget {
  const GroundMapScreen({super.key});
  @override
  State<GroundMapScreen> createState() => _GroundMapScreenState();
}

enum _Mode { point, polygon }

class _GroundMapScreenState extends State<GroundMapScreen> {
  final MapController _ctrl    = MapController();
  final _searchCtrl            = TextEditingController();
  _Mode   _mode                = _Mode.point;
  LatLng? _pinned;                          // point mode
  final List<LatLng> _polyPts  = [];        // polygon mode
  bool _locating  = false;
  bool _searching = false;
  List<Map<String, dynamic>> _results = [];

  @override
  void initState() { super.initState(); _goToMyLocation(init: true); }

  Future<void> _goToMyLocation({bool init = false}) async {
    setState(() => _locating = true);
    final pos = await LocationService().getCurrentLocation();
    if (pos != null) {
      _ctrl.move(pos, 16);
      if (init) setState(() => _pinned = pos);
    }
    setState(() => _locating = false);
  }

  Future<void> _search(String q) async {
    if (q.trim().isEmpty) { setState(() => _results = []); return; }
    setState(() => _searching = true);
    try {
      final uri = Uri.parse(
          'https://nominatim.openstreetmap.org/search'
          '?q=${Uri.encodeComponent(q)}&format=json&limit=5');
      final res = await http
          .get(uri, headers: {'User-Agent': 'AgroSense/5.0'})
          .timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as List;
        setState(() => _results = data.map((e) => {
          'name': e['display_name'],
          'lat':  double.parse(e['lat']),
          'lng':  double.parse(e['lon']),
        }).toList());
      }
    } catch (_) {} finally { setState(() => _searching = false); }
  }

  void _flyTo(double lat, double lng) {
    _ctrl.move(LatLng(lat, lng), 16);
    setState(() {
      _results = [];
      _searchCtrl.clear();
      if (_mode == _Mode.point) _pinned = LatLng(lat, lng);
    });
    FocusScope.of(context).unfocus();
  }

  void _onMapTap(LatLng pos) {
    if (_mode == _Mode.point) {
      setState(() => _pinned = pos);
    } else {
      setState(() => _polyPts.add(pos));
    }
  }

  void _undoLastPoint() {
    if (_polyPts.isNotEmpty) setState(() => _polyPts.removeLast());
  }

  void _clearPolygon() => setState(() => _polyPts.clear());

  // Compute area of polygon in acres using Shoelace formula
  double _calcAreaAcres(List<LatLng> pts) {
    if (pts.length < 3) return 0;
    // Convert to approximate metres using equirectangular
    const R = 6371000.0;
    final lat0 = pts.first.latitude * pi / 180;
    final xs = pts.map((p) => p.longitude * pi / 180 * R * cos(lat0)).toList();
    final ys = pts.map((p) => p.latitude  * pi / 180 * R).toList();
    double area = 0;
    final n = pts.length;
    for (int i = 0; i < n; i++) {
      final j = (i + 1) % n;
      area += xs[i] * ys[j];
      area -= xs[j] * ys[i];
    }
    final sqm = (area / 2).abs();
    return sqm / 4046.86; // sq metres → acres
  }

  LatLng _centroid(List<LatLng> pts) {
    final lat = pts.map((p) => p.latitude).reduce((a, b) => a + b) / pts.length;
    final lng = pts.map((p) => p.longitude).reduce((a, b) => a + b) / pts.length;
    return LatLng(lat, lng);
  }

  void _confirm() {
    if (_mode == _Mode.point) {
      if (_pinned == null) return;
      Navigator.push(context, MaterialPageRoute(
          builder: (_) => GroundFormScreen(location: _pinned!)));
    } else {
      if (_polyPts.length < 3) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Tap at least 3 points to draw a field boundary')));
        return;
      }
      final centroid  = _centroid(_polyPts);
      final areaAcres = _calcAreaAcres(_polyPts);
      Navigator.push(context, MaterialPageRoute(
          builder: (_) => GroundFormScreen(
            location:      centroid,
            polygonPoints: List.from(_polyPts),
            areaAcres:     areaAcres,
          )));
    }
  }

  @override
  Widget build(BuildContext context) {
    final canConfirm = _mode == _Mode.point
        ? _pinned != null
        : _polyPts.length >= 3;

    return Scaffold(
      appBar: AppBar(title: const Text('Select Location')),
      body: Stack(children: [

        // ── Map ─────────────────────────────────────────────────────────────
        FlutterMap(
          mapController: _ctrl,
          options: MapOptions(
            initialCenter: const LatLng(17.385, 78.4867),
            initialZoom: 14,
            onTap: (_, pos) => _onMapTap(pos),
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://server.arcgisonline.com/ArcGIS/rest/services/'
                  'World_Imagery/MapServer/tile/{z}/{y}/{x}',
              userAgentPackageName: 'com.agrosense.app',
            ),

            // Point marker
            if (_mode == _Mode.point && _pinned != null)
              MarkerLayer(markers: [
                Marker(
                  point: _pinned!, width: 40, height: 48,
                  child: const Icon(Icons.location_pin,
                      color: Color(0xFF1565C0), size: 40),
                ),
              ]),

            // Polygon lines + filled area
            if (_mode == _Mode.polygon && _polyPts.length >= 2)
              PolylineLayer(polylines: [
                Polyline(
                  points: [..._polyPts, _polyPts.first],
                  color: const Color(0xFF1565C0),
                  strokeWidth: 2.5,
                ),
              ]),

            if (_mode == _Mode.polygon && _polyPts.length >= 3)
              PolygonLayer(polygons: [
                Polygon(
                  points: _polyPts,
                  color: const Color(0x331565C0),
                  borderColor: const Color(0xFF1565C0),
                  borderStrokeWidth: 2.5,
                ),
              ]),

            // Polygon vertex markers
            if (_mode == _Mode.polygon && _polyPts.isNotEmpty)
              MarkerLayer(
                markers: _polyPts.asMap().entries.map((e) => Marker(
                  point: e.value, width: 20, height: 20,
                  child: Container(
                    width: 16, height: 16,
                    decoration: BoxDecoration(
                      color: e.key == 0
                          ? const Color(0xFF2E7D32)
                          : Colors.white,
                      border: Border.all(
                          color: const Color(0xFF1565C0), width: 2),
                      shape: BoxShape.circle,
                    ),
                    child: e.key == 0
                        ? const Icon(Icons.circle,
                            size: 6, color: Colors.white)
                        : null,
                  ),
                )).toList(),
              ),
          ],
        ),

        // ── Mode toggle ──────────────────────────────────────────────────────
        Positioned(top: 12, left: 12, child: _ModeToggle(
          mode: _mode,
          onChanged: (m) => setState(() {
            _mode = m;
            _polyPts.clear();
            _pinned = null;
          }),
        )),

        // ── Search bar ───────────────────────────────────────────────────────
        Positioned(top: 12, left: 120, right: 12,
            child: Column(children: [
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              boxShadow: [BoxShadow(
                  color: Colors.black.withOpacity(0.12),
                  blurRadius: 8, offset: const Offset(0, 2))],
            ),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: 'Search village, district...',
                hintStyle: const TextStyle(fontSize: 13),
                prefixIcon: const Icon(Icons.search,
                    color: Color(0xFF1565C0), size: 20),
                suffixIcon: _searching
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(width: 16, height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Color(0xFF1565C0))))
                    : null,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 4, vertical: 12),
              ),
              onChanged: _search,
            ),
          ),
          if (_results.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(top: 4),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                boxShadow: [BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 8, offset: const Offset(0, 2))],
              ),
              child: Column(
                children: _results.take(5).map((r) => InkWell(
                  onTap: () => _flyTo(r['lat'], r['lng']),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    child: Row(children: [
                      const Icon(Icons.location_on,
                          size: 16, color: Color(0xFF1565C0)),
                      const SizedBox(width: 8),
                      Expanded(child: Text(r['name'],
                          style: const TextStyle(fontSize: 12),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis)),
                    ]),
                  ),
                )).toList(),
              ),
            ),
        ])),

        // ── Info bar (coordinates / polygon info) ────────────────────────────
        if (_results.isEmpty)
          Positioned(top: 76, left: 12, right: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.92),
                borderRadius: BorderRadius.circular(8),
              ),
              child: _mode == _Mode.point && _pinned != null
                  ? Text(
                      '📍 ${_pinned!.latitude.toStringAsFixed(5)}°N  '
                      '${_pinned!.longitude.toStringAsFixed(5)}°E',
                      style: const TextStyle(fontSize: 12,
                          color: Color(0xFF374151),
                          fontWeight: FontWeight.w500),
                      textAlign: TextAlign.center)
                  : _mode == _Mode.polygon
                      ? Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              _polyPts.isEmpty
                                  ? 'Tap map corners to draw field boundary'
                                  : _polyPts.length < 3
                                      ? '${_polyPts.length} point${_polyPts.length == 1 ? '' : 's'} — need ${3 - _polyPts.length} more'
                                      : '🟦 ${_polyPts.length} pts  •  '
                                        '${_calcAreaAcres(_polyPts).toStringAsFixed(2)} acres',
                              style: const TextStyle(fontSize: 12,
                                  color: Color(0xFF1565C0),
                                  fontWeight: FontWeight.w500),
                              textAlign: TextAlign.center,
                            ),
                          ])
                      : const SizedBox(),
            ),
          ),

        // ── Polygon undo / clear controls ─────────────────────────────────
        if (_mode == _Mode.polygon && _polyPts.isNotEmpty)
          Positioned(left: 12, bottom: 90,
            child: Column(children: [
              _MapBtn(
                icon: Icons.undo,
                tooltip: 'Remove last point',
                onTap: _undoLastPoint,
              ),
              const SizedBox(height: 6),
              _MapBtn(
                icon: Icons.delete_outline,
                tooltip: 'Clear all',
                onTap: _clearPolygon,
                color: Colors.red,
              ),
            ]),
          ),

        // ── Zoom + locate controls ──────────────────────────────────────────
        Positioned(right: 12, bottom: 90,
          child: Column(children: [
            _MapBtn(
              icon: Icons.my_location,
              loading: _locating,
              onTap: _goToMyLocation,
              tooltip: 'My location',
            ),
            const SizedBox(height: 6),
            _MapBtn(icon: Icons.add, onTap: () =>
                _ctrl.move(_ctrl.camera.center, _ctrl.camera.zoom + 1)),
            const SizedBox(height: 4),
            _MapBtn(icon: Icons.remove, onTap: () =>
                _ctrl.move(_ctrl.camera.center, _ctrl.camera.zoom - 1)),
          ]),
        ),
      ]),

      // ── Bottom confirm button ──────────────────────────────────────────────
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: ElevatedButton.icon(
            onPressed: canConfirm ? _confirm : null,
            icon: const Icon(Icons.check, size: 18),
            label: Text(
              _mode == _Mode.point
                  ? (_pinned == null
                      ? 'Tap map to mark point'
                      : 'Confirm Point Location')
                  : (_polyPts.length < 3
                      ? 'Draw field boundary (≥3 points)'
                      : 'Confirm Field Boundary  '
                        '(${_calcAreaAcres(_polyPts).toStringAsFixed(2)} ac)'),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1565C0),
              minimumSize: const Size.fromHeight(50),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Mode toggle widget ────────────────────────────────────────────────────────

class _ModeToggle extends StatelessWidget {
  final _Mode mode;
  final ValueChanged<_Mode> onChanged;
  const _ModeToggle({required this.mode, required this.onChanged});

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(10),
      boxShadow: [BoxShadow(
          color: Colors.black.withOpacity(0.12),
          blurRadius: 6, offset: const Offset(0, 2))],
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      _Tab(
        icon: Icons.location_on,
        label: 'Point',
        active: mode == _Mode.point,
        onTap: () => onChanged(_Mode.point),
      ),
      _Tab(
        icon: Icons.crop_free,
        label: 'Field',
        active: mode == _Mode.polygon,
        onTap: () => onChanged(_Mode.polygon),
      ),
    ]),
  );
}

class _Tab extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _Tab({required this.icon, required this.label,
      required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: active ? const Color(0xFF1565C0) : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 15,
            color: active ? Colors.white : const Color(0xFF6B7280)),
        const SizedBox(width: 4),
        Text(label,
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: active ? Colors.white : const Color(0xFF6B7280))),
      ]),
    ),
  );
}

// ── Map control button ────────────────────────────────────────────────────────

class _MapBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool loading;
  final Color? color;
  final String? tooltip;
  const _MapBtn({
    required this.icon, required this.onTap,
    this.loading = false, this.color, this.tooltip,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Tooltip(
      message: tooltip ?? '',
      child: Container(
        width: 40, height: 40,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          boxShadow: [BoxShadow(
              color: Colors.black.withOpacity(0.15),
              blurRadius: 6, offset: const Offset(0, 2))],
        ),
        child: loading
            ? const Center(child: SizedBox(width: 16, height: 16,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Color(0xFF1565C0))))
            : Icon(icon, size: 20,
                color: color ?? const Color(0xFF374151)),
      ),
    ),
  );
}
