// lib/pages/results_page.dart
import 'dart:io';
import 'dart:async';
import 'dart:typed_data';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';

import '../services/api_service.dart';
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
          _error = "No image to process.";
        });
        return;
      }

      // If multiple images -> try multi-image endpoint but tolerate failures
      if (imagePaths.length > 1) {
        try {
          await _runMultiDetectionWithFallback();
        } catch (e) {
          debugPrint("[ResultsPage] multi detection failed -> falling back: $e");
          await _runSingleDetections();
        }
      } else {
        await _runSingleDetections();
      }

      // Build raw detections if not populated by multi endpoint
      if (_rawDetections.isEmpty) {
        int idx = 0;
        for (final path in imagePaths) {
          final comps = _detectionsPerPath[path] ?? [];
          for (final c in comps) {
            final bbox = (c['bbox'] is List) ? (c['bbox'] as List).map((e) => (e as num).toDouble()).toList() : <double>[];
            _rawDetections.add(_RawDetection(
              imageIndex: idx,
              imagePath: path,
              bbox: bbox,
              type: (c['type'] ?? 'unknown').toString(),
              confidence: (c['confidence'] is num) ? (c['confidence'] as num).toDouble() : 0.0,
              extra: (c['extra'] is Map) ? Map<String, dynamic>.from(c['extra'] as Map) : <String, dynamic>{},
            ));
          }
          idx++;
        }
      }

      // Group across images if multiple images exist and raw detections exist
      if (_rawDetections.isNotEmpty && imagePaths.length > 1) {
        await _groupDetectionsAcrossImages();
      } else {
        // No grouping needed: flatten per-path comps to _allComponents
        if (_allComponents.isEmpty) {
          for (final list in _detectionsPerPath.values) {
            _allComponents.addAll(list);
          }
        }
      }

      debugPrint("Total detections across images (after grouping): ${_allComponents.length}");

      setState(() {
        _loading = false;
      });

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
        throw Exception("Failed to detect for $path: $e");
      }

      if (json == null || json is! Map<String, dynamic>) {
        // Defensive: continue but ensure mapping exists
        debugPrint("[ResultsPage] unexpected response for $path: $json");
        _detectionsPerPath[path] = [];
        continue;
      }

      final blurred = json["blurred"] == true;
      if (blurred) _anyBlurred = true;

      // ---- image size ----
      final imgInfo = json["image"];
      if (imgInfo is Map) {
        final w = (imgInfo["width"] as num?)?.toDouble();
        final h = (imgInfo["height"] as num?)?.toDouble();
        if (w != null && h != null && w > 0 && h > 0) {
          _imageSizesPerPath[path] = Size(w, h);
        }
      }

      // ---- detections ----
      final detectionsRaw = json["detections"];
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

  @override
  Widget build(BuildContext context) {
    Widget body;

    if (_loading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_error != null) {
      body = Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error, color: Colors.red, size: 40),
            const SizedBox(height: 8),
            Text(
              "Failed to detect:\n$_error",
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: _runDetections,
              child: const Text("Retry"),
            ),
          ],
        ),
      );
    } else {
      final resistors = _byType("resistor");
      final ics = _allComponents.where((c) => (c["type"] as String? ?? "").toLowerCase() == "ic").toList();
      final others = _allComponents.where((c) {
        final t = (c["type"] as String? ?? "").toLowerCase();
        return !(t.startsWith("resistor") || t == "ic");
      }).toList();

      body = SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Total detections: ${_allComponents.length}",
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 8),

            if (_anyBlurred)
              Container(
                margin: const EdgeInsets.only(bottom: 14),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.amber.shade700,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  "⚠ Some images look blurry. You may want to retake for better accuracy.",
                  style: TextStyle(color: Colors.white),
                ),
              ),

            const Text(
              "🟡 Resistors:",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            if (resistors.isEmpty)
              const Text("• none")
            else
              ...resistors.map((r) {
                final val = r["extra"]?["value"] ?? "";
                final conf = (r["confidence"] ?? 0.0).toString();
                final source = _sourceLabelForComponent(r);
                return Text(
                  "• Resistor → ${val.toString().isEmpty ? "value N/A" : val}  (conf: $conf) — $source",
                );
              }),

            const SizedBox(height: 22),
            const Text(
              "🔵 ICs:",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            if (ics.isEmpty)
              const Text("• none")
            else
              ...ics.map((ic) {
                final ocr = ic["extra"]?["ocr"] ?? "";
                final conf = (ic["confidence"] ?? 0.0).toString();
                final source = _sourceLabelForComponent(ic);
                return Row(
                  children: [
                    Expanded(
                      child: Text(
                        "• IC → ${ocr.toString().isEmpty ? "unreadable" : ocr}  (conf: $conf) — $source",
                      ),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      width: 180,
                      child: TextField(
                        decoration: const InputDecoration(
                          hintText: 'Enter IC manually',
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                        ),
                      ),
                    ),
                  ],
                );
              }),

            const SizedBox(height: 22),
            const Text(
              "🧩 Others:",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            if (others.isEmpty)
              const Text("• none")
            else
              ...others.map((o) {
                final t = o["type"];
                final conf = (o["confidence"] ?? 0.0).toString();
                final source = _sourceLabelForComponent(o);
                return Text("• $t  (conf: $conf) — $source");
              }),

            const SizedBox(height: 28),
            if (imagePaths.isNotEmpty) ...[
              const Text(
                "📸 Captured Images:",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
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

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("• Angle ${index + 1}:"),
                      const SizedBox(height: 5),
                      Stack(
                        children: [
                          GestureDetector(
                            onTap: () => _showZoomableImage(index),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: AspectRatio(
                                aspectRatio: (imgSize != null && imgSize.width > 0 && imgSize.height > 0) ? imgSize.width / imgSize.height : 4 / 3,
                                child: _buildDetectionImage(
                                  file,
                                  comps,
                                  imgSize,
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            top: 8,
                            right: 8,
                            child: Row(
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.refresh, color: Colors.white),
                                  tooltip: "Retake",
                                  onPressed: () => _retakeImage(index),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete, color: Colors.red),
                                  tooltip: "Delete",
                                  onPressed: () => _confirmDelete(index),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                    ],
                  );
                },
              ),
            ],
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text("Detection Results"),
        actions: [
          IconButton(
            icon: const Icon(Icons.share),
            tooltip: "Export / Share Results",
            onPressed: _shareResults,
          ),
        ],
      ),
      body: body,
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
