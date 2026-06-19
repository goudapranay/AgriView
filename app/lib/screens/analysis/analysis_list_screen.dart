import 'package:flutter/material.dart';
import '../../services/api_service.dart';

class AnalysisListScreen extends StatefulWidget {
  const AnalysisListScreen({super.key});
  @override
  State<AnalysisListScreen> createState() => _AnalysisListScreenState();
}

class _AnalysisListScreenState extends State<AnalysisListScreen> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await ApiService().listAnalyses();
      setState(() { _items = data; _loading = false; });
    } catch (_) { setState(() => _loading = false); }
  }

  Future<void> _delete(String plotId) async {
    final ok = await showDialog<bool>(context: context,
        builder: (_) => AlertDialog(
          title: const Text('Delete analysis?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.pop(context, true),
                child: const Text('Delete', style: TextStyle(color: Colors.red))),
          ],
        ));
    if (ok == true) { await ApiService().deleteAnalysis(plotId); _load(); }
  }

  Color _healthColor(String? h) {
    switch (h) {
      case 'Good':     return const Color(0xFF2E7D32);
      case 'Moderate': return const Color(0xFFF57C00);
      case 'Sparse':   return const Color(0xFFE65100);
      default:         return Colors.red;
    }
  }

  String _healthEmoji(String? h) {
    switch (h) {
      case 'Good':     return '🟢';
      case 'Moderate': return '🟡';
      case 'Sparse':   return '🟠';
      default:         return '🔴';
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Field Analyses'),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)]),
    body: _loading
        ? const Center(child: CircularProgressIndicator(color: Color(0xFF2E7D32)))
        : _items.isEmpty
            ? const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text('🛰', style: TextStyle(fontSize: 48)),
                SizedBox(height: 12),
                Text('No analyses yet', style: TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w700)),
              ]))
            : ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _items.length,
                itemBuilder: (_, i) {
                  final a = _items[i];
                  final health = a['ndvi_health'] as String?;
                  return Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(children: [
                        Container(
                          width: 44, height: 44,
                          decoration: BoxDecoration(
                            color: const Color(0xFFE8F5E9),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Center(child: Text(_healthEmoji(health),
                              style: const TextStyle(fontSize: 22))),
                        ),
                        const SizedBox(width: 12),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(a['plot_id'] ?? '', style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w700)),
                          const SizedBox(height: 3),
                          Text(a['location_name'] ?? '',
                              style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
                          Text('Sow: ${a['sow_early'] ?? '—'} – ${a['sow_late'] ?? '—'}',
                              style: const TextStyle(fontSize: 11, color: Color(0xFF9E9E9E))),
                        ])),
                        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                            decoration: BoxDecoration(
                              color: _healthColor(health).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(health ?? '—', style: TextStyle(
                                fontSize: 11, color: _healthColor(health),
                                fontWeight: FontWeight.w600)),
                          ),
                          const SizedBox(height: 6),
                          GestureDetector(
                            onTap: () => _delete(a['plot_id']),
                            child: const Icon(Icons.delete_outline,
                                size: 18, color: Color(0xFFBDBDBD)),
                          ),
                        ]),
                      ]),
                    ),
                  );
                },
              ),
  );
}
