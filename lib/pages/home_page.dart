import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';

import 'camera_page.dart';
import 'history_page.dart';
import 'settings_page.dart';
import 'results_page.dart'; // Make sure this import points to your ResultsPage

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  Future<void> _pickImageFromGallery(BuildContext context) async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);

    if (pickedFile != null) {
      CroppedFile? croppedFile = await ImageCropper().cropImage(
        sourcePath: pickedFile.path,
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: 'Crop Image',
            toolbarColor: Colors.deepPurple,
            toolbarWidgetColor: Colors.white,
            lockAspectRatio: false,
          ),
          IOSUiSettings(
            title: 'Crop Image',
          ),
        ],
      );

      if (croppedFile != null) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ResultsPage(imagePaths: [croppedFile.path]),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text("E-Component Detector ⚡", style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: "Settings",
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsPage()),
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          // Background Image
          SizedBox.expand(
            child: Image.asset(
              "assets/images/home_page_bg.webp",
              fit: BoxFit.cover,
              color: Colors.black.withOpacity(0.25),
              colorBlendMode: BlendMode.darken,
            ),
          ),

          // Foreground content
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 30.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    "Welcome to",
                    style: TextStyle(fontSize: 22, color: Colors.white),
                  ),
                  const SizedBox(height: 5),
                  const Text(
                    "E-Component Detector",
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 40),

                  // Capture Button
                  _buildGradientButton(
                    text: 'Capture Circuit Image',
                    icon: Icons.camera_alt,
                    gradientColors: const [Color(0xFF00C6FF), Color(0xFF0072FF)],
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const CameraPage()),
                      );
                    },
                  ),
                  const SizedBox(height: 20),

                  // History Button
                  _buildGradientButton(
                    text: 'View Scan History',
                    icon: Icons.history,
                    gradientColors: const [Color(0xFF9F44D3), Color(0xFF6A3093)],
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const HistoryPage()),
                      );
                    },
                  ),
                  const SizedBox(height: 20),

                  // NEW: Pick from Gallery Button
                  _buildGradientButton(
                    text: 'Pick from Gallery',
                    icon: Icons.photo_library,
                    gradientColors: const [Color(0xFFFD6E6A), Color(0xFFFFA07A)],
                    onPressed: () => _pickImageFromGallery(context),
                  ),
                ],
              ),
            ),
          )
        ],
      ),
    );
  }

  // 🔧 Gradient Button Widget
  Widget _buildGradientButton({
    required String text,
    required IconData icon,
    required List<Color> gradientColors,
    required VoidCallback onPressed,
  }) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: gradientColors),
        borderRadius: BorderRadius.circular(15),
      ),
      child: ElevatedButton.icon(
        icon: Icon(icon, color: Colors.white),
        label: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Text(text, style: const TextStyle(fontSize: 18)),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          padding: const EdgeInsets.symmetric(horizontal: 20),
        ),
        onPressed: onPressed,
      ),
    );
  }
}
