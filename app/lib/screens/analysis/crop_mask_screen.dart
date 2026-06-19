import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../models/models.dart';
import '../../services/export_service.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// CROP MASK GATE
// ═══════════════════════════════════════════════════════════════════════════════

class CropMaskScreen extends StatefulWidget {
  final List<List<double>> polygon;
  const CropMaskScreen({super.key, required this.polygon});
  @override
  State<CropMaskScreen> createState() => _CropMaskScreenState();
}

class _CropMaskScreenState extends State<CropMaskScreen> {
  CropMask? _mask;
  bool _loading = true;
  String? _error;

  @override
  void initState() { super.initState(); _check(); }

  Future<void> _check() async {
    setState(() { _loading = true; _error = null; });
    try {
      final m = await ApiService().checkCropland(widget.polygon);
      setState(() { _mask = m; _loading = false; });
    } catch (e) {
      setState(() { _error = 'Could not check cropland. Try again.'; _loading = false; });
    }
  }

  void _continue() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => FieldDetailsSheet(
        polygon: widget.polygon,
        cropMask: _mask!,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Cropland Check')),
      body: _loading
          ? const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
              CircularProgressIndicator(color: Color(0xFF2E7D32)),
              SizedBox(height: 16),
              Text('Checking ESA satellite data...'),
              SizedBox(height: 6),
              Text('WorldCover 10m resolution',
                  style: TextStyle(fontSize: 12, color: Color(0xFF9E9E9E))),
            ]))
          : _error != null
              ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.error_outline, size: 48, color: Color(0xFFBDBDBD)),
                  const SizedBox(height: 12),
                  Text(_error!),
                  const SizedBox(height: 16),
                  ElevatedButton(onPressed: _check, child: const Text('Retry')),
                ]))
              : Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(children: [
                    // Result card
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: _mask!.isCropland
                            ? const Color(0xFFE8F5E9) : const Color(0xFFFFF3F3),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: _mask!.isCropland
                            ? const Color(0xFFA5D6A7) : const Color(0xFFFFCDD2)),
                      ),
                      child: Column(children: [
                        Text(_mask!.isCropland ? '✅' : '🚫',
                            style: const TextStyle(fontSize: 48)),
                        const SizedBox(height: 12),
                        Text(
                          _mask!.isCropland
                              ? 'Cropland Confirmed'
                              : 'Not Agricultural Land',
                          style: TextStyle(
                            fontSize: 20, fontWeight: FontWeight.w800,
                            color: _mask!.isCropland
                                ? const Color(0xFF1B5E20) : Colors.red,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _mask!.isCropland
                              ? '${_mask!.cropPct.toStringAsFixed(0)}% of your boundary is active cropland'
                              : 'No cropland detected within your drawn boundary',
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 14, color: Color(0xFF374151)),
                        ),
                      ]),
                    ),

                    const SizedBox(height: 20),

                    // Land breakdown
                    _LandBreakdown(mask: _mask!),

                    const SizedBox(height: 8),
                    Text('Source: ${_mask!.source}',
                        style: const TextStyle(fontSize: 11, color: Color(0xFF9E9E9E))),

                    const Spacer(),

                    // Action button
                    if (_mask!.isCropland)
                      ElevatedButton.icon(
                        onPressed: _continue,
                        icon: const Icon(Icons.satellite_alt, size: 18),
                        label: const Text('Continue to Analysis'),
                        style: ElevatedButton.styleFrom(
                            minimumSize: const Size.fromHeight(52)),
                      )
                    else
                      Column(children: [
                        Text('Try moving your boundary to the actual field area.',
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280))),
                        const SizedBox(height: 12),
                        ElevatedButton.icon(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.undo, size: 18),
                          label: const Text('Redraw Boundary'),
                          style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                              minimumSize: const Size.fromHeight(52)),
                        ),
                      ]),
                  ]),
                ),
    );
  }
}

