// lib/pages/results_page.dart
import 'dart:io';
import 'dart:async';
import 'dart:typed_data';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:photo_view/photo_view_gallery.dart';

import '../services/api_service.dart';
import '../theme/gradients.dart';
import 'history_page.dart'; // <--- using HistoryStorage.addEntry

class ResultsPage extends StatefulWidget {
  final List<String> imagePaths;

  const ResultsPage({Key? key, required this.imagePaths}) : super(key: key);

  @override
  State<ResultsPage> createState() => _ResultsPageState();
}

class _ResultsPageState extends State<ResultsPage> {
  late List<String> imagePaths;

  bool _loading = true;
  String? _error;

  // ── Rejection state ──────────────────────────────────────────────────────
  bool _isRejected = false;
  String _rejectionType = ''; // 'blurry' | 'not_circuit'
  String _rejectionReason = '';

  bool _anyBlurred = false;

  /// All detections merged (for text summary). After grouping this becomes grouped components.
  final List<Map<String, dynamic>> _allComponents = [];

  /// Per-image detections: path -> detections
  final Map<String, List<Map<String, dynamic>>> _detectionsPerPath = {};

  /// Per-image original size from backend: path -> Size(width, height)
  final Map<String, Size> _imageSizesPerPath = {};

  /// Internal raw detections used for grouping (built from _detectionsPerPath)
  final List<_RawDetection> _rawDetections = [];

  @override
  void initState() {
    super.initState();
    imagePaths = List.from(widget.imagePaths);
    _runDetections();
  }

