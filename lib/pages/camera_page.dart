import 'dart:io';
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

  XFile? _firstImage;
  XFile? _secondImage;
  bool _isCapturingSecond = false;

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

      if (!_isCapturingSecond) {
        setState(() => _firstImage = image);
        _askForSecondAngle();
      } else {
        setState(() => _secondImage = image);
        _navigateToResults();
      }
    } catch (e) {
      debugPrint("Capture failed: $e");
    }
  }

  void _askForSecondAngle() async {
    bool takeSecond = await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Multi-angle Capture"),
        content: const Text("Do you want to take another angle for better accuracy?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("No")),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text("Yes")),
        ],
      ),
    );

    if (takeSecond) {
      setState(() {
        _isCapturingSecond = true;
        _secondImage = null;
      });
    } else {
      _navigateToResults();
    }
  }

  void _navigateToResults() {
    if (_firstImage != null) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ResultsPage(
            firstImagePath: _firstImage!.path,
            secondImagePath: _secondImage?.path,
          ),
        ),
      );
    }
  }

  void _resetCapture() {
    setState(() {
      _firstImage = null;
      _secondImage = null;
      _isCapturingSecond = false;
    });
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    XFile? previewImage = _secondImage ?? _firstImage;

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
                        child: previewImage == null
                            ? CameraPreview(_controller!)
                            : Image.file(File(previewImage.path), fit: BoxFit.cover),
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
                          label: previewImage == null
                              ? "Capture"
                              : (_isCapturingSecond ? "Capture 2nd" : "Process"),
                          color1: Colors.teal,
                          color2: Colors.cyan,
                          icon: previewImage == null
                              ? Icons.camera_alt
                              : (_isCapturingSecond ? Icons.camera_alt_outlined : Icons.check),
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
                      child: const Text(
                        "⚡ Tip: Take multiple angles for better recognition accuracy.",
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
