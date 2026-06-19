import 'dart:io';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import '../../services/local_db_service.dart';

const _crops  = ['Rice','Wheat','Maize','Cotton','Chickpea','Sorghum',
    'Groundnut','Sunflower','Soybean','Other'];
const _stages = ['Land Preparation','Sowing','Germination','Vegetative',
    'Flowering','Grain Filling','Harvest','Fallow'];
const _irrigationOptions = ['Rainfed','Borewell','Canal','Drip',
    'Sprinkler','Pond','Other'];
const _soilTypes  = ['Black Cotton','Red Loam','Sandy','Clayey',
    'Alluvial','Laterite','Other'];
const _photoLabels = ['Field Overview','Crop Closeup','Soil',
    'Pest Damage','Irrigation','Other'];

class GroundFormScreen extends StatefulWidget {
  final LatLng location;
  final List<LatLng>? polygonPoints;   // null = point record
  final double? areaAcres;

  const GroundFormScreen({
    super.key,
    required this.location,
    this.polygonPoints,
    this.areaAcres,
  });

  bool get isPolygon =>
      polygonPoints != null && polygonPoints!.length >= 3;

  @override
  State<GroundFormScreen> createState() => _GroundFormScreenState();
}

class _GroundFormScreenState extends State<GroundFormScreen> {
  String? _presentCrop, _previousCrop, _cropStage, _irrigationSel, _soilType;
  final _phoneCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  final List<XFile>  _tempPhotos = [];
  final List<String> _labels     = [];
  bool _saving = false;
  String? _error;
  final _picker = ImagePicker();