  Future<void> _runDetections() async {
    setState(() {
      _loading = true;
      _error = null;
      _isRejected = false;
      _rejectionType = '';
      _rejectionReason = '';
      _anyBlurred = false;
      _allComponents.clear();
      _detectionsPerPath.clear();
      _imageSizesPerPath.clear();
      _rawDetections.clear();
    });

    try {
      if (imagePaths.isEmpty) {
        setState(() {
          _loading = false;
          _error = 'No image to process.';
        });
        return;
      }

      // If multiple images -> try multi-image endpoint but tolerate failures
      if (imagePaths.length > 1) {
        try {
          await _runMultiDetectionWithFallback();
        } catch (e) {
          debugPrint('[ResultsPage] multi detection failed -> falling back: $e');
          await _runSingleDetections();
        }
      } else {
        await _runSingleDetections();
      }

      // If rejected, stop here — UI already updated inside _runSingleDetections
      if (_isRejected) return;

      // Build raw detections if not populated by multi endpoint
      if (_rawDetections.isEmpty) {
        int idx = 0;
        for (final path in imagePaths) {
          final comps = _detectionsPerPath[path] ?? [];
          for (final c in comps) {
            final bbox = (c['bbox'] is List)
                ? (c['bbox'] as List).map((e) => (e as num).toDouble()).toList()
                : <double>[];
            _rawDetections.add(_RawDetection(
              imageIndex: idx,
              imagePath: path,
              bbox: bbox,
              type: (c['type'] ?? 'unknown').toString(),
              confidence: (c['confidence'] is num) ? (c['confidence'] as num).toDouble() : 0.0,
              extra: (c['extra'] is Map)
                  ? Map<String, dynamic>.from(c['extra'] as Map)
                  : <String, dynamic>{},
            ));
          }
          idx++;
        }
      }

      // Group across images if multiple images exist and raw detections exist
      if (_rawDetections.isNotEmpty && imagePaths.length > 1) {
        await _groupDetectionsAcrossImages();
      } else {
        if (_allComponents.isEmpty) {
          for (final list in _detectionsPerPath.values) {
            _allComponents.addAll(list);
          }
        }
      }

      debugPrint('Total detections across images (after grouping): ${_allComponents.length}');

      setState(() { _loading = false; });

      // Save detection to history (non-blocking)
      _saveCurrentDetectionToHistory();
    } catch (e) {
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  /// Run single-image detection for each image (defensive).
  Future<void> _runSingleDetections() async {
    _detectionsPerPath.clear();
    _allComponents.clear();
    _imageSizesPerPath.clear();
    _rawDetections.clear();

    for (final path in imagePaths) {
      dynamic json;
      try {
        json = await ApiService.detectSingle(path);
      } catch (e) {
        throw Exception('Failed to detect for $path: $e');
      }

      if (json == null || json is! Map<String, dynamic>) {
        debugPrint('[ResultsPage] unexpected response for $path: $json');
        _detectionsPerPath[path] = [];
        continue;
      }

      // ── Handle backend rejection ─────────────────────────────────────────
      if (json['rejected'] == true) {
        setState(() {
          _loading = false;
          _isRejected = true;
          _rejectionType = (json['rejection_type'] ?? '').toString();
          _rejectionReason = (json['reason'] ?? 'Image was rejected by the server.').toString();
        });
        return;
      }

      final blurred = json['blurred'] == true;
      if (blurred) _anyBlurred = true;

      // Read blur variance if provided
      final bv = json['blur_variance'];
      if (bv is num) _anyBlurred = _anyBlurred || bv.toDouble() < 90.0;

      // ── Image size ───────────────────────────────────────────────────────
      final imgInfo = json['image'];
      if (imgInfo is Map) {
        final w = (imgInfo['width'] as num?)?.toDouble();
        final h = (imgInfo['height'] as num?)?.toDouble();
        if (w != null && h != null && w > 0 && h > 0) {
          _imageSizesPerPath[path] = Size(w, h);
        }
      }

      // ── Detections ───────────────────────────────────────────────────────
      final detectionsRaw = json['detections'];
      List<Map<String, dynamic>> comps = [];

      if (detectionsRaw is List) {
        try {
          comps = detectionsRaw.map<Map<String, dynamic>>((e) {
            final raw = Map<String, dynamic>.from(e as Map);

            final label = (raw["label"] ?? "").toString();
            final conf = (raw["confidence"] ?? 0.0) as num;

            final bboxRaw = raw["bbox"];
            List<double> bbox;
            if (bboxRaw is List) {
              bbox = bboxRaw.map((v) => (v as num).toDouble()).toList(); // [x1,y1,x2,y2]
            } else {
              bbox = const <double>[];
            }

            final extraRaw = raw["extra"];
            final extra = (extraRaw is Map) ? Map<String, dynamic>.from(extraRaw as Map) : <String, dynamic>{};

            return {
              "type": label,
              "bbox": bbox,
              "confidence": conf.toDouble(),
              "extra": extra,
            };
          }).toList();
        } catch (e) {
          debugPrint("[ResultsPage] parse detections failed for $path: $e");
          comps = [];
        }
      } else {
        // no detections key or not list -> treat as empty
        debugPrint("[ResultsPage] missing/invalid detections for $path");
        comps = [];
      }

      _detectionsPerPath[path] = comps;
    }
  }

  /// Try to call ApiService.detectMulti(...) and if it fails or returns unexpected JSON,
  /// fall back to calling detectSingle for each image.
  Future<void> _runMultiDetectionWithFallback() async {
    _detectionsPerPath.clear();
    _allComponents.clear();
    _imageSizesPerPath.clear();
    _rawDetections.clear();

    for (final p in imagePaths) _detectionsPerPath[p] = [];

    dynamic json;
    try {
      json = await ApiService.detectMulti(imagePaths);
    } catch (e) {
      debugPrint("[ResultsPage] detectMulti call threw: $e");
      rethrow;
    }

    if (json == null) {
      debugPrint("[ResultsPage] detectMulti returned null, falling back");
      await _runSingleDetections();
      return;
    }

    // Case A: backend returned aggregated map with "components"
    if (json is Map<String, dynamic> && json.containsKey("components") && json["components"] is List) {
      final mapJson = json as Map<String, dynamic>;
      final compsRaw = (mapJson["components"] as List).cast<Map>();
      final comps = compsRaw.map((m) => Map<String, dynamic>.from(m)).toList();

      // optional: read image sizes array
      if (mapJson.containsKey("images") && mapJson["images"] is List) {
        final imgs = (mapJson["images"] as List).cast<Map>();
        for (var i = 0; i < imgs.length && i < imagePaths.length; i++) {
          final info = imgs[i];
          final w = (info["width"] as num?)?.toDouble();
          final h = (info["height"] as num?)?.toDouble();
          if (w != null && h != null && w > 0 && h > 0) {
            _imageSizesPerPath[imagePaths[i]] = Size(w, h);
          }
        }
      }

      // Each component includes 'views' which map to image_index + bbox
      for (final comp in comps) {
        final type = (comp["type"] ?? comp["label"] ?? "unknown").toString();
        final extra = (comp["extra"] is Map) ? Map<String, dynamic>.from(comp["extra"]) : <String, dynamic>{};
        final confidence = (comp["confidence"] is num) ? (comp["confidence"] as num).toDouble() : 0.0;
        final id = comp["id"]?.toString();

        final viewsRaw = comp["views"];
        final List<Map<String, dynamic>> views = [];
        if (viewsRaw is List) {
          for (final v in viewsRaw) {
            if (v is Map) {
              final imageIndex = (v["image_index"] is num) ? (v["image_index"] as num).toInt() : null;
              final bboxRaw = v["bbox"];
              List<double> bbox = const <double>[];
              if (bboxRaw is List) {
                bbox = bboxRaw.map((x) => (x as num).toDouble()).toList();
              }
              views.add({"image_index": imageIndex, "bbox": bbox});
            }
          }
        }

        // Add to aggregated components list
        _allComponents.add({
          "id": id,
          "type": type,
          "confidence": confidence,
          "extra": extra,
          "views": views,
        });

        // Populate per-image detections
        for (final view in views) {
          final idx = view["image_index"] as int?;
          final bbox = (view["bbox"] as List?) ?? const <double>[];
          if (idx == null || idx < 0 || idx >= imagePaths.length) continue;
          final path = imagePaths[idx];
          final entry = {
            "type": type,
            "bbox": bbox,
            "confidence": confidence,
            "extra": extra,
            "component_id": id,
          };
          _detectionsPerPath[path] = (_detectionsPerPath[path] ?? [])..add(entry);
        }
      }
      return;
    }

    // Case B: backend returned a List of per-image single-detect responses (fallback style)
    if (json is List) {
      final list = json.cast<dynamic>();
      // If list length >= images, map each item to a path
      final n = math.min(list.length, imagePaths.length);
      for (var i = 0; i < n; i++) {
        final item = list[i];
        final path = imagePaths[i];
        if (item == null || item is! Map<String, dynamic>) {
          _detectionsPerPath[path] = [];
          continue;
        }

        // blurred
        final blurred = item["blurred"] == true;
        if (blurred) _anyBlurred = true;

        // sizes
        final imgInfo = item["image"];
        if (imgInfo is Map) {
          final w = (imgInfo["width"] as num?)?.toDouble();
          final h = (imgInfo["height"] as num?)?.toDouble();
          if (w != null && h != null && w > 0 && h > 0) {
            _imageSizesPerPath[path] = Size(w, h);
          }
        }

        // detections
        final detectionsRaw = item["detections"];
        List<Map<String, dynamic>> comps = [];
        if (detectionsRaw is List) {
          try {
            comps = detectionsRaw.map<Map<String, dynamic>>((e) {
              final raw = Map<String, dynamic>.from(e as Map);
              final label = (raw["label"] ?? "").toString();
              final conf = (raw["confidence"] ?? 0.0) as num;
              final bboxRaw = raw["bbox"];
              List<double> bbox;
              if (bboxRaw is List) {
                bbox = bboxRaw.map((v) => (v as num).toDouble()).toList();
              } else {
                bbox = const <double>[];
              }
              final extraRaw = raw["extra"];
              final extra = (extraRaw is Map) ? Map<String, dynamic>.from(extraRaw as Map) : <String, dynamic>{};
              return {"type": label, "bbox": bbox, "confidence": conf.toDouble(), "extra": extra};
            }).toList();
          } catch (e) {
            debugPrint("[ResultsPage] parse per-image item failed: $e");
            comps = [];
          }
        }
        _detectionsPerPath[path] = comps;
      }
      // If list longer than images, ignore extras
      return;
    }

    // Unknown format -> fall back to single detection per image
    debugPrint("[ResultsPage] detectMulti returned unexpected format, falling back");
    await _runSingleDetections();
  }

  /// Save the current detection summary to local history via HistoryStorage.
  Future<void> _saveCurrentDetectionToHistory() async {
    try {
      if (_allComponents.isEmpty) return;

      final resistors = _allComponents.where((c) {
        final t = (c["type"] as String? ?? "").toLowerCase();
        return t.startsWith("resistor");
      }).map((r) {
        final extra = (r["extra"] as Map?) ?? {};
        final value = (extra["value"] != null && extra["value"].toString().isNotEmpty) ? extra["value"].toString() : "value N/A";
        return value;
      }).toList();

      final ics = _allComponents.where((c) {
        final t = (c["type"] as String? ?? "").toLowerCase();
        return t == "ic";
      }).map((ic) {
        final extra = (ic["extra"] as Map?) ?? {};
        final ocr = (extra["ocr"] != null && extra["ocr"].toString().isNotEmpty) ? extra["ocr"].toString() : "unreadable";
        return ocr;
      }).toList();

      final Map<String, int> counts = {};
      for (final c in _allComponents) {
        final key = (c["type"] ?? "unknown").toString();
        counts[key] = (counts[key] ?? 0) + 1;
      }

      final entry = <String, dynamic>{
        'timestamp': DateTime.now().toIso8601String(),
        'resistors': resistors,
        'ics': ics,
        'thumbnailPath': imagePaths.isNotEmpty ? imagePaths.first : null,
        'notes': null,
        'all_components': _allComponents.map((c) {
          final m = {
            'type': c['type'],
            'bbox': c['bbox'],
            'confidence': c['confidence'],
            'extra': c['extra'],
          };
          if (c.containsKey('views')) m['views'] = c['views'];
          if (c.containsKey('id')) m['id'] = c['id'];
          if (c.containsKey('count')) m['count'] = c['count'];
          if (c.containsKey('members')) m['members'] = c['members'];
          return m;
        }).toList(),
        'counts': counts,
      };

      final ok = await HistoryStorage.addEntry(entry);
      if (ok) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Saved detection to history.")));
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Failed to save detection to history.")));
        }
      }
    } catch (e) {
      debugPrint("[ResultsPage] _saveCurrentDetectionToHistory error: $e");
    }
  }

