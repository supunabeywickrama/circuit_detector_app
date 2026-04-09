// lib/pages/history_page.dart
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../theme/gradients.dart';

/// HistoryPage with persistent storage (history.json), premium card design.
class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  List<Map<String, dynamic>> _historyList = [];
  List<Map<String, dynamic>> _filteredList = [];
  bool _loading = true;
  String _query = '';
  _FilterMode _filterMode = _FilterMode.all;
  bool _sortNewestFirst = true;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    setState(() => _loading = true);
    _historyList = await HistoryStorage.loadAll();
    _applyFilters();
    setState(() => _loading = false);
  }

  void _applyFilters() {
    final q = _query.trim().toLowerCase();
    _filteredList = _historyList.where((entry) {
      if (_filterMode == _FilterMode.resistor) {
        final List<dynamic> r = entry['resistors'] ?? [];
        if (r.isEmpty) return false;
      } else if (_filterMode == _FilterMode.ic) {
        final List<dynamic> ics = entry['ics'] ?? [];
        if (ics.isEmpty) return false;
      }
      if (q.isEmpty) return true;
      final ts = (entry['timestamp'] ?? '').toString().toLowerCase();
      final rlist = (entry['resistors'] ?? []).join(' ').toLowerCase();
      final ics = (entry['ics'] ?? []).join(' ').toLowerCase();
      return ts.contains(q) || rlist.contains(q) || ics.contains(q);
    }).toList();

    _filteredList.sort((a, b) {
      final ta = DateTime.tryParse(a['timestamp'] ?? '') ?? DateTime(2000);
      final tb = DateTime.tryParse(b['timestamp'] ?? '') ?? DateTime(2000);
      return _sortNewestFirst ? tb.compareTo(ta) : ta.compareTo(tb);
    });
  }

  void _onSearchChanged(String value) {
    setState(() {
      _query = value;
      _applyFilters();
    });
  }

  void _changeFilter(_FilterMode mode) {
    setState(() {
      _filterMode = mode;
      _applyFilters();
    });
  }

  Future<void> _deleteEntryAt(int index) async {
    final entry = _filteredList[index];
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Entry'),
        content: const Text('Are you sure you want to delete this record?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await HistoryStorage.deleteById(entry['id']);
    await _loadHistory();
  }

  Future<void> _clearAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear History'),
        content: const Text('Delete all scan history? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clear All'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await HistoryStorage.clearAll();
    await _loadHistory();
  }

  Future<void> _exportEntry(Map<String, dynamic> entry) async {
    final exportedPath = await HistoryStorage.exportEntryToFile(entry);
    if (exportedPath != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Exported to: $exportedPath')));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Export failed.')));
    }
  }

  String _formatTimestamp(String? raw) {
    if (raw == null || raw.isEmpty) return 'Unknown';
    final dt = DateTime.tryParse(raw);
    if (dt == null) return raw;
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dt.day}/${dt.month}/${dt.year}';
  }

  int _totalComponents(Map<String, dynamic> entry) {
    final r = (entry['resistors'] as List<dynamic>?)?.length ?? 0;
    final i = (entry['ics'] as List<dynamic>?)?.length ?? 0;
    final ac = (entry['all_components'] as List<dynamic>?)?.length;
    return ac ?? (r + i);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Scan History'),
        leading: _glassBack(context),
        actions: [
          if (_historyList.isNotEmpty)
            _GlassIconBtn(
              icon: Icons.delete_sweep_rounded,
              onPressed: _clearAll,
            ),
          const SizedBox(width: 4),
          _GlassIconBtn(
            icon: _sortNewestFirst ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded,
            onPressed: () => setState(() {
              _sortNewestFirst = !_sortNewestFirst;
              _applyFilters();
            }),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: isDark ? AppGradients.darkBackground : AppGradients.surfaceLight,
        ),
        child: SafeArea(
          child: Column(
            children: [
              // ── Search bar ────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                          child: TextField(
                            onChanged: _onSearchChanged,
                            decoration: InputDecoration(
                              prefixIcon: Icon(Icons.search_rounded,
                                  color: isDark ? AppColors.textSecondary : AppColors.textDarkSecondary),
                              hintText: 'Search scans...',
                              filled: true,
                              fillColor: isDark
                                  ? Colors.white.withOpacity(0.06)
                                  : Colors.white.withOpacity(0.7),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(AppRadius.md),
                                borderSide: BorderSide.none,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    // Filter chips
                    _FilterChip(
                      label: _filterMode == _FilterMode.all
                          ? 'All'
                          : _filterMode == _FilterMode.resistor
                              ? 'R'
                              : 'IC',
                      isDark: isDark,
                      onTap: () {
                        final modes = _FilterMode.values;
                        final next = modes[(_filterMode.index + 1) % modes.length];
                        _changeFilter(next);
                      },
                    ),
                  ],
                ),
              ),

              // ── List ──────────────────────────────────────────────
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _filteredList.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.history_rounded,
                                    size: 56,
                                    color: isDark ? AppColors.textSecondary : Colors.grey.shade400),
                                const SizedBox(height: 12),
                                Text(
                                  'No scans yet',
                                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                        color: isDark ? AppColors.textSecondary : Colors.grey,
                                      ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Your detection history will appear here.',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                            itemCount: _filteredList.length,
                            itemBuilder: (context, index) => _buildCard(index, isDark),
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCard(int index, bool isDark) {
    final entry = _filteredList[index];
    final thumbnail = entry['thumbnailPath'] as String?;
    final resistors = (entry['resistors'] as List<dynamic>?)?.cast<String>() ?? <String>[];
    final ics = (entry['ics'] as List<dynamic>?)?.cast<String>() ?? <String>[];
    final total = _totalComponents(entry);
    final timeStr = _formatTimestamp(entry['timestamp']?.toString());

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Dismissible(
        key: Key(entry['id'].toString()),
        direction: DismissDirection.endToStart,
        background: Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 24),
          decoration: BoxDecoration(
            color: AppColors.error.withOpacity(0.15),
            borderRadius: BorderRadius.circular(AppRadius.lg),
          ),
          child: const Icon(Icons.delete_rounded, color: AppColors.error, size: 28),
        ),
        confirmDismiss: (_) async {
          await _deleteEntryAt(index);
          return false; // we handle deletion ourselves
        },
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
            child: Container(
              decoration: BoxDecoration(
                color: isDark ? Colors.white.withOpacity(0.06) : Colors.white.withOpacity(0.80),
                borderRadius: BorderRadius.circular(AppRadius.lg),
                border: Border.all(
                  color: isDark ? Colors.white.withOpacity(0.08) : Colors.grey.shade200,
                ),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(AppRadius.lg),
                onTap: () => _viewDetails(entry),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      // Thumbnail
                      ClipRRect(
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        child: thumbnail != null && File(thumbnail).existsSync()
                            ? Image.file(File(thumbnail), width: 60, height: 60, fit: BoxFit.cover)
                            : Container(
                                width: 60,
                                height: 60,
                                decoration: BoxDecoration(
                                  gradient: AppGradients.cyanBlue,
                                  borderRadius: BorderRadius.circular(AppRadius.md),
                                ),
                                child: const Icon(Icons.memory_rounded, color: Colors.white, size: 28),
                              ),
                      ),
                      const SizedBox(width: 14),
                      // Info
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  '$total components',
                                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                        fontWeight: FontWeight.w600,
                                      ),
                                ),
                                const Spacer(),
                                Text(
                                  timeStr,
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                if (resistors.isNotEmpty)
                                  _MiniTag(
                                    label: '${resistors.length} R',
                                    color: AppColors.accentAmber,
                                    isDark: isDark,
                                  ),
                                if (resistors.isNotEmpty && ics.isNotEmpty) const SizedBox(width: 6),
                                if (ics.isNotEmpty)
                                  _MiniTag(
                                    label: '${ics.length} IC',
                                    color: AppColors.primaryBlue,
                                    isDark: isDark,
                                  ),
                                if (resistors.isEmpty && ics.isEmpty)
                                  _MiniTag(
                                    label: 'Detected',
                                    color: AppColors.accentEmerald,
                                    isDark: isDark,
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Actions
                      PopupMenuButton<String>(
                        icon: Icon(Icons.more_vert_rounded,
                            color: isDark ? AppColors.textSecondary : Colors.grey),
                        onSelected: (v) async {
                          if (v == 'export') await _exportEntry(entry);
                          if (v == 'delete') await _deleteEntryAt(index);
                        },
                        itemBuilder: (_) => [
                          const PopupMenuItem(value: 'export', child: Text('Export JSON')),
                          const PopupMenuItem(value: 'delete', child: Text('Delete')),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _viewDetails(Map<String, dynamic> entry) async {
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Scan: ${_formatTimestamp(entry['timestamp']?.toString())}'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (entry['thumbnailPath'] != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  child: Image.file(File(entry['thumbnailPath']), height: 150, fit: BoxFit.cover),
                ),
              const SizedBox(height: 12),
              Text('🟡 Resistors: ${(entry['resistors'] as List<dynamic>?)?.join(', ') ?? 'none'}'),
              Text('🔵 ICs: ${(entry['ics'] as List<dynamic>?)?.join(', ') ?? 'none'}'),
              if (entry['all_components'] != null) ...[
                const SizedBox(height: 8),
                _buildComponentSummary(entry['all_components']),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
        ],
      ),
    );
  }

  Widget _buildComponentSummary(dynamic rawList) {
    if (rawList is! List) return const SizedBox();
    final Map<String, int> counts = {};
    for (final item in rawList) {
      if (item is Map) {
        final t = (item['type'] ?? item['label'] ?? '').toString();
        if (t.isNotEmpty) counts[t] = (counts[t] ?? 0) + 1;
      }
    }
    if (counts.isEmpty) return const Text('No components');
    final entries = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('📦 Components:', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        ...entries.map((e) => Text('• ${e.key} — ${e.value}')),
      ],
    );
  }

  Widget _glassBack(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 12),
      child: GestureDetector(
        onTap: () => Navigator.pop(context),
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.10),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white.withOpacity(0.12)),
          ),
          child: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 16),
        ),
      ),
    );
  }
}