class _LandBreakdown extends StatelessWidget {
  final CropMask mask;
  const _LandBreakdown({required this.mask});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE8E4DC))),
    child: Column(children: [
      _Bar('🌾 Cropland',   mask.cropPct,   const Color(0xFF2E7D32)),
      _Bar('🌳 Tree Cover', mask.treePct,   const Color(0xFF1B5E20)),
      _Bar('🌿 Shrubland',  mask.shrubPct,  const Color(0xFF8BC34A)),
      _Bar('🐄 Grassland',  mask.grassPct,  const Color(0xFFFFC107)),
      _Bar('🏠 Built-up',   mask.builtupPct, const Color(0xFF9E9E9E)),
    ]),
  );
}

class _Bar extends StatelessWidget {
  final String label; final double pct; final Color color;
  const _Bar(this.label, this.pct, this.color);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(children: [
      SizedBox(width: 90, child: Text(label,
          style: const TextStyle(fontSize: 12, color: Color(0xFF374151)))),
      Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: pct / 100,
            backgroundColor: const Color(0xFFF0EDE8),
            valueColor: AlwaysStoppedAnimation(color),
            minHeight: 8,
          ))),
      const SizedBox(width: 8),
      SizedBox(width: 38, child: Text('${pct.toStringAsFixed(1)}%',
          style: const TextStyle(fontSize: 11, color: Color(0xFF9E9E9E)))),
    ]),
  );
}

// ═══════════════════════════════════════════════════════════════════════════════
// FIELD DETAILS BOTTOM SHEET
// ═══════════════════════════════════════════════════════════════════════════════

class FieldDetailsSheet extends StatefulWidget {
  final List<List<double>> polygon;
  final CropMask cropMask;
  const FieldDetailsSheet({super.key, required this.polygon, required this.cropMask});
  @override
  State<FieldDetailsSheet> createState() => _FieldDetailsSheetState();
}

class _FieldDetailsSheetState extends State<FieldDetailsSheet> {
  final _phoneCtrl = TextEditingController();
  String? _selectedCrop;

  final _crops = ['Rice','Wheat','Maize','Cotton','Chickpea',
      'Sorghum','Groundnut','Sunflower','Soybean','Other'];

  void _proceed(BuildContext ctx, {bool skip = false}) {
    Navigator.pop(ctx); // close sheet
    Navigator.push(ctx, MaterialPageRoute(
        builder: (_) => AnalysisLoadingScreen(
          polygon:     widget.polygon,
          cropMask:    widget.cropMask,
          phone:       skip ? null : _phoneCtrl.text.trim().isEmpty ? null : _phoneCtrl.text.trim(),
          presentCrop: skip ? null : _selectedCrop,
        )));
  }

  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
    decoration: const BoxDecoration(
      color: Color(0xFFF7F6F2),
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Center(child: Container(width: 40, height: 4,
            decoration: BoxDecoration(color: const Color(0xFFE0E0E0),
                borderRadius: BorderRadius.circular(2)))),
        const SizedBox(height: 16),
        const Text('Field Details', style: TextStyle(
            fontSize: 18, fontWeight: FontWeight.w700, color: Color(0xFF1A3A1A))),
        const Text('Optional — helps identify the record',
            style: TextStyle(fontSize: 12, color: Color(0xFF9E9E9E))),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          value: _selectedCrop,
          decoration: const InputDecoration(hintText: 'Present crop (optional)'),
          items: _crops.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
          onChanged: (v) => setState(() => _selectedCrop = v),
        ),
        const SizedBox(height: 12),
        TextField(controller: _phoneCtrl, keyboardType: TextInputType.phone,
            decoration: const InputDecoration(hintText: 'Phone number (optional)')),
        const SizedBox(height: 20),
        Row(children: [
          Expanded(child: OutlinedButton(
            onPressed: () => _proceed(context, skip: true),
            style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                side: const BorderSide(color: Color(0xFFBDBDBD)),
                foregroundColor: const Color(0xFF6B7280),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            child: const Text('Skip'),
          )),
          const SizedBox(width: 12),
          Expanded(flex: 2, child: ElevatedButton(
            onPressed: () => _proceed(context),
            child: const Text('Save & Analyse'),
          )),
        ]),
      ]),
    ),
  );
}

