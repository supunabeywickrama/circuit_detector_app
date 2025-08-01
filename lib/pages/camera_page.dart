import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'results_page.dart';

class CameraPage extends StatefulWidget {
  const CameraPage({super.key});

  @override
  State<CameraPage> createState() => _CameraPageState();
}

class _CameraPageState extends State<CameraPage> {
  CameraController? _controller;
  XFile? _capturedImage;
  bool _isCameraInitialized = false;

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
      setState(() => _capturedImage = image);
    } catch (e) {
      debugPrint("Capture failed: $e");
    }
  }

  void _retakeImage() {
    setState(() => _capturedImage = null);
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text("📷 Image Capture", style: TextStyle(fontWeight: FontWeight.bold)),
        leading: const BackButton(color: Colors.white),
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

                    // Preview
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
                        child: _capturedImage == null
                            ? CameraPreview(_controller!)
                            : Image.file(File(_capturedImage!.path), fit: BoxFit.cover),
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
                          onPressed: _retakeImage,
                        ),
                        _buildRoundedButton(
                          label: _capturedImage == null ? "Capture" : "Process",
                          color1: Colors.teal,
                          color2: Colors.cyan,
                          icon: _capturedImage == null ? Icons.camera_alt : Icons.check,
                          onPressed: () {
                            if (_capturedImage == null) {
                              _captureImage();
                            } else {
                              Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => const ResultsPage()),
                              );
                            }
                          },
                        ),
                      ],
                    ),

                    // Optional helper note
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 20),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.deepPurple.shade800.withOpacity(0.85),
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: const Text(
                        "⚡ Tip: Ensure your camera is steady and focused for the best recognition results.",
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white),
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