  Future<void> _addPhoto() async {
    if (_tempPhotos.length >= 5) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Maximum 5 photos allowed')));
      return;
    }
    final picked = await _picker.pickImage(source: ImageSource.camera);
    if (picked != null) {
      setState(() { _tempPhotos.add(picked); _labels.add('Field Overview'); });
    }
  }

  Future<void> _save() async {
    if (_presentCrop == null) {
      setState(() => _error = 'Please select present crop');
      return;
    }
    setState(() { _saving = true; _error = null; });
    try {
      final now    = DateTime.now();
      final prefix = widget.isPolygon ? 'Field' : 'Point';
      final plotId = '${prefix}_${_presentCrop!.replaceAll(' ', '')}_'
          '${DateFormat('yyyyMMdd_HHmm').format(now)}';

      // Copy photos to permanent local storage
      final localPaths = <String>[];
      for (int i = 0; i < _tempPhotos.length; i++) {
        final path = await LocalDbService()
            .savePhoto(_tempPhotos[i].path, plotId, i + 1);
        localPaths.add(path);
      }

      // Convert LatLng polygon to [[lat,lng], ...]
      List<List<double>>? polyData;
      if (widget.isPolygon) {
        polyData = widget.polygonPoints!
            .map((p) => [p.latitude, p.longitude])
            .toList();
      }

      await LocalDbService().insertRecord(LocalRecord(
        plotId:        plotId,
        presentCrop:   _presentCrop!,
        previousCrop:  _previousCrop,
        cropStage:     _cropStage,
        irrigation:    _irrigationSel,
        soilType:      _soilType,
        phone:         _phoneCtrl.text.trim().isEmpty
            ? null : _phoneCtrl.text.trim(),
        observations:  _notesCtrl.text.trim().isEmpty
            ? null : _notesCtrl.text.trim(),
        latitude:      widget.location.latitude,
        longitude:     widget.location.longitude,
        polygonPoints: polyData,
        areaAcres:     widget.areaAcres,
        photoPaths:    localPaths,
        photoLabels:   _labels,
        syncStatus:    kPending,
        createdAt:     now.toIso8601String(),
      ));

      if (mounted) _showSuccess(plotId);
    } catch (e) {
      setState(() {
        _error  = 'Could not save. Please try again.';
        _saving = false;
      });
    }
  }

  void _showSuccess(String plotId) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('✅', style: TextStyle(fontSize: 48)),
          const SizedBox(height: 12),
          const Text('Record Saved!', style: TextStyle(
              fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Text(plotId, style: const TextStyle(
              fontSize: 12, color: Color(0xFF6B7280)),
              textAlign: TextAlign.center),
          const SizedBox(height: 10),

          // Geometry info
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(
              widget.isPolygon ? Icons.crop_free : Icons.location_on,
              color: const Color(0xFF1565C0), size: 15,
            ),
            const SizedBox(width: 5),
            Text(
              widget.isPolygon
                  ? '${widget.polygonPoints!.length} pts  •  '
                    '${widget.areaAcres!.toStringAsFixed(2)} acres'
                  : '${widget.location.latitude.toStringAsFixed(5)}°N  '
                    '${widget.location.longitude.toStringAsFixed(5)}°E',
              style: const TextStyle(
                  fontSize: 12, color: Color(0xFF1565C0)),
            ),
          ]),
          const SizedBox(height: 6),

          // Local save confirmation
          const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.save, color: Color(0xFF2E7D32), size: 15),
            SizedBox(width: 5),
            Text('Saved locally on device ✅',
                style: TextStyle(fontSize: 12, color: Color(0xFF2E7D32))),
          ]),
          const SizedBox(height: 4),
          const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.photo_camera, color: Color(0xFF2E7D32), size: 15),
            SizedBox(width: 5),
            Text('Photos preserved with GPS ✅',
                style: TextStyle(fontSize: 12, color: Color(0xFF2E7D32))),
          ]),
        ]),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pop(context);
              Navigator.pop(context);
            },
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  Widget _lbl(String t) => Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(t, style: const TextStyle(
          fontSize: 13, fontWeight: FontWeight.w600,
          color: Color(0xFF374151))));

  Widget _dd(String hint, List<String> items, String? value,
      ValueChanged<String?> cb) =>
      DropdownButtonFormField<String>(
        value: value,
        decoration: InputDecoration(hintText: hint),
        items: items.map((e) =>
            DropdownMenuItem(value: e, child: Text(e))).toList(),
        onChanged: cb,
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ground Data Collection')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

          // ── Location / geometry banner ─────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: widget.isPolygon
                  ? const Color(0xFFE8F5E9)
                  : const Color(0xFFE3F2FD),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(children: [
              Icon(
                widget.isPolygon ? Icons.crop_free : Icons.location_on,
                color: widget.isPolygon
                    ? const Color(0xFF2E7D32)
                    : const Color(0xFF1565C0),
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  widget.isPolygon
                      ? 'Field Boundary — ${widget.polygonPoints!.length} vertices'
                      : '${widget.location.latitude.toStringAsFixed(5)}°N  '
                        '${widget.location.longitude.toStringAsFixed(5)}°E',
                  style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600,
                      color: widget.isPolygon
                          ? const Color(0xFF2E7D32)
                          : const Color(0xFF1565C0)),
                ),
                if (widget.isPolygon) ...[
                  const SizedBox(height: 2),
                  Text(
                    'Area: ${widget.areaAcres!.toStringAsFixed(2)} acres  •  '
                    'Centre: ${widget.location.latitude.toStringAsFixed(4)}°N '
                    '${widget.location.longitude.toStringAsFixed(4)}°E',
                    style: const TextStyle(fontSize: 11, color: Color(0xFF4B7B55)),
                  ),
                ] else ...[
                  const SizedBox(height: 2),
                  Text(DateFormat('dd MMM yyyy  h:mm a').format(DateTime.now()),
                      style: const TextStyle(
                          fontSize: 11, color: Color(0xFF6B7280))),
                ],
              ])),
            ]),
          ),
          const SizedBox(height: 10),

          // ── Offline notice ─────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F8E9),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFA5D6A7)),
            ),
            child: const Row(children: [
              Icon(Icons.save_alt, size: 14, color: Color(0xFF2E7D32)),
              SizedBox(width: 8),
              Expanded(child: Text(
                'Data saved locally on your device — no internet needed.',
                style: TextStyle(fontSize: 11, color: Color(0xFF2E7D32)),
              )),
            ]),
          ),
          const SizedBox(height: 20),

          _lbl('Present Crop *'),
          _dd('Select crop', _crops, _presentCrop,
              (v) => setState(() => _presentCrop = v)),
          const SizedBox(height: 14),

          _lbl('Previous Crop'),
          _dd('Select previous crop', ['None', ..._crops], _previousCrop,
              (v) => setState(() => _previousCrop = v == 'None' ? null : v)),
          const SizedBox(height: 14),

          _lbl('Crop Stage'),
          _dd('Select stage', _stages, _cropStage,
              (v) => setState(() => _cropStage = v)),
          const SizedBox(height: 14),

          _lbl('Irrigation Source'),
          _dd('Select irrigation', _irrigationOptions, _irrigationSel,
              (v) => setState(() => _irrigationSel = v)),
          const SizedBox(height: 14),

          _lbl('Soil Type'),
          _dd('Select soil type', _soilTypes, _soilType,
              (v) => setState(() => _soilType = v)),
          const SizedBox(height: 14),

          _lbl('Phone (optional)'),
          TextField(
            controller: _phoneCtrl,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(hintText: '+91 9876543210'),
          ),
          const SizedBox(height: 14),

          _lbl('Observations'),
          TextField(
            controller: _notesCtrl, maxLines: 3,
            decoration: const InputDecoration(
                hintText: 'Any notes about the field condition...'),
          ),
          const SizedBox(height: 20),

          // ── Photos ─────────────────────────────────────────────────────────
          Row(children: [
            const Text('Photos', style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w600,
                color: Color(0xFF374151))),
            const SizedBox(width: 8),
            Text('${_tempPhotos.length}/5',
                style: const TextStyle(
                    fontSize: 12, color: Color(0xFF9E9E9E))),
            const Spacer(),
            const Icon(Icons.location_on, size: 13,
                color: Color(0xFF2E7D32)),
            const SizedBox(width: 3),
            const Text('GPS preserved',
                style: TextStyle(fontSize: 11, color: Color(0xFF2E7D32))),
          ]),
          const SizedBox(height: 10),

          Wrap(spacing: 10, runSpacing: 10, children: [
            ..._tempPhotos.asMap().entries.map((e) => _PhotoThumb(
              file: e.value,
              label: _labels[e.key],
              onLabelChange: (l) => setState(() => _labels[e.key] = l),
              onRemove: () => setState(() {
                _tempPhotos.removeAt(e.key);
                _labels.removeAt(e.key);
              }),
            )),
            if (_tempPhotos.length < 5)
              GestureDetector(
                onTap: _addPhoto,
                child: Container(
                  width: 90, height: 90,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE3F2FD),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: const Color(0xFF1565C0), width: 1.5),
                  ),
                  child: const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.camera_alt,
                          color: Color(0xFF1565C0), size: 28),
                      SizedBox(height: 4),
                      Text('Add Photo', style: TextStyle(
                          fontSize: 10, color: Color(0xFF1565C0))),
                    ]),
                ),
              ),
          ]),

          if (_error != null) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF3F3),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFFFCDD2)),
              ),
              child: Text(_error!,
                  style: const TextStyle(color: Colors.red, fontSize: 13)),
            ),
          ],

          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(width: 16, height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.save, size: 18),
            label: Text(_saving ? 'Saving...' : 'Save Record Locally'),
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1565C0),
                minimumSize: const Size.fromHeight(50)),
          ),
          const SizedBox(height: 20),
        ]),
      ),
    );
  }
}