// ═══════════════════════════════════════════════════════════════════════════════
// LOADING SCREEN
// ═══════════════════════════════════════════════════════════════════════════════

class AnalysisLoadingScreen extends StatefulWidget {
  final List<List<double>> polygon;
  final CropMask cropMask;
  final String? phone, presentCrop;
  const AnalysisLoadingScreen({super.key, required this.polygon,
      required this.cropMask, this.phone, this.presentCrop});
  @override
  State<AnalysisLoadingScreen> createState() => _AnalysisLoadingScreenState();
}

class _AnalysisLoadingScreenState extends State<AnalysisLoadingScreen> {
  @override
  void initState() { super.initState(); _run(); }

  Future<void> _run() async {
    try {
      final result = await ApiService().runAnalysis(
        polygon:      widget.polygon,
        phone:        widget.phone,
        presentCrop:  widget.presentCrop,
      );
      if (mounted) {
        Navigator.pushReplacement(context, MaterialPageRoute(
            builder: (_) => AnalysisResultsScreen(analysis: result)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Analysis failed: $e')));
        Navigator.pop(context);
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Text('🛰', style: TextStyle(fontSize: 56)),
      const SizedBox(height: 20),
      const CircularProgressIndicator(color: Color(0xFF2E7D32)),
      const SizedBox(height: 20),
      const Text('Fetching satellite data...',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF1A3A1A))),
      const SizedBox(height: 8),
      Text('NDVI  •  Weather  •  Sowing window',
          style: TextStyle(fontSize: 13, color: Colors.grey[500])),
      const SizedBox(height: 6),
      Text('This may take 10–20 seconds',
          style: TextStyle(fontSize: 12, color: Colors.grey[400])),
    ])),
  );
}

// ═══════════════════════════════════════════════════════════════════════════════
// RESULTS SCREEN
// ═══════════════════════════════════════════════════════════════════════════════

class AnalysisResultsScreen extends StatefulWidget {
  final FieldAnalysis analysis;
  const AnalysisResultsScreen({super.key, required this.analysis});
  @override
  State<AnalysisResultsScreen> createState() => _AnalysisResultsScreenState();
}

class _AnalysisResultsScreenState extends State<AnalysisResultsScreen> {
  bool _exporting = false;


