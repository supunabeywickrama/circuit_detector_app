// lib/pages/results_page.dart
import 'dart:io';

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

  /// All detections merged (for text summary)
  final List<Map<String, dynamic>> _allComponents = [];

  /// Per-image detections: path -> detections
  final Map<String, List<Map<String, dynamic>>> _detectionsPerPath = {};

  /// Per-image original size from backend: path -> Size(width, height)
  final Map<String, Size> _imageSizesPerPath = {};

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
          // Fallback to per-image single detection
          debugPrint("[ResultsPage] multi detection failed -> falling back: $e");
          await _runSingleDetections();
        }
      } else {
        await _runSingleDetections();
      }

      debugPrint("Total detections across images: ${_allComponents.length}");

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

  /// Run single-image detection for each image (original behavior).
  Future<void> _runSingleDetections() async {
    _detectionsPerPath.clear();
    _allComponents.clear();
    _imageSizesPerPath.clear();

    for (final path in imagePaths) {
      final json = await ApiService.detectSingle(path);

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
      }

      _detectionsPerPath[path] = comps;
      _allComponents.addAll(comps);
    }
  }

  /// Try to call ApiService.detectMulti(...) and if it fails or returns unexpected JSON,
  /// fall back to calling detectSingle for each image.
  Future<void> _runMultiDetectionWithFallback() async {
    _detectionsPerPath.clear();
    _allComponents.clear();
    _imageSizesPerPath.clear();

    // init per-path lists
    for (final p in imagePaths) _detectionsPerPath[p] = [];

    dynamic json;
    try {
      // NOTE: ApiService.detectMulti must be implemented. If not, this will throw/noSuchMethod.
      json = await ApiService.detectMulti(imagePaths);
    } catch (e) {
      debugPrint("[ResultsPage] detectMulti call threw: $e");
      // Re-throw so caller falls back to single detections
      rethrow;
    }

    // If backend returned null or non-map, fallback
    if (json == null || json is! Map<String, dynamic>) {
      debugPrint("[ResultsPage] detectMulti returned null/unexpected, falling back to single calls");
      // Do single-image detections instead
      await _runSingleDetections();
      return;
    }

    final Map<String, dynamic> mapJson = json as Map<String, dynamic>;

    // If backend provided "components" aggregated across images (preferred)
    if (mapJson.containsKey("components") && mapJson["components"] is List) {
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

      // Each component should include "views": list of {image_index, bbox}
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

        // add to master components
        _allComponents.add({
          "id": id,
          "type": type,
          "confidence": confidence,
          "extra": extra,
          "views": views,
        });

        // populate per-image lists
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
    } else {
      // No aggregated components — fall back to single-image style structure
      debugPrint("[ResultsPage] detectMulti returned no components key; attempting per-image fallback");
      await _runSingleDetections();
    }
  }

  /// Save the current detection summary to local history via HistoryStorage.
  /// Now saves `all_components` so history page can show full categorized counts.
  Future<void> _saveCurrentDetectionToHistory() async {
    try {
      if (_allComponents.isEmpty) return; // nothing to save

      // Build resistors list (legacy view): take extra.value if present
      final resistors = _allComponents.where((c) {
        final t = (c["type"] as String? ?? "").toLowerCase();
        return t.startsWith("resistor");
      }).map((r) {
        final extra = (r["extra"] as Map?) ?? {};
        final value = (extra["value"] != null && extra["value"].toString().isNotEmpty) ? extra["value"].toString() : "value N/A";
        return value;
      }).toList();

      // Build IC list (legacy): use OCR if available
      final ics = _allComponents.where((c) {
        final t = (c["type"] as String? ?? "").toLowerCase();
        return t == "ic";
      }).map((ic) {
        final extra = (ic["extra"] as Map?) ?? {};
        final ocr = (extra["ocr"] != null && extra["ocr"].toString().isNotEmpty) ? extra["ocr"].toString() : "unreadable";
        return ocr;
      }).toList();

      // Build counts summary map
      final Map<String, int> counts = {};
      for (final c in _allComponents) {
        final key = (c["type"] ?? "unknown").toString();
        counts[key] = (counts[key] ?? 0) + 1;
      }

      // Prepare entry — include full `all_components` so HistoryPage can categorize correctly
      final entry = <String, dynamic>{
        'timestamp': DateTime.now().toIso8601String(),
        'resistors': resistors,
        'ics': ics,
        'thumbnailPath': imagePaths.isNotEmpty ? imagePaths.first : null,
        'notes': null,
        'all_components': _allComponents.map((c) {
          // sanitize to ensure JSON-serializable basic types
          return {
            'type': c['type'],
            'bbox': c['bbox'],
            'confidence': c['confidence'],
            'extra': c['extra'],
            if (c.containsKey('views')) 'views': c['views'],
            if (c.containsKey('id')) 'id': c['id'],
          };
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
                return Text(
                  "• Resistor → ${val.toString().isEmpty ? "value N/A" : val}  (conf: $conf)",
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
                return Row(
                  children: [
                    Expanded(
                      child: Text(
                        "• IC → ${ocr.toString().isEmpty ? "unreadable" : ocr}  (conf: $conf)",
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
                return Text("• $t  (conf: $conf)");
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
