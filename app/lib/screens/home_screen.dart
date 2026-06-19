import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/api_service.dart';
import '../services/location_service.dart';
import '../services/local_db_service.dart';
import '../services/sync_service.dart';
import 'ground/ground_map_screen.dart';
import 'ground/ground_records_screen.dart';
import 'analysis/analysis_map_screen.dart';
import 'analysis/analysis_list_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _location = 'Detecting location...';
  List<Map<String, dynamic>> _recent = [];
  bool _loadingRecent = true;
  int _pendingCount   = 0;

  @override
  void initState() {
    super.initState();
    _detectLocation();
    _loadRecent();
    _autoSync();
    // Listen for connectivity changes
    SyncService().startListening(() {
      if (mounted) _loadRecent();
    });
  }

  Future<void> _autoSync() async {
    final pending = await LocalDbService().getPendingCount();
    if (mounted) setState(() => _pendingCount = pending);
    if (pending > 0) {
      await SyncService().syncPending();
      final remaining = await LocalDbService().getPendingCount();
      if (mounted) setState(() => _pendingCount = remaining);
    }
  }

  Future<void> _detectLocation() async {
    final pos = await LocationService().getCurrentLocation();
    if (pos != null && mounted) {
      setState(() => _location = '${pos.latitude.toStringAsFixed(4)}°N  ${pos.longitude.toStringAsFixed(4)}°E');
    } else if (mounted) {
      setState(() => _location = 'Location unavailable');
    }
  }

  Future<void> _loadRecent() async {
    setState(() => _loadingRecent = true);
    try {
      final ground   = await LocalDbService().getAllRecords();
      final pending  = await LocalDbService().getPendingCount();
      List<Map<String, dynamic>> analyses = [];
      try { analyses = await ApiService().listAnalyses(); } catch (_) {}
      final all = <Map<String, dynamic>>[];
      for (final g in ground) {
        all.add({'type': 'ground', 'plot_id': g.plotId,
            'crop': g.presentCrop, 'location': g.locationName ?? '',
            'date': g.createdAt, 'photos': g.photoPaths.length,
            'sync_status': g.syncStatus});
      }
      for (final a in analyses) {
        all.add({'type': 'analysis', 'plot_id': a['plot_id'],
            'crop': a['plot_id'], 'location': a['location_name'] ?? '',
            'date': a['analysed_at'] ?? '', 'ndvi_health': a['ndvi_health'] ?? ''});
      }
      all.sort((a, b) => (b['date'] as String).compareTo(a['date'] as String));
      setState(() {
        _recent        = all.take(5).toList();
        _pendingCount  = pending;
        _loadingRecent = false;
      });
    } catch (_) {
      setState(() => _loadingRecent = false);
    }
  }

  String _relativeDate(String dateStr) {
    try {
      final dt   = DateTime.parse(dateStr.replaceAll(' ', 'T'));
      final diff = DateTime.now().difference(dt);
      if (diff.inDays == 0) return 'Today ${DateFormat('h:mm a').format(dt)}';
      if (diff.inDays == 1) return 'Yesterday';
      return '${diff.inDays}d ago';
    } catch (_) { return dateStr; }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          color: const Color(0xFF2E7D32),
          onRefresh: _loadRecent,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(children: [
                  Container(
                    width: 44, height: 44,
                    decoration: BoxDecoration(
                      color: const Color(0xFF2E7D32),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Center(child: Text('🌾', style: TextStyle(fontSize: 24))),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('AgroSense', style: TextStyle(
                        fontSize: 20, fontWeight: FontWeight.w800, color: Color(0xFF1A3A1A))),
                    Row(children: [
                      const Icon(Icons.location_on, size: 13, color: Color(0xFF2E7D32)),
                      const SizedBox(width: 3),
                      Text(_location, style: const TextStyle(
                          fontSize: 12, color: Color(0xFF6B7280))),
                    ]),
                  ])),
                ]),

                const SizedBox(height: 28),

                // Module buttons
                Row(children: [
                  Expanded(child: _ModuleCard(
                    emoji: '📷',
                    title: 'Ground Data\nCollection',
                    subtitle: 'Crop, photos, field info',
                    color: const Color(0xFF1565C0),
                    bg: const Color(0xFFE3F2FD),
                    badge: _pendingCount > 0 ? '$_pendingCount pending' : null,
                    onTap: () => Navigator.push(context, MaterialPageRoute(
                        builder: (_) => const GroundMapScreen())).then((_) => _loadRecent()),
                  )),
                  const SizedBox(width: 14),
                  Expanded(child: _ModuleCard(
                    emoji: '🛰',
                    title: 'Field\nAnalysis',
                    subtitle: 'NDVI, weather, sowing',
                    color: const Color(0xFF2E7D32),
                    bg: const Color(0xFFE8F5E9),
                    badge: null,
                    onTap: () => Navigator.push(context, MaterialPageRoute(
                        builder: (_) => const AnalysisMapScreen())).then((_) => _loadRecent()),
                  )),
                ]),

                const SizedBox(height: 28),

                // Recent activity
                Row(children: [
                  const Text('Recent Activity', style: TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFF1A3A1A))),
                  const Spacer(),
                  Row(children: [
                    GestureDetector(
                      onTap: () => Navigator.push(context, MaterialPageRoute(
                          builder: (_) => const GroundRecordsScreen())).then((_) => _loadRecent()),
                      child: const Text('Ground', style: TextStyle(
                          fontSize: 12, color: Color(0xFF1565C0))),
                    ),
                    const Text('  ·  ', style: TextStyle(color: Color(0xFFBDBDBD))),
                    GestureDetector(
                      onTap: () => Navigator.push(context, MaterialPageRoute(
                          builder: (_) => const AnalysisListScreen())).then((_) => _loadRecent()),
                      child: const Text('Analysis', style: TextStyle(
                          fontSize: 12, color: Color(0xFF2E7D32))),
                    ),
                  ]),
                ]),

                const SizedBox(height: 10),

                if (_loadingRecent)
                  const Center(child: Padding(
                    padding: EdgeInsets.all(20),
                    child: CircularProgressIndicator(color: Color(0xFF2E7D32)),
                  ))
                else if (_recent.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFE8E4DC)),
                    ),
                    child: const Column(children: [
                      Text('🌱', style: TextStyle(fontSize: 40)),
                      SizedBox(height: 12),
                      Text('No records yet', style: TextStyle(
                          fontWeight: FontWeight.w700, color: Color(0xFF1A3A1A))),
                      SizedBox(height: 6),
                      Text('Start by collecting ground data\nor running a field analysis',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 13, color: Color(0xFF6B7280))),
                    ]),
                  )
                else
                  ..._recent.map((r) => _RecentCard(
                      record: r, relDate: _relativeDate(r['date']))),

                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ModuleCard extends StatelessWidget {
  final String emoji, title, subtitle;
  final Color color, bg;
  final String? badge;
  final VoidCallback onTap;
  const _ModuleCard({required this.emoji, required this.title,
      required this.subtitle, required this.color,
      required this.bg, required this.onTap, this.badge});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: bg, borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(emoji, style: const TextStyle(fontSize: 32)),
          const Spacer(),
          if (badge != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFFF57C00),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(badge!, style: const TextStyle(
                  fontSize: 10, color: Colors.white, fontWeight: FontWeight.w700)),
            ),
        ]),
        const SizedBox(height: 12),
        Text(title, style: TextStyle(
            fontSize: 15, fontWeight: FontWeight.w800, color: color)),
        const SizedBox(height: 4),
        Text(subtitle, style: const TextStyle(
            fontSize: 11, color: Color(0xFF6B7280))),
      ]),
    ),
  );
}