  Future<void> _exportReport() async {
    setState(() => _exporting = true);
    final result = await ExportService().exportAnalysisReport(widget.analysis);
    setState(() => _exporting = false);
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
          Text(result.success ? 'Report Saved' : 'Save Failed',
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
                color: const Color(0xFFE3F2FD),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(children: [
                const Icon(Icons.description,
                    size: 14, color: Color(0xFF1565C0)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(result.filePath!,
                      style: const TextStyle(
                          fontSize: 10,
                          color: Color(0xFF1565C0),
                          fontFamily: 'monospace')),
                ),
              ]),
            ),
            const SizedBox(height: 8),
            const Text(
              'Open the .html file in any browser on your phone to view the full report.',
              style: TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
            ),
          ],
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK')),
        ],
      ),
    );
  }

  Color _ndviColor(String health) {
    switch (health) {
      case 'Good':     return const Color(0xFF2E7D32);
      case 'Moderate': return const Color(0xFFF57C00);
      case 'Sparse':   return const Color(0xFFE65100);
      default:         return Colors.red;
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.analysis;
    return Scaffold(
      appBar: AppBar(title: Text(a.plotId)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

          // Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF1B5E20), Color(0xFF2E7D32)],
                begin: Alignment.topLeft, end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(a.plotId, style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white))),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(a.gee ? '🛰 Live' : '🔬 Simulated',
                      style: const TextStyle(fontSize: 11, color: Colors.white)),
                ),
              ]),
              const SizedBox(height: 6),
              Text('📍 ${a.locationName}', style: const TextStyle(
                  fontSize: 13, color: Colors.white70)),
              const SizedBox(height: 4),
              Row(children: [
                Text('${a.areaAcres.toStringAsFixed(2)} acres',
                    style: const TextStyle(fontSize: 13, color: Colors.white70)),
                const Text('  •  ', style: TextStyle(color: Colors.white38)),
                Text('${a.areaHectares.toStringAsFixed(2)} ha',
                    style: const TextStyle(fontSize: 13, color: Colors.white70)),
                const Text('  •  ', style: TextStyle(color: Colors.white38)),
                Text('${a.cropMask.cropPct.toStringAsFixed(0)}% cropland',
                    style: const TextStyle(fontSize: 13, color: Colors.white70)),
              ]),
            ]),
          ),

          const SizedBox(height: 20),

          // ── SECTION A: NDVI ─────────────────────────────────────────────────
          _SectionHeader('🛰 Vegetation Health (NDVI)'),
          const SizedBox(height: 12),

          // Health badge
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: _ndviColor(a.ndvi.health).withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: _ndviColor(a.ndvi.health).withOpacity(0.3)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(_ndviHealthEmoji(a.ndvi.health),
                    style: const TextStyle(fontSize: 16)),
                const SizedBox(width: 6),
                Text(a.ndvi.health, style: TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w700,
                    color: _ndviColor(a.ndvi.health))),
              ]),
            ),
            const SizedBox(width: 10),
            Text('Peak: ${a.ndvi.peakMonth} (${a.ndvi.peak.toStringAsFixed(2)})',
                style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280))),
          ]),

          const SizedBox(height: 12),

          // NDVI Chart
          _NdviChart(series: a.ndvi.series),
          const SizedBox(height: 10),

          // NDVI legend
          Wrap(spacing: 10, runSpacing: 6, children: const [
            _NdviLegend(Color(0xFF2E7D32), '0.6+ Good'),
            _NdviLegend(Color(0xFFF57C00), '0.4 Moderate'),
            _NdviLegend(Color(0xFFE65100), '0.2 Sparse'),
            _NdviLegend(Colors.red,        '<0.2 Poor'),
          ]),

          const SizedBox(height: 10),

          // Interpretation
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF5F5F0),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(a.ndvi.interpretation,
                style: const TextStyle(fontSize: 13, color: Color(0xFF374151), height: 1.5)),
          ),

          const SizedBox(height: 24),

          // ── SECTION B: Weather ──────────────────────────────────────────────
          _SectionHeader('🌦 7-Day Weather Forecast'),
          const SizedBox(height: 12),

          // Today hero
          if (a.weather.isNotEmpty) ...[
            _WeatherHero(day: a.weather.first),
            const SizedBox(height: 10),
          ],

          // Daily strip
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: a.weather.asMap().entries.map((e) =>
                _WeatherDayChip(day: e.value, isToday: e.key == 0)).toList()),
          ),

          const SizedBox(height: 10),

          // Farming note
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF8E1),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFFFE0B2)),
            ),
            child: Row(children: [
              const Icon(Icons.info_outline, color: Color(0xFFF57C00), size: 16),
              const SizedBox(width: 8),
              Expanded(child: Text(a.farmNote,
                  style: const TextStyle(fontSize: 13, color: Color(0xFF374151)))),
            ]),
          ),

          const SizedBox(height: 24),

          // ── SECTION C: Sowing Window ────────────────────────────────────────
          _SectionHeader('🗓 Optimal Sowing Window'),
          const SizedBox(height: 12),

          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE8E4DC)),
            ),
            child: Column(children: [
              // Three columns
              Row(children: [
                Expanded(child: _SowingCol('Early', a.sowing.early, const Color(0xFF8BC34A))),
                Container(width: 1, height: 60, color: const Color(0xFFE8E4DC)),
                Expanded(child: _SowingCol('Peak', a.sowing.peak, const Color(0xFF2E7D32))),
                Container(width: 1, height: 60, color: const Color(0xFFE8E4DC)),
                Expanded(child: _SowingCol('Late', a.sowing.late, const Color(0xFFF57C00))),
              ]),

              const SizedBox(height: 14),

              // Visual bar
              _SowingBar(early: a.sowing.early, peak: a.sowing.peak, late: a.sowing.late),

              const SizedBox(height: 14),

              // Reason
              Text(a.sowing.reason, textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 13, color: Color(0xFF374151), height: 1.5)),
            ]),
          ),

          const SizedBox(height: 24),

          // ── Footer ──────────────────────────────────────────────────────────
          const Divider(color: Color(0xFFE8E4DC)),
          const SizedBox(height: 8),
          const Text('Data: Sentinel-2 + CHIRPS + MODIS + ESA WorldCover',
              style: TextStyle(fontSize: 11, color: Color(0xFF9E9E9E))),
          Text('Analysed: ${a.analysedAt}',
              style: const TextStyle(fontSize: 11, color: Color(0xFF9E9E9E))),

          const SizedBox(height: 16),

          // ── Save Report to device ────────────────────────────────────────
          ElevatedButton.icon(
            onPressed: _exporting ? null : _exportReport,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1565C0),
              foregroundColor: Colors.white,
            ),
            icon: _exporting
                ? const SizedBox(width: 16, height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.download, size: 18),
            label: Text(_exporting ? 'Saving Report...' : '📄 Save Report to Device'),
          ),


          const SizedBox(height: 30),
        ]),
      ),
    );
  }

  String _ndviHealthEmoji(String health) {
    switch (health) {
      case 'Good':     return '🟢';
      case 'Moderate': return '🟡';
      case 'Sparse':   return '🟠';
      default:         return '🔴';
    }
  }
}

