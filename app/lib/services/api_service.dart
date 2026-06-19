import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/models.dart';

const String kBaseUrl = 'http://10.0.2.2:8000';
// const String kBaseUrl = 'https://agrosense-6wbu.onrender.com';

class ApiService {
  static final ApiService _i = ApiService._();
  factory ApiService() => _i;
  ApiService._();
  final _client = http.Client();

  Future<Map<String, dynamic>> _post(String path, Map body) async {
    final res = await _client.post(
      Uri.parse('$kBaseUrl$path'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    ).timeout(const Duration(seconds: 45));
    if (res.statusCode == 200) return jsonDecode(res.body);
    throw Exception('${res.statusCode}: ${res.body}');
  }

  Future<dynamic> _get(String path) async {
    final res = await _client
        .get(Uri.parse('$kBaseUrl$path'))
        .timeout(const Duration(seconds: 15));
    if (res.statusCode == 200) return jsonDecode(res.body);
    throw Exception('${res.statusCode}');
  }

  Future<dynamic> _delete(String path) async {
    final res = await _client
        .delete(Uri.parse('$kBaseUrl$path'))
        .timeout(const Duration(seconds: 10));
    if (res.statusCode == 200) return jsonDecode(res.body);
    throw Exception('${res.statusCode}');
  }

  // Ground
  Future<Map<String, dynamic>> saveGroundRecord({
    required String presentCrop,
    String? previousCrop, String? cropStage,
    String? irrigation, String? soilType,
    String? phone, String? observations,
    required double latitude, required double longitude,
    List<String> photos = const [],
    String? existingPlotId,
  }) async {
    return await _post('/ground/save', {
      'present_crop':  presentCrop,
      'previous_crop': previousCrop,
      'crop_stage':    cropStage,
      'irrigation':    irrigation,
      'soil_type':     soilType,
      'phone':         phone,
      'observations':  observations,
      'latitude':      latitude,
      'longitude':     longitude,
      'photos':        photos,
      if (existingPlotId != null) 'plot_id': existingPlotId,
    });
  }

  Future<List<GroundRecord>> listGroundRecords() async {
    final data = await _get('/ground');
    return (data as List).map((e) => GroundRecord.fromJson(e)).toList();
  }

  Future<void> deleteGroundRecord(String plotId) => _delete('/ground/$plotId');

  // Analysis
  Future<CropMask> checkCropland(List<List<double>> polygon) async {
    return CropMask.fromJson(
        await _post('/analysis/check-cropland', {'polygon': polygon}));
  }

  Future<FieldAnalysis> runAnalysis({
    required List<List<double>> polygon,
    String? locationName, String? phone, String? presentCrop,
  }) async {
    return FieldAnalysis.fromJson(await _post('/analysis/run', {
      'polygon':       polygon,
      'location_name': locationName,
      'phone':         phone,
      'present_crop':  presentCrop ?? 'Field',
    }));
  }

  Future<Map<String, dynamic>> saveToDrive(String plotId) async {
    return await _post('/analysis/save-to-drive', {'plot_id': plotId});
  }

  Future<List<Map<String, dynamic>>> listAnalyses() async {
    final data = await _get('/analysis');
    return List<Map<String, dynamic>>.from(data);
  }

  Future<void> deleteAnalysis(String plotId) => _delete('/analysis/$plotId');
}