class _PhotoThumb extends StatelessWidget {
  final XFile file;
  final String label;
  final ValueChanged<String> onLabelChange;
  final VoidCallback onRemove;
  const _PhotoThumb({required this.file, required this.label,
      required this.onLabelChange, required this.onRemove});

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 90,
    child: Column(children: [
      Stack(children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Image.file(File(file.path),
              width: 90, height: 90, fit: BoxFit.cover),
        ),
        Positioned(top: 4, right: 4,
          child: GestureDetector(
            onTap: onRemove,
            child: Container(
              width: 20, height: 20,
              decoration: const BoxDecoration(
                  color: Colors.red, shape: BoxShape.circle),
              child: const Icon(Icons.close, size: 14, color: Colors.white),
            ),
          ),
        ),
        Positioned(bottom: 4, left: 4,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(3),
            ),
            child: const Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.location_on, size: 8, color: Colors.white),
              SizedBox(width: 2),
              Text('GPS', style: TextStyle(fontSize: 7, color: Colors.white)),
            ]),
          ),
        ),
      ]),
      const SizedBox(height: 4),
      DropdownButton<String>(
        value: label, isExpanded: true, isDense: true,
        style: const TextStyle(fontSize: 9, color: Color(0xFF374151)),
        underline: const SizedBox(),
        items: _photoLabels.map((l) =>
            DropdownMenuItem(value: l, child: Text(l))).toList(),
        onChanged: (v) { if (v != null) onLabelChange(v); },
      ),
    ]),
  );
}