// ── NDVI Chart ─────────────────────────────────────────────────────────────────

class _NdviChart extends StatelessWidget {
  final List<NdviPoint> series;
  const _NdviChart({required this.series});

  Color _dotColor(double v) {
    if (v >= 0.6) return const Color(0xFF2E7D32);
    if (v >= 0.4) return const Color(0xFFF57C00);
    if (v >= 0.2) return const Color(0xFFE65100);
    return Colors.red;
  }

  @override
  Widget build(BuildContext context) {
    final spots = series.asMap().entries
        .where((e) => e.value.ndvi != null)
        .map((e) => FlSpot(e.key.toDouble(), e.value.ndvi!))
        .toList();

    return Container(
      height: 200,
      padding: const EdgeInsets.fromLTRB(4, 12, 16, 4),
      decoration: BoxDecoration(color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE8E4DC))),
      child: LineChart(LineChartData(
        minY: 0, maxY: 1.0,
        gridData: FlGridData(show: true, drawVerticalLine: false,
            horizontalInterval: 0.2,
            getDrawingHorizontalLine: (_) =>
                FlLine(color: const Color(0xFFF0EDE8), strokeWidth: 1)),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true,
              reservedSize: 36, interval: 0.2,
              getTitlesWidget: (v, _) => Text(v.toStringAsFixed(1),
                  style: const TextStyle(fontSize: 10, color: Color(0xFF9E9E9E))))),
          bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true,
              reservedSize: 24,
              getTitlesWidget: (v, _) {
                final i = v.toInt();
                if (i < 0 || i >= series.length) return const SizedBox();
                return Text(series[i].month,
                    style: const TextStyle(fontSize: 9, color: Color(0xFF9E9E9E)));
              })),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots, isCurved: true,
            color: const Color(0xFF2E7D32), barWidth: 2.5,
            dotData: FlDotData(show: true,
                getDotPainter: (s, _, __, ___) => FlDotCirclePainter(
                    radius: 4.5, color: _dotColor(s.y),
                    strokeWidth: 1.5, strokeColor: Colors.white)),
            belowBarData: BarAreaData(show: true, color: const Color(0x1A2E7D32)),
          ),
        ],
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipItems: (spots) => spots.map((s) {
              final i = s.spotIndex;
              return LineTooltipItem(
                '${series[i].month}\nNDVI: ${s.y.toStringAsFixed(3)}',
                const TextStyle(fontSize: 11, color: Colors.white),
              );
            }).toList(),
          ),
        ),
      )),
    );
  }
}

// ── Weather widgets ────────────────────────────────────────────────────────────

