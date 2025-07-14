import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'results_page.dart';

class CameraPage extends StatefulWidget {
  const CameraPage({super.key});

  @override
  State<CameraPage> createState() => _CameraPageState();
}

class _CameraPageState extends State<CameraPage> {
  final ImagePicker _picker = ImagePicker();
  File? _imageFile;
  bool _isLoading = false;

  Future<void> _pickImage(ImageSource source) async {
    final XFile? image = await _picker.pickImage(source: source);
    if (image == null) return;

    setState(() {
      _imageFile = File(image.path);
      _isLoading = true;
    });

    // Simulate delay before showing result
    await Future.delayed(const Duration(seconds: 1));
    setState(() => _isLoading = false);

    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ResultsPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Capture Image")),
      body: Center(
        child: _isLoading
            ? const CircularProgressIndicator()
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (_imageFile != null) Image.file(_imageFile!, height: 200),
                  const SizedBox(height: 20),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.camera),
                    label: const Text("Use Camera"),
                    onPressed: () => _pickImage(ImageSource.camera),
                  ),
                  const SizedBox(height: 10),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.photo),
                    label: const Text("Pick from Gallery"),
                    onPressed: () => _pickImage(ImageSource.gallery),
                  ),
                ],
              ),
      ),
    );
  }
}