// ── Mini tag widget ─────────────────────────────────────────────────────────
class _MiniTag extends StatelessWidget {
  final String label;
  final Color color;
  final bool isDark;
  const _MiniTag({required this.label, required this.color, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(isDark ? 0.15 : 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600),
      ),
    );
  }
}

// ── Filter chip ─────────────────────────────────────────────────────────────
class _FilterChip extends StatelessWidget {
  final String label;
  final bool isDark;
  final VoidCallback onTap;
  const _FilterChip({required this.label, required this.isDark, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withOpacity(0.06) : Colors.white.withOpacity(0.7),
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(
            color: isDark ? AppColors.primaryCyan.withOpacity(0.3) : AppColors.primaryBlue.withOpacity(0.3),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isDark ? AppColors.primaryCyan : AppColors.primaryBlue,
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}

// ── Glass icon button for AppBar ────────────────────────────────────────────
class _GlassIconBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;
  const _GlassIconBtn({required this.icon, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.10),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white.withOpacity(0.12)),
        ),
        child: Icon(icon, color: Colors.white.withOpacity(0.8), size: 18),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  HistoryStorage — local JSON persistence (unchanged logic, kept in place)
// ═══════════════════════════════════════════════════════════════════════════
class HistoryStorage {
  static const _fileName = 'history.json';
  static const _imagesDir = 'history_images';

  static Future<List<Map<String, dynamic>>> loadAll() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File(p.join(dir.path, _fileName));
      if (!await file.exists()) return [];
      final txt = await file.readAsString();
      final data = jsonDecode(txt) as List<dynamic>;
      final out = data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      out.sort((a, b) {
        final ta = DateTime.tryParse(a['timestamp'] ?? '') ?? DateTime(2000);
        final tb = DateTime.tryParse(b['timestamp'] ?? '') ?? DateTime(2000);
        return tb.compareTo(ta);
      });
      return out;
    } catch (e) {
      debugPrint('[HistoryStorage] loadAll error: $e');
      return [];
    }
  }

