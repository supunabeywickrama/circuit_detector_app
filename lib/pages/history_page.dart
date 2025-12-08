// lib/pages/history_page.dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// HistoryPage with persistent storage (history.json) and thumbnail copies.
/// Public API: HistoryStorage.addEntry(...)
class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  List<Map<String, dynamic>> _historyList = [];
  List<Map<String, dynamic>> _filteredList = [];
  bool _loading = true;
  String _query = "";
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
      // Filter by type:
      if (_filterMode == _FilterMode.resistor) {
        final List<dynamic> r = entry['resistors'] ?? [];
        if (r.isEmpty) return false;
      } else if (_filterMode == _FilterMode.ic) {
        final List<dynamic> ics = entry['ics'] ?? [];
        if (ics.isEmpty) return false;
      }

      if (q.isEmpty) return true;

      final ts = (entry['timestamp'] ?? "").toString().toLowerCase();
      final rlist = (entry['resistors'] ?? []).join(' ').toLowerCase();
      final ics = (entry['ics'] ?? []).join(' ').toLowerCase();

      return ts.contains(q) || rlist.contains(q) || ics.contains(q);
    }).toList();

    _filteredList.sort((a, b) {
      final ta = DateTime.tryParse(a['timestamp'] ?? "") ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final tb = DateTime.tryParse(b['timestamp'] ?? "") ??
          DateTime.fromMillisecondsSinceEpoch(0);
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
    final globalIndex = _historyList.indexWhere((e) => e['id'] == entry['id']);
    if (globalIndex == -1) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text("Delete Entry"),
        content: const Text("Are you sure you want to delete this record?"),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text("Cancel")),
          ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text("Delete")),
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
      builder: (dialogContext) => AlertDialog(
        title: const Text("Clear History"),
        content: const Text(
            "Are you sure you want to clear all scan history? This cannot be undone."),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text("Cancel")),
          ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text("Clear All")),
        ],
      ),
    );

    if (confirmed != true) return;
    await HistoryStorage.clearAll();
    await _loadHistory();
  }

  Future<void> _viewDetails(Map<String, dynamic> entry) async {
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text("Scan from ${entry['timestamp'] ?? 'unknown'}"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (entry['thumbnailPath'] != null)
              Image.file(
                File(entry['thumbnailPath']),
                height: 150,
                fit: BoxFit.cover,
              ),
            const SizedBox(height: 10),
            Text(
                "🟡 Resistors: ${(entry['resistors'] as List<dynamic>?)?.join(', ') ?? 'none'}"),
            Text(
                "🔵 ICs: ${(entry['ics'] as List<dynamic>?)?.join(', ') ?? 'none'}"),
            const SizedBox(height: 8),
            // Show categorized components if available
            if (entry['all_components'] != null)
              _buildComponentSummary(entry['all_components']),
            if (entry['notes'] != null) ...[
              const SizedBox(height: 8),
              Text("📝 Notes: ${entry['notes']}"),
            ],
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Close"))
        ],
      ),
    );
  }

  Future<void> _exportEntry(Map<String, dynamic> entry) async {
    final exportedPath = await HistoryStorage.exportEntryToFile(entry);
    if (exportedPath != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text("Exported to: $exportedPath")));
    } else {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text("Export failed.")));
    }
  }

  Widget _buildListTile(int index) {
    final entry = _filteredList[index];
    final thumbnail = entry['thumbnailPath'] as String?;
    final timestamp = entry['timestamp'] ?? '';
    final resistors =
        (entry['resistors'] as List<dynamic>?)?.cast<String>() ?? <String>[];
    final ics = (entry['ics'] as List<dynamic>?)?.cast<String>() ?? <String>[];

    return Dismissible(
      key: Key(entry['id'].toString()),
      background: Container(
          color: Colors.red,
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.only(left: 16),
          child: const Icon(Icons.delete, color: Colors.white)),
      secondaryBackground: Container(
          color: Colors.red,
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 16),
          child: const Icon(Icons.delete, color: Colors.white)),
      onDismissed: (_) async => await _deleteEntryAt(index),
      child: ListTile(
        leading: thumbnail != null
            ? ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.file(File(thumbnail),
                    width: 56, height: 56, fit: BoxFit.cover),
              )
            : const Icon(Icons.image_not_supported, size: 40, color: Colors.grey),
        title: Text("📅 $timestamp"),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Legacy short lists
            Text("🟡 Resistors: ${resistors.isEmpty ? 'none' : resistors.join(', ')}"),
            Text("🔵 ICs: ${ics.isEmpty ? 'none' : ics.join(', ')}"),
            const SizedBox(height: 6),
            // New: component category summary (prefer full all_components list)
            if (entry['all_components'] != null)
              _buildComponentSummary(entry['all_components'])
            else
              _buildLegacySummary(resistors, ics),
          ],
        ),
        isThreeLine: true,
        trailing: PopupMenuButton<String>(
          onSelected: (v) async {
            if (v == 'view') {
              _viewDetails(entry);
            } else if (v == 'export') {
              await _exportEntry(entry);
            } else if (v == 'delete') {
              final globalIndex =
                  _historyList.indexWhere((e) => e['id'] == entry['id']);
              if (globalIndex != -1) {
                await HistoryStorage.deleteById(entry['id']);
                await _loadHistory();
              }
            }
          },
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'view', child: Text("View details")),
            const PopupMenuItem(value: 'export', child: Text("Export JSON")),
            const PopupMenuItem(value: 'delete', child: Text("Delete")),
          ],
        ),
        onTap: () => _viewDetails(entry),
      ),
    );
  }

  /// Build categorized summary from full detection list: [{type, ...}, ...]
  Widget _buildComponentSummary(dynamic rawList) {
    if (rawList is! List) return const SizedBox();

    final Map<String, int> counts = {};

    for (final item in rawList) {
      if (item is Map) {
        // support either 'type' or 'label' naming
        final t = (item['type'] ?? item['label'] ?? "").toString();
        if (t.isNotEmpty) {
          counts[t] = (counts[t] ?? 0) + 1;
        }
      }
    }

    if (counts.isEmpty) return const Text("No components");

    // Sorted by count desc then name
    final entries = counts.entries.toList()
      ..sort((a, b) {
        final byCount = b.value.compareTo(a.value);
        if (byCount != 0) return byCount;
        return a.key.compareTo(b.key);
      });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("📦 Components:", style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        ...entries.map(
          (e) => Text("• ${e.key} — ${e.value}"),
        )
      ],
    );
  }

  /// Fallback for old history entries (no 'all_components')
  Widget _buildLegacySummary(List<String> resistors, List<String> ics) {
    final Map<String, int> summarised = {
      if (resistors.isNotEmpty) "Resistor": resistors.length,
      if (ics.isNotEmpty) "IC": ics.length,
    };

    if (summarised.isEmpty) return const Text("No components");

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("📦 Components:", style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        ...summarised.entries.map(
          (e) => Text("• ${e.key} — ${e.value}"),
        )
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("📜 Scan History"),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep),
            tooltip: "Clear all history",
            onPressed: _historyList.isEmpty ? null : _clearAll,
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'sort') {
                setState(() {
                  _sortNewestFirst = !_sortNewestFirst;
                  _applyFilters();
                });
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'sort',
                child:
                    Text(_sortNewestFirst ? "Sort: Newest first" : "Sort: Oldest first"),
              ),
            ],
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          decoration: const InputDecoration(
                              prefixIcon: Icon(Icons.search),
                              hintText: "Search timestamp / values / IC"),
                          onChanged: _onSearchChanged,
                        ),
                      ),
                      const SizedBox(width: 8),
                      PopupMenuButton<_FilterMode>(
                        tooltip: "Filter",
                        onSelected: _changeFilter,
                        itemBuilder: (_) => [
                          const PopupMenuItem(value: _FilterMode.all, child: Text("All")),
                          const PopupMenuItem(
                              value: _FilterMode.resistor, child: Text("Only: Resistors")),
                          const PopupMenuItem(
                              value: _FilterMode.ic, child: Text("Only: ICs")),
                        ],
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              color: Colors.blue.shade50),
                          child: Text(_filterMode == _FilterMode.all
                              ? "All"
                              : (_filterMode == _FilterMode.resistor ? "Resistors" : "ICs")),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: _filteredList.isEmpty
                      ? const Center(child: Text("No history available."))
                      : ListView.separated(
                          padding: const EdgeInsets.all(8.0),
                          itemCount: _filteredList.length,
                          separatorBuilder: (_, __) => const Divider(),
                          itemBuilder: (context, index) => _buildListTile(index),
                        ),
                ),
              ],
            ),
    );
  }
}