class _RecentCard extends StatelessWidget {
  final Map<String, dynamic> record;
  final String relDate;
  const _RecentCard({required this.record, required this.relDate});

  @override
  Widget build(BuildContext context) {
    final isGround = record['type'] == 'ground';
    final color    = isGround ? const Color(0xFF1565C0) : const Color(0xFF2E7D32);
    final bg       = isGround ? const Color(0xFFE3F2FD) : const Color(0xFFE8F5E9);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE8E4DC)),
      ),
      child: Row(children: [
        Container(
          width: 36, height: 36,
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
          child: Center(child: Text(isGround ? '📷' : '🛰',
              style: const TextStyle(fontSize: 18))),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(record['plot_id'] ?? '', style: const TextStyle(
              fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF1A3A1A))),
          const SizedBox(height: 2),
          Text(record['location'] ?? '', style: const TextStyle(
              fontSize: 11, color: Color(0xFF9E9E9E))),
        ])),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(relDate, style: const TextStyle(fontSize: 11, color: Color(0xFF9E9E9E))),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(4)),
            child: Text(
              isGround
                  ? (record['sync_status'] == kSynced ? '✅ Synced'
                      : record['sync_status'] == kFailed ? '❌ Failed'
                      : '⏳ Pending')
                  : record['ndvi_health'] ?? '',
              style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w600)),
          ),
        ]),
      ]),
    );
  }
}