  static Future<bool> _saveAll(List<Map<String, dynamic>> list) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File(p.join(dir.path, _fileName));
      await file.writeAsString(jsonEncode(list));
      return true;
    } catch (e) {
      debugPrint('[HistoryStorage] _saveAll error: $e');
      return false;
    }
  }

  static Future<bool> addEntry(Map<String, dynamic> entry) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final imagesDir = Directory(p.join(dir.path, _imagesDir));
      if (!await imagesDir.exists()) await imagesDir.create(recursive: true);

      final list = await loadAll();

      if (entry['timestamp'] == null) entry['timestamp'] = DateTime.now().toIso8601String();

      if (entry['thumbnailPath'] != null) {
        try {
          final src = File(entry['thumbnailPath']);
          if (await src.exists()) {
            final ext = p.extension(src.path);
            final id = DateTime.now().millisecondsSinceEpoch.toString();
            final dstPath = p.join(imagesDir.path, 'thumb_$id$ext');
            await src.copy(dstPath);
            entry['thumbnailPath'] = dstPath;
          } else {
            entry['thumbnailPath'] = null;
          }
        } catch (e) {
          debugPrint('[HistoryStorage] thumbnail copy failed: $e');
          entry['thumbnailPath'] = null;
        }
      }

      entry['id'] = entry['id'] ?? DateTime.now().millisecondsSinceEpoch.toString();
      entry['resistors'] =
          (entry['resistors'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? <String>[];
      entry['ics'] =
          (entry['ics'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? <String>[];

      if (entry['all_components'] is List) {
        try {
          entry['all_components'] = (entry['all_components'] as List)
              .map((e) => e is Map ? Map<String, dynamic>.from(e) : {'label': e.toString()})
              .toList();
        } catch (_) {}
      }

      list.insert(0, entry);
      return await _saveAll(list);
    } catch (e) {
      debugPrint('[HistoryStorage] addEntry error: $e');
      return false;
    }
  }

  static Future<bool> deleteById(dynamic id) async {
    try {
      final list = await loadAll();
      final idx = list.indexWhere((e) => e['id'] == id);
      if (idx == -1) return false;
      final entry = list.removeAt(idx);
      try {
        if (entry['thumbnailPath'] != null) {
          final f = File(entry['thumbnailPath']);
          if (await f.exists()) await f.delete();
        }
      } catch (e) {
        debugPrint('[HistoryStorage] delete thumbnail error: $e');
      }
      return await _saveAll(list);
    } catch (e) {
      debugPrint('[HistoryStorage] deleteById error: $e');
      return false;
    }
  }

  static Future<bool> clearAll() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File(p.join(dir.path, _fileName));
      if (await file.exists()) await file.delete();
      final imagesDir = Directory(p.join(dir.path, _imagesDir));
      if (await imagesDir.exists()) {
        await for (var f in imagesDir.list()) {
          try {
            final fi = File(f.path);
            if (await fi.exists()) await fi.delete();
          } catch (_) {}
        }
        try { await imagesDir.delete(); } catch (_) {}
      }
      return true;
    } catch (e) {
      debugPrint('[HistoryStorage] clearAll error: $e');
      return false;
    }
  }

  static Future<String?> exportEntryToFile(Map<String, dynamic> entry) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final exportsDir = Directory(p.join(dir.path, 'exports'));
      if (!await exportsDir.exists()) await exportsDir.create(recursive: true);
      final id = entry['id'] ?? DateTime.now().millisecondsSinceEpoch.toString();
      final out = File(p.join(exportsDir.path, 'entry_$id.json'));
      await out.writeAsString(jsonEncode(entry));
      return out.path;
    } catch (e) {
      debugPrint('[HistoryStorage] exportEntryToFile error: $e');
      return null;
    }
  }
}

enum _FilterMode { all, resistor, ic }