/// Simple storage helper that saves history to a JSON file and copies thumbnails.
/// All methods are static for convenience.
class HistoryStorage {
  static const _fileName = "history.json";
  static const _imagesDir = "history_images";

  /// Load all history (returns list sorted newest first).
  static Future<List<Map<String, dynamic>>> loadAll() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File(p.join(dir.path, _fileName));
      if (!await file.exists()) return [];
      final txt = await file.readAsString();
      final data = jsonDecode(txt) as List<dynamic>;
      // ensure stable typed structure
      final out = data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      out.sort((a, b) {
        final ta = DateTime.tryParse(a['timestamp'] ?? "") ??
            DateTime.fromMillisecondsSinceEpoch(0);
        final tb = DateTime.tryParse(b['timestamp'] ?? "") ??
            DateTime.fromMillisecondsSinceEpoch(0);
        return tb.compareTo(ta);
      });
      return out;
    } catch (e) {
      debugPrint("[HistoryStorage] loadAll error: $e");
      return [];
    }
  }

  /// Save whole list (internal)
  static Future<bool> _saveAll(List<Map<String, dynamic>> list) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File(p.join(dir.path, _fileName));
      await file.writeAsString(jsonEncode(list));
      return true;
    } catch (e) {
      debugPrint("[HistoryStorage] _saveAll error: $e");
      return false;
    }
  }

  /// Add an entry. If `thumbnailPath` is provided, the image will be copied to app storage.
  /// Entry example:
  /// {
  ///  'timestamp': '2025-07-14T14:30:00Z',
  ///  'resistors': ['4.7kΩ'],
  ///  'ics': ['NE555'],
  ///  'thumbnailPath': '/some/path.jpg', // optional
  ///  'notes': '...'
  /// }
  static Future<bool> addEntry(Map<String, dynamic> entry) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final imagesDir = Directory(p.join(dir.path, _imagesDir));
      if (!await imagesDir.exists()) await imagesDir.create(recursive: true);

      final list = await loadAll();

      // Ensure timestamp
      if (entry['timestamp'] == null) entry['timestamp'] = DateTime.now().toIso8601String();

      // Copy thumbnail if path provided
      if (entry['thumbnailPath'] != null) {
        try {
          final src = File(entry['thumbnailPath']);
          if (await src.exists()) {
            final ext = p.extension(src.path);
            final id = DateTime.now().millisecondsSinceEpoch.toString();
            final dstPath = p.join(imagesDir.path, "thumb_$id$ext");
            await src.copy(dstPath);
            entry['thumbnailPath'] = dstPath;
          } else {
            entry['thumbnailPath'] = null;
          }
        } catch (e) {
          debugPrint("[HistoryStorage] thumbnail copy failed: $e");
          entry['thumbnailPath'] = null;
        }
      }

      // Add unique id
      entry['id'] = entry['id'] ?? DateTime.now().millisecondsSinceEpoch.toString();
      // Normalize lists
      entry['resistors'] =
          (entry['resistors'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? <String>[];
      entry['ics'] =
          (entry['ics'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? <String>[];

      // Ensure all_components is a list of maps if present
      if (entry['all_components'] is List) {
        try {
          entry['all_components'] = (entry['all_components'] as List)
              .map((e) => e is Map ? Map<String, dynamic>.from(e) : {'label': e.toString()})
              .toList();
        } catch (_) {
          // leave as-is if conversion fails
        }
      }

      list.insert(0, entry);
      return await _saveAll(list);
    } catch (e) {
      debugPrint("[HistoryStorage] addEntry error: $e");
      return false;
    }
  }

  /// Delete by id
  static Future<bool> deleteById(dynamic id) async {
    try {
      final list = await loadAll();
      final idx = list.indexWhere((e) => e['id'] == id);
      if (idx == -1) return false;

      final entry = list.removeAt(idx);

      // Delete thumbnail file if present
      try {
        if (entry['thumbnailPath'] != null) {
          final f = File(entry['thumbnailPath']);
          if (await f.exists()) await f.delete();
        }
      } catch (e) {
        debugPrint("[HistoryStorage] delete thumbnail error: $e");
      }

      return await _saveAll(list);
    } catch (e) {
      debugPrint("[HistoryStorage] deleteById error: $e");
      return false;
    }
  }

  /// Clear all entries and delete images folder
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
        try {
          await imagesDir.delete();
        } catch (_) {}
      }
      return true;
    } catch (e) {
      debugPrint("[HistoryStorage] clearAll error: $e");
      return false;
    }
  }

  /// Export single entry JSON to a file and return path (or null)
  static Future<String?> exportEntryToFile(Map<String, dynamic> entry) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final exportsDir = Directory(p.join(dir.path, "exports"));
      if (!await exportsDir.exists()) await exportsDir.create(recursive: true);
      final id = entry['id'] ?? DateTime.now().millisecondsSinceEpoch.toString();
      final out = File(p.join(exportsDir.path, "entry_$id.json"));
      await out.writeAsString(jsonEncode(entry));
      return out.path;
    } catch (e) {
      debugPrint("[HistoryStorage] exportEntryToFile error: $e");
      return null;
    }
  }
}

enum _FilterMode { all, resistor, ic }
