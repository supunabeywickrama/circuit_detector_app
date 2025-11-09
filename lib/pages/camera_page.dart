import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'results_page.dart';


class CameraPage extends StatefulWidget {
  const CameraPage({super.key});

  @override
  State<CameraPage> createState() => _CameraPageState();
}

class _CameraPageState extends State<CameraPage> {
  CameraController? _controller;
  bool _isCameraInitialized = false;

  final List<XFile> _capturedImages = [];
  static const int maxImages = 5;

  final Map<String, double> _aspectRatios = {
    '4:3': 4 / 3,
    '1:1': 1,
    '16:9': 16 / 9,
  };
  String _selectedAspect = '4:3';

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    try {
      final cameras = await availableCameras();
      _controller = CameraController(cameras[0], ResolutionPreset.medium);
      await _controller!.initialize();
      setState(() => _isCameraInitialized = true);
    } catch (e) {
      debugPrint("Camera initialization failed: $e");
    }
  }

  Future<void> _captureImage() async {
    if (!_controller!.value.isInitialized || _controller!.value.isTakingPicture) return;

    try {
      final image = await _controller!.takePicture();
      setState(() => _capturedImages.add(image));

      // 🔹 Mock blurry detection
      bool isBlurry = Random().nextDouble() < 0.3; // 30% chance

      if (isBlurry) {
        await _showBlurryWarning();
      }

      if (_capturedImages.length < maxImages) {
        _askForAnotherAngle();
      } else {
        _navigateToResults();
      }
    } catch (e) {
      debugPrint("Capture failed: $e");
    }
  }

  Future<void> _showBlurryWarning() async {
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("⚠ Blurry Image Detected"),
        content: const Text(
            "This photo appears blurry. You may want to retake it for better accuracy."),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text("OK")),
        ],
      ),
    );
  }

  void _askForAnotherAngle() async {
    bool takeAnother = await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Multi-angle Capture"),
        content: Text("Do you want to take another angle? (${_capturedImages.length}/$maxImages taken)"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("No")),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text("Yes")),
        ],
      ),
    );

    if (!takeAnother) {
      _navigateToResults();
    }
  }

  void _navigateToResults() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ResultsPage(
          imagePaths: _capturedImages.map((img) => img.path).toList(),
        ),
      ),
    );
  }

  void _resetCapture() {
    setState(() => _capturedImages.clear());
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    XFile? previewImage = _capturedImages.isNotEmpty ? _capturedImages.last : null;
    double aspect = _aspectRatios[_selectedAspect]!;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text("📷 Image Capture", style: TextStyle(fontWeight: FontWeight.bold)),
        leading: const BackButton(color: Colors.white),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                dropdownColor: Colors.black87,
                value: _selectedAspect,
                items: _aspectRatios.keys
                    .map((key) => DropdownMenuItem(
                          value: key,
                          child: Text(key, style: const TextStyle(color: Colors.white)),
                        ))
                    .toList(),
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _selectedAspect = value);
                  }
                },
              ),
            ),
          ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF4B2EF5), Color(0xFF00C9FF)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: _isCameraInitialized
              ? Column(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text(
                        "Capture the Circuit",
                        style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
                      ),
                    ),

                    // Camera Preview with Framing Box
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 30),
                      height: 250,
                      decoration: BoxDecoration(
                        color: Colors.black,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.2),
                            blurRadius: 10,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            previewImage == null
                                ? CameraPreview(_controller!)
                                : Image.file(File(previewImage.path), fit: BoxFit.cover),

                            // Framing Overlay Box
                            Align(
                              alignment: Alignment.center,
                              child: AspectRatio(
                                aspectRatio: aspect,
                                child: Container(
                                  decoration: BoxDecoration(
                                    border: Border.all(color: Colors.greenAccent, width: 2),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Buttons
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _buildRoundedButton(
                          label: "Retake",
                          color1: Colors.deepPurple,
                          color2: Colors.indigo,
                          icon: Icons.refresh,
                          onPressed: _resetCapture,
                        ),
                        _buildRoundedButton(
                          label: _capturedImages.length < maxImages ? "Capture" : "Process",
                          color1: Colors.teal,
                          color2: Colors.cyan,
                          icon: _capturedImages.length < maxImages ? Icons.camera_alt : Icons.check,
                          onPressed: _captureImage,
                        ),
                      ],
                    ),

                    // Tip
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 20),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.deepPurple.shade800.withOpacity(0.85),
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: Text(
                        "⚡ Tip: Take up to $maxImages angles for better recognition accuracy.",
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                  ],
                )
              : const Center(child: CircularProgressIndicator()),
        ),
      ),
    );
  }

  Widget _buildRoundedButton({
    required String label,
    required Color color1,
    required Color color2,
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [color1, color2]),
        borderRadius: BorderRadius.circular(30),
      ),
      child: ElevatedButton.icon(
        icon: Icon(icon, color: Colors.white),
        label: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          child: Text(label, style: const TextStyle(fontSize: 16)),
        ),
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
        ),
      ),
    );
  }
}