  int _categoryCount() {
    final types = <String>{};
    for (final c in _allComponents) {
      final t = (c['type'] as String? ?? '').toLowerCase();
      if (t.isNotEmpty) types.add(t);
    }
    return types.length;
  }

  List<Map<String, dynamic>> _byType(String startsWith) {
    return _allComponents.where((c) => (c["type"] as String? ?? "").toLowerCase().startsWith(startsWith.toLowerCase())).toList();
  }

  // --- NEW: compute a human-friendly source label for a component ---
  String _sourceLabelForComponent(Map<String, dynamic> comp) {
    final indices = _componentSourceIndices(comp);
    if (indices.isEmpty) return "unknown";
    indices.sort();
    if (indices.length == 1) return "only angle ${indices.first}";
    // join with & as requested: 1&2&3 or 1&3
    final joined = indices.map((i) => i.toString()).join("&");
    return "angles: $joined";
  }

  // returns list of 1-based image indices for a component
  List<int> _componentSourceIndices(Map<String, dynamic> comp) {
    final Set<int> out = {};
    try {
      // 1) if 'members' present (grouped), use imageIndex entries
      if (comp.containsKey('members') && comp['members'] is List) {
        for (final m in (comp['members'] as List)) {
          if (m is Map && m.containsKey('imageIndex')) {
            final idx = (m['imageIndex'] is num) ? (m['imageIndex'] as num).toInt() : null;
            if (idx != null && idx >= 0 && idx < imagePaths.length) out.add(idx + 1);
          }
        }
        if (out.isNotEmpty) return out.toList();
      }

      // 2) if 'views' present (multi-detect backend), use image_index in views
      if (comp.containsKey('views') && comp['views'] is List) {
        for (final v in (comp['views'] as List)) {
          if (v is Map && v.containsKey('image_index')) {
            final idx = (v['image_index'] is num) ? (v['image_index'] as num).toInt() : null;
            if (idx != null && idx >= 0 && idx < imagePaths.length) out.add(idx + 1);
          }
        }
        if (out.isNotEmpty) return out.toList();
      }

      // 3) fallback: search per-image detections for matching bbox(s)
      for (var i = 0; i < imagePaths.length; i++) {
        final path = imagePaths[i];
        final comps = _detectionsPerPath[path] ?? [];
        for (final c in comps) {
          final cbbox = (c['bbox'] is List) ? (c['bbox'] as List).map((e) => (e as num).toDouble()).toList() : <double>[];
          final tbbox = (comp['bbox'] is List) ? (comp['bbox'] as List).map((e) => (e as num).toDouble()).toList() : <double>[];
          if (_bboxEquals(cbbox, tbbox)) {
            out.add(i + 1);
          }
          // also if comp has component_id and per-image entry has same component_id
          if (comp.containsKey('id') && c.containsKey('component_id') && c['component_id'] == comp['id']) {
            out.add(i + 1);
          }
        }
      }
    } catch (_) {}
    return out.toList();
  }

