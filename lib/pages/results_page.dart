import 'dart:io';

import 'package:flutter/material.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';

import '../services/api_service.dart';

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
  final List<Map<String, dynamic>> _allComponents = [];
  List<Map<String, dynamic>> _detectionsForFirst = []; // for drawing boxes

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
      _detectionsForFirst = [];
    });

    try {
      if (imagePaths.isEmpty) {
        setState(() {
          _loading = false;
          _error = "No image to process.";
        });
        return;
      }

      // 🔹 Call backend for the FIRST image
      final json = await ApiService.detectSingle(imagePaths.first);

      final blurred = json["blurred"] == true;
      _anyBlurred = blurred;

      final detectionsRaw = json["detections"];
      List<Map<String, dynamic>> comps = [];

      if (detectionsRaw is List) {
        comps = detectionsRaw.map<Map<String, dynamic>>((e) {
          // raw detection from backend
          final raw = Map<String, dynamic>.from(e as Map);

          final label = (raw["label"] ?? "").toString();
          final conf = (raw["confidence"] ?? 0.0) as num;

          final bboxRaw = raw["bbox"];
          List<double> bbox;
          if (bboxRaw is List) {
            bbox = bboxRaw
                .map((v) => (v as num).toDouble())
                .toList(); // [x1,y1,x2,y2]
          } else {
            bbox = const <double>[];
          }

          final extraRaw = raw["extra"];
          final extra = (extraRaw is Map)
              ? Map<String, dynamic>.from(extraRaw as Map)
              : <String, dynamic>{};

          // 🔁 Normalize to the structure the UI expects
          return {
            "type": label,
            "bbox": bbox,
            "confidence": conf.toDouble(),
            "extra": extra,
          };
        }).toList();
      }

      _allComponents.addAll(comps);
      _detectionsForFirst = comps;

      debugPrint("Detections count (parsed): ${_allComponents.length}");

      setState(() {
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  List<Map<String, dynamic>> _byType(String startsWith) {
    return _allComponents
        .where((c) =>
            (c["type"] as String? ?? "")
                .toLowerCase()
                .startsWith(startsWith.toLowerCase()))
        .toList();
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
              setState(() {
                imagePaths.removeAt(index);
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

  /// Draw image with YOLO boxes (we assume bbox coords are in original pixels)
  Widget _buildDetectionImage(File imageFile, List<Map<String, dynamic>> comps) {
    return Stack(
      children: [
        Image.file(
          imageFile,
          height: 200,
          width: double.infinity,
          fit: BoxFit.cover,
        ),
        ...comps.map((det) {
          final bbox = (det["bbox"] as List?) ?? const [];
          if (bbox.length != 4) return const SizedBox.shrink();

          final double x1 = (bbox[0] as num).toDouble();
          final double y1 = (bbox[1] as num).toDouble();
          final double x2 = (bbox[2] as num).toDouble();
          final double y2 = (bbox[3] as num).toDouble();

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
                    padding:
                        const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    child: Text(
                      "${det["type"] ?? "obj"} (${(((det["confidence"] ?? 0.0) as num) * 100).toStringAsFixed(0)}%)",
                      style:
                          const TextStyle(fontSize: 10, color: Colors.black),
                    ),
                  ),
                ),
              ),
            ),
          );
        })
      ],
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
      final ics = _allComponents
          .where((c) =>
              (c["type"] as String? ?? "").toLowerCase() == "ic")
          .toList();
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

            const Text("🟡 Resistors:",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
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
            const Text("🔵 ICs:",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
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
                          contentPadding: EdgeInsets.symmetric(
                              horizontal: 8, vertical: 6),
                        ),
                      ),
                    ),
                  ],
                );
              }),

            const SizedBox(height: 22),
            const Text("🧩 Others:",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
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
              const Text("📸 Captured Images:",
                  style:
                      TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              ListView.builder(
                itemCount: imagePaths.length,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemBuilder: (context, index) {
                  final file = File(imagePaths[index]);
                  final comps = (index == 0)
                      ? _detectionsForFirst
                      : const <Map<String, dynamic>>[];

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
                              child: _buildDetectionImage(file, comps),
                            ),
                          ),
                          Positioned(
                            top: 8,
                            right: 8,
                            child: Row(
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.refresh,
                                      color: Colors.white),
                                  tooltip: "Retake",
                                  onPressed: () => _retakeImage(index),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete,
                                      color: Colors.red),
                                  tooltip: "Delete",
                                  onPressed: () =>
                                      _confirmDelete(index),
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
