import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';

import 'camera_page.dart';
import 'history_page.dart';
import 'settings_page.dart';
import 'results_page.dart';
import '../theme/gradients.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  Future<void> _pickImageFromGallery(BuildContext context) async {
    final picker = ImagePicker();
    final List<XFile>? pickedFiles = await picker.pickMultiImage(imageQuality: 90);
    if (pickedFiles == null || pickedFiles.isEmpty) return;

    if (pickedFiles.length == 1) {
      final pickedFile = pickedFiles.first;
      CroppedFile? croppedFile = await ImageCropper().cropImage(
        sourcePath: pickedFile.path,
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: 'Crop Image',
            toolbarColor: AppColors.darkBg,
            toolbarWidgetColor: Colors.white,
            backgroundColor: AppColors.darkBg,
            lockAspectRatio: false,
          ),
          IOSUiSettings(title: 'Crop Image'),
        ],
      );
      if (croppedFile != null) {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => ResultsPage(imagePaths: [croppedFile.path])),
        );
      }
      return;
    }

    final paths = pickedFiles.map((f) => f.path).toList();
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ResultsPage(imagePaths: paths)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                gradient: AppGradients.cyanBlue,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.bolt_rounded, color: Colors.white, size: 18),
            ),
            const SizedBox(width: 10),
            Text(
              'E-Component',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
            ),
          ],
        ),
        actions: [
          _GlassIconButton(
            icon: Icons.history_rounded,
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const HistoryPage()),
            ),
          ),
          const SizedBox(width: 4),
          _GlassIconButton(
            icon: Icons.settings_rounded,
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsPage()),
            ),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: Stack(
        children: [
          // ── Background image ─────────────────────────────────────────
          SizedBox.expand(
            child: Image.asset(
              isDark
                  ? 'assets/images/home_bg_premium.png'
                  : 'assets/images/home_page_bg.webp',
              fit: BoxFit.cover,
              color: Colors.black.withOpacity(isDark ? 0.3 : 0.15),
              colorBlendMode: BlendMode.darken,
            ),
          ),

          // ── Gradient overlay ─────────────────────────────────────────
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  (isDark ? AppColors.darkBg : Colors.white).withOpacity(0.85),
                ],
                stops: const [0.3, 1.0],
              ),
            ),
          ),

          // ── Content ──────────────────────────────────────────────────
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Spacer(flex: 2),

                  // ── Hero section ──────────────────────────────────────
                  Text(
                    'Detect Circuit\nComponents',
                    style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                          color: Colors.white,
                          height: 1.15,
                          fontSize: 36,
                        ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Point your camera at any PCB. AI identifies\nevery component and reads values instantly.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.white.withOpacity(0.7),
                          height: 1.5,
                        ),
                  ),

                  const Spacer(flex: 1),

                  // ── Action cards ──────────────────────────────────────
                  _ActionCard(
                    icon: Icons.camera_alt_rounded,
                    title: 'Capture Circuit Image',
                    subtitle: 'Take multi-angle photos with quality checks',
                    gradient: AppGradients.cyanBlue,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const CameraPage()),
                    ),
                  ),
                  const SizedBox(height: 14),

                  _ActionCard(
                    icon: Icons.photo_library_rounded,
                    title: 'Pick from Gallery',
                    subtitle: 'Select one or more existing images',
                    gradient: AppGradients.violetPurple,
                    onTap: () => _pickImageFromGallery(context),
                  ),
                  const SizedBox(height: 14),

                  _ActionCard(
                    icon: Icons.history_rounded,
                    title: 'Scan History',
                    subtitle: 'Browse and search past detections',
                    gradient: AppGradients.emeraldTeal,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const HistoryPage()),
                    ),
                  ),

                  const Spacer(flex: 2),

                  // ── Footer ────────────────────────────────────────────
                  Center(
                    child: Text(
                      'Powered by YOLOv8 + GPT-4o Vision',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Colors.white.withOpacity(0.35),
                          ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Glassmorphism action card ──────────────────────────────────────────────
class _ActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final LinearGradient gradient;
  final VoidCallback onTap;

  const _ActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.gradient,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.white.withOpacity(0.10),
                  Colors.white.withOpacity(0.04),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(
                color: Colors.white.withOpacity(0.12),
                width: 1,
              ),
            ),
            child: Row(
              children: [
                // Icon with gradient background
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    gradient: gradient,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    boxShadow: [
                      BoxShadow(
                        color: gradient.colors.first.withOpacity(0.4),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Icon(icon, color: Colors.white, size: 24),
                ),
                const SizedBox(width: 16),
                // Text
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.55),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.arrow_forward_ios_rounded,
                  color: Colors.white.withOpacity(0.3),
                  size: 16,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Small glass icon button for AppBar ─────────────────────────────────────
class _GlassIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;

  const _GlassIconButton({required this.icon, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.10),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white.withOpacity(0.12)),
        ),
        child: Icon(icon, color: Colors.white.withOpacity(0.8), size: 20),
      ),
    );
  }
}
