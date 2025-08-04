import 'dart:io';

import 'package:flutter/material.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';

class ResultsPage extends StatefulWidget {
  final List<String> imagePaths;

  const ResultsPage({
    Key? key,
    required this.imagePaths,
  }) : super(key: key);

  @override
  State<ResultsPage> createState() => _ResultsPageState();
}

class _ResultsPageState extends State<ResultsPage> {
  late List<String> imagePaths;

  @override
  void initState() {
    super.initState();
    imagePaths = List.from(widget.imagePaths);
  }

  void _showZoomableImage(int initialIndex) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        child: Container(
          height: 400,
          child: PhotoViewGallery.builder(
            itemCount: imagePaths.length,
            pageController: PageController(initialPage: initialIndex),
            builder: (context, index) {
              return PhotoViewGalleryPageOptions(
                imageProvider: FileImage(File(imagePaths[index])),
              );
            },
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
    // 🔄 Replace this with actual navigation to camera with index reference.
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Retake logic not implemented. Index: $index")),
    );
  }

  void _shareResults() {
    // 📨 Share logic placeholder
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Share/export feature coming soon!")),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Detection Results"),
        actions: [
          IconButton(
            icon: const Icon(Icons.share),
            tooltip: "Export / Share Results",
            onPressed: _shareResults,
          )
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("🟡 Resistors:",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              const Text("• Resistor 01 → 100kΩ"),
              const Text("• Resistor 02 → 47kΩ"),
              const SizedBox(height: 30),
              const Text("🔵 ICs:",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              Row(
                children: [
                  const Text("IC 01:", style: TextStyle(fontSize: 16)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      decoration: const InputDecoration(
                        hintText: 'Enter IC value manually',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 30),

              /// 📸 Captured Image List
              if (imagePaths.isNotEmpty)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("📸 Captured Images:",
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 10),
                    ListView.builder(
                      itemCount: imagePaths.length,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemBuilder: (context, index) {
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
                                    child: Image.file(
                                      File(imagePaths[index]),
                                      height: 200,
                                      width: double.infinity,
                                      fit: BoxFit.cover,
                                    ),
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
                ),
            ],
          ),
        ),
      ),
    );
  }
}