  void _showZoomableImage(int initialIndex) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        child: SizedBox(
          height: 400,
          child: PhotoViewGallery.builder(
            itemCount: imagePaths.length,
            pageController: PageController(initialPage: initialIndex),
            builder: (context, index) => PhotoViewGalleryPageOptions(
              imageProvider: FileImage(File(imagePaths[index])),
            ),
          ),
        ),
      ),
    );
  }

  void _confirmDelete(int index) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Delete Image"),
        content: const Text("Are you sure you want to remove this image?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () {
              final removedPath = imagePaths[index];
              setState(() {
                imagePaths.removeAt(index);
                _detectionsPerPath.remove(removedPath);
                _imageSizesPerPath.remove(removedPath);
                _allComponents
                  ..clear()
                  ..addAll(_detectionsPerPath.values.expand((e) => e));
              });
              Navigator.pop(context);
            },
            child: const Text("Delete"),
          ),
        ],
      ),
    );
  }

  void _retakeImage(int index) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Retake logic not implemented. Index: $index")),
    );
  }

  void _shareResults() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Share/export feature coming soon!")),
    );
  }

  /// Image with properly scaled boxes
  Widget _buildDetectionImage(
    File imageFile,
    List<Map<String, dynamic>> comps,
    Size? originalSize,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final displayW = constraints.maxWidth;
        final displayH = constraints.maxHeight;

        double sx = 1.0;
        double sy = 1.0;
        if (originalSize != null) {
          sx = displayW / originalSize.width;
          sy = displayH / originalSize.height;
        }

        return Stack(
          children: [
            Image.file(
              imageFile,
              width: displayW,
              height: displayH,
              fit: BoxFit.cover,
            ),
            ...comps.map((det) {
              final bbox = (det["bbox"] as List?) ?? const [];
              if (bbox.length != 4) return const SizedBox.shrink();

              final double x1 = (bbox[0] as num).toDouble() * sx;
              final double y1 = (bbox[1] as num).toDouble() * sy;
              final double x2 = (bbox[2] as num).toDouble() * sx;
              final double y2 = (bbox[3] as num).toDouble() * sy;

              return Positioned(
                left: x1,
                top: y1,
                width: (x2 - x1),
                height: (y2 - y1),
                child: IgnorePointer(
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.greenAccent, width: 2),
                    ),
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: Container(
                        color: Colors.greenAccent.withOpacity(0.75),
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                        child: Text(
                          "${det["type"] ?? "obj"} (${(((det["confidence"] ?? 0.0) as num) * 100).toStringAsFixed(0)}%)",
                          style: const TextStyle(fontSize: 10, color: Colors.black),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            })
          ],
        );
      },
    );
  }

  /// GROUPING: compute average rgb signature for each raw detection and cluster by label+color
  Future<void> _groupDetectionsAcrossImages() async {
    _allComponents.clear();

    for (final rd in _rawDetections) {
      try {
        rd.signature = await _computeCropAverageColor(rd.imagePath, rd.bbox, _imageSizesPerPath[rd.imagePath]);
      } catch (e) {
        debugPrint("[Grouping] signature error: $e");
        rd.signature = null;
      }
    }

    final double colorThreshold = 45.0;

    final List<_Group> groups = [];
    int gid = 1;
    for (final rd in _rawDetections) {
      bool attached = false;
      for (final g in groups) {
        if (g.type.toLowerCase() != rd.type.toLowerCase()) continue;
        if (g.signature != null && rd.signature != null) {
          final d = _colorDist(g.signature!, rd.signature!);
          if (d <= colorThreshold) {
            g.add(rd);
            attached = true;
            break;
          }
        } else {
          if (_bboxCenterDistanceHeuristic(g.representative.bbox, rd.bbox) < 0.09) {
            g.add(rd);
            attached = true;
            break;
          }
        }
      }
      if (!attached) {
        final g = _Group(id: "g$gid", type: rd.type);
        gid++;
        g.add(rd);
        groups.add(g);
      }
    }

    for (final g in groups) {
      final rep = g.representative;
      final count = g.members.length;
      final avgConf = g.members.map((m) => m.confidence).fold(0.0, (a, b) => a + b) / (count > 0 ? count : 1);
      final grouped = {
        "id": g.id,
        "type": g.type,
        "count": count,
        "confidence": double.parse(avgConf.toStringAsFixed(3)),
        "extra": rep.extra ?? {},
        "members": g.members.map((m) {
          return {
            "imageIndex": m.imageIndex,
            "path": m.imagePath,
            "bbox": m.bbox,
            "confidence": m.confidence,
          };
        }).toList(),
      };
      _allComponents.add(grouped);

      for (final m in g.members) {
        final list = _detectionsPerPath[m.imagePath] ?? [];
        bool found = false;
        for (var item in list) {
          final itemBbox = (item["bbox"] as List?) ?? const [];
          if (_bboxEquals(itemBbox, m.bbox)) {
            item["component_id"] = g.id;
            found = true;
            break;
          }
        }
        if (!found) {
          _detectionsPerPath[m.imagePath] = list..add({
            "type": m.type,
            "bbox": m.bbox,
            "confidence": m.confidence,
            "extra": m.extra,
            "component_id": g.id,
          });
        }
      }
    }
  }

  Future<List<int>?> _computeCropAverageColor(String imagePath, List<double> bbox, Size? originalSize) async {
    try {
      if (bbox.length != 4) return null;
      final bytes = await File(imagePath).readAsBytes();
      final uiImage = await _decodeUiImage(bytes);
      final imgW = uiImage.width;
      final imgH = uiImage.height;

      double scaleX = 1.0, scaleY = 1.0;
      if (originalSize != null && originalSize.width > 0 && originalSize.height > 0) {
        scaleX = imgW / originalSize.width;
        scaleY = imgH / originalSize.height;
      }

      final x1 = (bbox[0] * scaleX).clamp(0, imgW - 1).toInt();
      final y1 = (bbox[1] * scaleY).clamp(0, imgH - 1).toInt();
      final x2 = (bbox[2] * scaleX).clamp(0, imgW - 1).toInt();
      final y2 = (bbox[3] * scaleY).clamp(0, imgH - 1).toInt();

      if (x2 <= x1 || y2 <= y1) return null;

      final width = x2 - x1;
      final height = y2 - y1;

      final stepX = (width / 20).ceil().clamp(1, 8);
      final stepY = (height / 20).ceil().clamp(1, 8);

      final bd = await uiImage.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (bd == null) return null;
      final data = bd.buffer.asUint8List();

      int rSum = 0, gSum = 0, bSum = 0, count = 0;

      for (int yy = y1; yy < y2; yy += stepY) {
        for (int xx = x1; xx < x2; xx += stepX) {
          final idx = (yy * imgW + xx) * 4;
          if (idx + 2 >= data.length) continue;
          final r = data[idx];
          final g = data[idx + 1];
          final b = data[idx + 2];
          rSum += r;
          gSum += g;
          bSum += b;
          count++;
        }
      }

      if (count == 0) return null;
      final rAvg = (rSum / count).round();
      final gAvg = (gSum / count).round();
      final bAvg = (bSum / count).round();
      return [rAvg, gAvg, bAvg];
    } catch (e) {
      debugPrint("[computeCropAvgColor] error: $e");
      return null;
    }
  }

  Future<ui.Image> _decodeUiImage(Uint8List data) {
    final completer = Completer<ui.Image>();
    ui.decodeImageFromList(data, (ui.Image img) => completer.complete(img));
    return completer.future;
  }

  double _colorDist(List<int> a, List<int> b) {
    final dr = (a[0] - b[0]).toDouble();
    final dg = (a[1] - b[1]).toDouble();
    final db = (a[2] - b[2]).toDouble();
    return math.sqrt(dr * dr + dg * dg + db * db);
  }

  double _bboxCenterDistanceHeuristic(List? aRaw, List? bRaw) {
    try {
      if (aRaw == null || bRaw == null) return 1.0;
      if (aRaw.length != 4 || bRaw.length != 4) return 1.0;
      final a = aRaw.cast<num>().map((e) => e.toDouble()).toList();
      final b = bRaw.cast<num>().map((e) => e.toDouble()).toList();
      final ax = (a[0] + a[2]) / 2.0;
      final ay = (a[1] + a[3]) / 2.0;
      final bx = (b[0] + b[2]) / 2.0;
      final by = (b[1] + b[3]) / 2.0;
      final dx = (ax - bx).abs();
      final dy = (ay - by).abs();
      final denom = (((a[2] - a[0]).abs() + (b[2] - b[0]).abs()) / 2.0).abs() + 1.0;
      final norm = ((dx + dy) / denom);
      return norm;
    } catch (_) {
      return 1.0;
    }
  }

  bool _bboxEquals(List? aRaw, List? bRaw) {
    if (aRaw == null || bRaw == null) return false;
    if (aRaw.length != 4 || bRaw.length != 4) return false;
    for (int i = 0; i < 4; i++) {
      final av = (aRaw[i] as num).toDouble();
      final bv = (bRaw[i] as num).toDouble();
      if ((av - bv).abs() > 2.0) return false;
    }
    return true;
  }

  // ── Rejection card widget ────────────────────────────────────────────────
  Widget _buildRejectionView() {
    final isBlurry = _rejectionType == 'blurry';
    final icon = isBlurry ? Icons.blur_on : Icons.no_photography_rounded;
    final color = isBlurry ? Colors.orange.shade700 : Colors.red.shade600;
    final title = isBlurry ? '📸 Image Too Blurry' : '🚫 Not a Circuit Board';

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: color, width: 2),
              ),
              child: Column(
                children: [
                  Icon(icon, size: 64, color: color),
                  const SizedBox(height: 16),
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _rejectionReason,
                    style: const TextStyle(fontSize: 14, height: 1.5),
                    textAlign: TextAlign.center,
                  ),
                  if (isBlurry) ...[
                    const SizedBox(height: 12),
                    const Text(
                      'Tips for a sharp photo:\n'
                      '• Hold your phone still\n'
                      '• Use good, even lighting\n'
                      '• Avoid reflections on the PCB\n'
                      '• Tap the screen to focus before shooting',
                      style: TextStyle(fontSize: 13, color: Colors.grey),
                    ),
                  ] else ...[
                    const SizedBox(height: 12),
                    const Text(
                      'Tips:\n'
                      '• Ensure the circuit board fills most of the frame\n'
                      '• Crop out non-board areas before uploading\n'
                      '• Use the camera page for best results',
                      style: TextStyle(fontSize: 13, color: Colors.grey),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                OutlinedButton.icon(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('Go Back'),
                ),
                ElevatedButton.icon(
                  onPressed: _runDetections,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                  style: ElevatedButton.styleFrom(backgroundColor: color),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget body;

    if (_loading) {
      body = Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 56,
            height: 56,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              valueColor: AlwaysStoppedAnimation<Color>(AppColors.primaryCyan),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Analysing your circuit...',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          Text(
            'AI is detecting components and reading values',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      );
    } else if (_isRejected) {
      body = _buildRejectionView();
    } else if (_error != null) {
      body = Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 48),
              const SizedBox(height: 12),
              Text(
                'Detection failed:\n$_error',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _runDetections,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    } else {
      final resistors = _byType('resistor');
      final ics = _allComponents
          .where((c) => (c['type'] as String? ?? '').toLowerCase() == 'ic')
          .toList();
      final chips = _allComponents
          .where((c) => (c['type'] as String? ?? '').toLowerCase() == 'chip')
          .toList();
      final voltageRegs = _allComponents
          .where((c) => (c['type'] as String? ?? '').toLowerCase() == 'voltage_regulator')
          .toList();
      final others = _allComponents.where((c) {
        final t = (c['type'] as String? ?? '').toLowerCase();
        return !(t.startsWith('resistor') || t == 'ic' || t == 'chip' || t == 'voltage_regulator');
      }).toList();

      body = SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 30),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Summary chips ──
            Row(
              children: [
                _SummaryChip(
                  icon: Icons.memory_rounded,
                  label: '${_allComponents.length}',
                  subtitle: 'Components',
                  color: AppColors.primaryCyan,
                ),
                const SizedBox(width: 10),
                _SummaryChip(
                  icon: Icons.image_rounded,
                  label: '${widget.imagePaths.length}',
                  subtitle: 'Images',
                  color: AppColors.primaryViolet,
                ),
                const SizedBox(width: 10),
                _SummaryChip(
                  icon: Icons.category_rounded,
                  label: '${_categoryCount()}',
                  subtitle: 'Types',
                  color: AppColors.accentEmerald,
                ),
              ],
            ),
            const SizedBox(height: 8),

            const SizedBox(height: 14),

            // ── Blur warning banner ────────────────────────────────────────
            if (_anyBlurred)
              Container(
                margin: const EdgeInsets.only(bottom: 14),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [AppColors.warning.withOpacity(0.15), AppColors.warning.withOpacity(0.08)],
                  ),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(color: AppColors.warning.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.blur_on_rounded, color: AppColors.warning, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Some images appear blurry — results may be less accurate.',
                        style: TextStyle(color: AppColors.warning, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),

            // ── Resistors ──────────────────────────────────────────────────
            _SectionCard(
              title: 'Resistors',
              icon: Icons.electric_bolt_rounded,
              color: AppColors.accentAmber,
              count: resistors.length,
              isEmpty: resistors.isEmpty,
              children: resistors.map((r) {
                final val = (r['extra']?['value'] ?? '').toString();
                final conf = ((r['confidence'] ?? 0.0) as num).toStringAsFixed(2);
                final bands = r['extra']?['bands'];
                return _ComponentTile(
                  icon: Icons.electrical_services_rounded,
                  iconColor: AppColors.accentAmber,
                  title: val.isEmpty ? 'Value N/A' : val,
                  subtitle: 'Confidence: $conf',
                  trailing: bands is List && bands.isNotEmpty
                      ? Row(
                          mainAxisSize: MainAxisSize.min,
                          children: bands.take(5).map<Widget>((b) {
                            return Container(
                              width: 14,
                              height: 14,
                              margin: const EdgeInsets.only(left: 2),
                              decoration: BoxDecoration(
                                color: _bandColor(b.toString()),
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white24, width: 0.5),
                              ),
                            );
                          }).toList(),
                        )
                      : null,
                );
              }).toList(),
            ),

            const SizedBox(height: 14),
            // ── ICs ────────────────────────────────────────────────────────
            _SectionCard(
              title: 'Integrated Circuits',
              icon: Icons.memory_rounded,
              color: AppColors.primaryBlue,
              count: ics.length,
              isEmpty: ics.isEmpty,
              children: ics.map((ic) {
                final ocr = (ic['extra']?['ocr'] ?? '').toString();
                final conf = ((ic['confidence'] ?? 0.0) as num).toStringAsFixed(2);
                return _ComponentTile(
                  icon: Icons.developer_board_rounded,
                  iconColor: AppColors.primaryBlue,
                  title: ocr.isEmpty || ocr == 'unreadable' ? 'Unreadable' : ocr,
                  subtitle: 'Confidence: $conf',
                );
              }).toList(),
            ),

            // ── Chips ─────────────────────────────────────────────────────
            if (chips.isNotEmpty) ...[
              const SizedBox(height: 14),
              _SectionCard(
                title: 'Chips',
                icon: Icons.sim_card_rounded,
                color: AppColors.primaryViolet,
                count: chips.length,
                isEmpty: false,
                children: chips.map((chip) {
                  final ocr = (chip['extra']?['ocr'] ?? '').toString();
                  final conf = ((chip['confidence'] ?? 0.0) as num).toStringAsFixed(2);
                  return _ComponentTile(
                    icon: Icons.sim_card_rounded,
                    iconColor: AppColors.primaryViolet,
                    title: ocr.isEmpty || ocr == 'unreadable' ? 'Unreadable' : ocr,
                    subtitle: 'Confidence: $conf',
                  );
                }).toList(),
              ),
            ],

            // ── Voltage Regulators ─────────────────────────────────────────
            if (voltageRegs.isNotEmpty) ...[
              const SizedBox(height: 14),
              _SectionCard(
                title: 'Voltage Regulators',
                icon: Icons.bolt_rounded,
                color: AppColors.accentOrange,
                count: voltageRegs.length,
                isEmpty: false,
                children: voltageRegs.map((vr) {
                  final ocr = (vr['extra']?['ocr'] ?? '').toString();
                  final conf = ((vr['confidence'] ?? 0.0) as num).toStringAsFixed(2);
                  return _ComponentTile(
                    icon: Icons.bolt_rounded,
                    iconColor: AppColors.accentOrange,
                    title: ocr.isEmpty || ocr == 'unreadable' ? 'Unreadable' : ocr,
                    subtitle: 'Confidence: $conf',
                  );
                }).toList(),
              ),
            ],

            // ── Others ─────────────────────────────────────────────────────
            if (others.isNotEmpty) ...[
              const SizedBox(height: 14),
              _SectionCard(
                title: 'Other Components',
                icon: Icons.widgets_rounded,
                color: AppColors.textSecondary,
                count: others.length,
                isEmpty: false,
                children: others.map((o) {
                  final t = o['type'] ?? 'Unknown';
                  final conf = ((o['confidence'] ?? 0.0) as num).toStringAsFixed(2);
                  return _ComponentTile(
                    icon: Icons.widgets_rounded,
                    iconColor: AppColors.textSecondary,
                    title: t.toString(),
                    subtitle: 'Confidence: $conf',
                  );
                }).toList(),
              ),
            ],

            const SizedBox(height: 28),
            if (imagePaths.isNotEmpty) ...[
              Row(
                children: [
                  Icon(Icons.camera_alt_rounded, size: 16, color: AppColors.primaryCyan),
                  const SizedBox(width: 8),
                  Text(
                    'CAPTURED IMAGES',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primaryCyan,
                      letterSpacing: 1.2,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ListView.builder(
                itemCount: imagePaths.length,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemBuilder: (context, index) {
                  final path = imagePaths[index];
                  final file = File(path);
                  final comps = _detectionsPerPath[path] ?? const <Map<String, dynamic>>[];
                  final imgSize = _imageSizesPerPath[path];

                  return Container(
                    margin: const EdgeInsets.only(bottom: 14),
                    decoration: BoxDecoration(
                      color: (Theme.of(context).brightness == Brightness.dark
                              ? Colors.white
                              : Colors.black)
                          .withOpacity(0.05),
                      borderRadius: BorderRadius.circular(AppRadius.lg),
                      border: Border.all(
                        color: (Theme.of(context).brightness == Brightness.dark
                                ? Colors.white
                                : Colors.grey)
                            .withOpacity(0.08),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
                          child: Row(
                            children: [
                              Text('Angle ${index + 1}',
                                  style: Theme.of(context).textTheme.titleMedium),
                              const Spacer(),
                              GestureDetector(
                                onTap: () => _retakeImage(index),
                                child: Icon(Icons.refresh_rounded,
                                    size: 20, color: AppColors.primaryCyan),
                              ),
                              const SizedBox(width: 12),
                              GestureDetector(
                                onTap: () => _confirmDelete(index),
                                child: Icon(Icons.delete_rounded,
                                    size: 20, color: AppColors.error),
                              ),
                            ],
                          ),
                        ),
                        GestureDetector(
                          onTap: () => _showZoomableImage(index),
                          child: ClipRRect(
                            borderRadius: const BorderRadius.only(
                              bottomLeft: Radius.circular(AppRadius.lg),
                              bottomRight: Radius.circular(AppRadius.lg),
                            ),
                            child: AspectRatio(
                              aspectRatio: (imgSize != null && imgSize.width > 0 && imgSize.height > 0)
                                  ? imgSize.width / imgSize.height
                                  : 4 / 3,
                              child: _buildDetectionImage(file, comps, imgSize),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ],
        ),
      );
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Detection Results'),
        leading: Padding(
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
        ),
        actions: [
          GestureDetector(
            onTap: _shareResults,
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.10),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white.withOpacity(0.12)),
              ),
              child: Icon(Icons.ios_share_rounded, color: Colors.white.withOpacity(0.8), size: 18),
            ),
          ),
          const SizedBox(width: 14),
        ],
      ),
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: isDark ? AppGradients.darkBackground : AppGradients.surfaceLight,
        ),
        child: SafeArea(child: body),
      ),
    );
  }
}

/// Small internal helper class for raw detections:
class _RawDetection {
  final int imageIndex;
  final String imagePath;
  final List<double> bbox;
  final String type;
  final double confidence;
  final Map<String, dynamic> extra;
  List<int>? signature; // avg RGB sample
  _RawDetection({
    required this.imageIndex,
    required this.imagePath,
    required this.bbox,
    required this.type,
    required this.confidence,
    required this.extra,
  });
}

/// Group of raw detections representing same physical component
class _Group {
  final String id;
  final String type;
  final List<_RawDetection> members = [];
  List<int>? signature;
  _RawDetection get representative => members.first;

  _Group({required this.id, required this.type});

  void add(_RawDetection d) {
    members.add(d);
    final sigs = members.where((m) => m.signature != null).map((m) => m.signature!).toList();
    if (sigs.isNotEmpty) {
      final r = (sigs.map((s) => s[0]).reduce((a, b) => a + b) / sigs.length).round();
      final g = (sigs.map((s) => s[1]).reduce((a, b) => a + b) / sigs.length).round();
      final b = (sigs.map((s) => s[2]).reduce((a, b) => a + b) / sigs.length).round();
      signature = [r, g, b];
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  Premium UI Widgets for Results Page
// ═══════════════════════════════════════════════════════════════════════════

/// Summary stat chip widget
class _SummaryChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final Color color;

  const _SummaryChip({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
        decoration: BoxDecoration(
          color: color.withOpacity(isDark ? 0.10 : 0.08),
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w700,
                fontSize: 20,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: TextStyle(
                color: isDark ? AppColors.textSecondary : AppColors.textDarkSecondary,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Section card wrapping a group of component tiles
class _SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  final int count;
  final bool isEmpty;
  final List<Widget> children;

  const _SectionCard({
    required this.title,
    required this.icon,
    required this.color,
    required this.count,
    required this.isEmpty,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.04) : Colors.white.withOpacity(0.80),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(
          color: isDark ? color.withOpacity(0.15) : color.withOpacity(0.12),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [color.withOpacity(0.12), color.withOpacity(0.04)],
              ),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(AppRadius.lg),
                topRight: Radius.circular(AppRadius.lg),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: color, size: 18),
                ),
                const SizedBox(width: 12),
                Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                    color: isDark ? AppColors.textPrimary : AppColors.textDarkPrimary,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '$count',
                    style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
          // Body
          if (isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'None detected',
                style: TextStyle(
                  color: isDark ? AppColors.textSecondary : AppColors.textDarkSecondary,
                  fontStyle: FontStyle.italic,
                ),
              ),
            )
          else
            ...children,
        ],
      ),
    );
  }
}

/// Individual component tile inside a SectionCard
class _ComponentTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final Widget? trailing;

  const _ComponentTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: iconColor, size: 16),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: isDark ? AppColors.textPrimary : AppColors.textDarkPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? AppColors.textSecondary : AppColors.textDarkSecondary,
                  ),
                ),
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// Map resistor band color names to actual display colors
Color _bandColor(String name) {
  switch (name.toLowerCase().trim()) {
    case 'black': return Colors.black;
    case 'brown': return const Color(0xFF8B4513);
    case 'red': return Colors.red;
    case 'orange': return Colors.orange;
    case 'yellow': return Colors.yellow;
    case 'green': return Colors.green;
    case 'blue': return Colors.blue;
    case 'violet': case 'purple': return Colors.purple;
    case 'grey': case 'gray': return Colors.grey;
    case 'white': return Colors.white;
    case 'gold': return const Color(0xFFDAA520);
    case 'silver': return const Color(0xFFC0C0C0);
    default: return Colors.grey;
  }
}