class _WeatherHero extends StatelessWidget {
  final WeatherDay day;
  const _WeatherHero({required this.day});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
          colors: [Color(0xFF1565C0), Color(0xFF1976D2)],
          begin: Alignment.topLeft, end: Alignment.bottomRight),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Row(children: [
      Text(day.emoji, style: const TextStyle(fontSize: 40)),
      const SizedBox(width: 16),
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${day.tempMax.toStringAsFixed(0)}°C',
            style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w800, color: Colors.white)),
        Text('${day.tempMin.toStringAsFixed(0)}° low  •  ${day.desc}',
            style: const TextStyle(fontSize: 13, color: Colors.white70)),
        if (day.rainMm > 0)
          Text('💧 ${day.rainMm.toStringAsFixed(1)}mm rain',
              style: const TextStyle(fontSize: 12, color: Colors.lightBlueAccent)),
      ]),
    ]),
  );
}

class _WeatherDayChip extends StatelessWidget {
  final WeatherDay day; final bool isToday;
  const _WeatherDayChip({required this.day, required this.isToday});
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(right: 8),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(
      color: isToday ? const Color(0xFFE3F2FD) : Colors.white,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: isToday
          ? const Color(0xFF90CAF9) : const Color(0xFFE8E4DC)),
    ),
    child: Column(children: [
      Text(isToday ? 'Today' : day.day,
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
              color: isToday ? const Color(0xFF1565C0) : const Color(0xFF374151))),
      const SizedBox(height: 4),
      Text(day.emoji, style: const TextStyle(fontSize: 20)),
      const SizedBox(height: 4),
      Text('${day.tempMax.toStringAsFixed(0)}°',
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
              color: Color(0xFF374151))),
      Text('${day.tempMin.toStringAsFixed(0)}°',
          style: const TextStyle(fontSize: 11, color: Color(0xFF9E9E9E))),
      if (day.rainMm > 0) ...[
        const SizedBox(height: 2),
        Text('${day.rainMm.toStringAsFixed(0)}mm',
            style: const TextStyle(fontSize: 10, color: Color(0xFF42A5F5))),
      ],
    ]),
  );
}

// ── Sowing Window widgets ──────────────────────────────────────────────────────

class _SowingCol extends StatelessWidget {
  final String label, month; final Color color;
  const _SowingCol(this.label, this.month, this.color);
  @override
  Widget build(BuildContext context) => Column(children: [
    Text(label, style: const TextStyle(fontSize: 11, color: Color(0xFF9E9E9E))),
    const SizedBox(height: 6),
    Text(month, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: color)),
  ]);
}

class _SowingBar extends StatelessWidget {
  final String early, peak, late;
  const _SowingBar({required this.early, required this.peak, required this.late});
  static const _months = ['Jan','Feb','Mar','Apr','May','Jun',
                          'Jul','Aug','Sep','Oct','Nov','Dec'];
  @override
  Widget build(BuildContext context) {
    return Row(children: _months.map((m) {
      final isEarly = m == early;
      final isPeak  = m == peak;
      final isLate  = m == late;
      final active  = isEarly || isPeak || isLate;
      final color   = isPeak ? const Color(0xFF2E7D32)
          : isEarly ? const Color(0xFF8BC34A)
          : isLate  ? const Color(0xFFF57C00)
          : const Color(0xFFF0EDE8);
      return Expanded(child: Column(children: [
        Container(height: 12, color: color),
        const SizedBox(height: 4),
        if (active)
          Text(m, style: TextStyle(fontSize: 8, fontWeight: FontWeight.w600,
              color: isPeak ? const Color(0xFF2E7D32) : const Color(0xFF9E9E9E)))
        else
          const SizedBox(height: 12),
      ]));
    }).toList());
  }
}

// ── Shared widgets ─────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String text;
  const _SectionHeader(this.text);
  @override
  Widget build(BuildContext context) => Text(text,
      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700,
          color: Color(0xFF1A3A1A)));
}

class _NdviLegend extends StatelessWidget {
  final Color color; final String label;
  const _NdviLegend(this.color, this.label);
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
    Container(width: 10, height: 10,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
    const SizedBox(width: 4),
    Text(label, style: const TextStyle(fontSize: 11, color: Color(0xFF6B7280))),
  ]);
}
