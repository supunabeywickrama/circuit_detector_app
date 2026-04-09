// lib/pages/camera_page.dart
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as imglib;
import 'package:image_cropper/image_cropper.dart';
import 'package:path_provider/path_provider.dart';

import '../theme/gradients.dart';
import 'results_page.dart';

class CameraPage extends StatefulWidget {
  const CameraPage({super.key});

  @override
  State<CameraPage> createState() => _CameraPageState();
}

class _CameraPageState extends State<CameraPage> with SingleTickerProviderStateMixin {
  CameraController? _controller;
  bool _isCameraInitialized = false;
  bool _isBusy = false;

  final List<XFile> _capturedImages = [];
  static const int maxImages = 5;

  // keep quality for each captured file path
  final Map<String, _ImageQualityResult> _qualityPerPath = {};

  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        debugPrint("No cameras available");
        return;
      }
      _controller = CameraController(cameras[0], ResolutionPreset.medium, enableAudio: false);
      await _controller!.initialize();
      if (!mounted) return;
      setState(() => _isCameraInitialized = true);
    } catch (e) {
      debugPrint("Camera initialization failed: $e");
    }
  }

  /// Capture -> crop (user) -> quality check -> keep/retake/finish
  Future<void> _captureImage() async {
    if (_isBusy) return;
    if (_controller == null || !_controller!.value.isInitialized || _controller!.value.isTakingPicture) return;

    setState(() => _isBusy = true);
    HapticFeedback.selectionClick();

    try {
      final XFile raw = await _controller!.takePicture();

      // Immediately open cropper for user to edit/crop before anything else.
      final croppedPath = await _cropImage(raw.path);

      // If user cancelled cropping, delete raw file and exit.
      if (croppedPath == null) {
        try {
          final f = File(raw.path);
          if (await f.exists()) await f.delete();
        } catch (_) {}
        setState(() => _isBusy = false);
        return;
      }

      // Proceed with quality checks using the cropped image path.
      final quality = await _analyzeImageQuality(croppedPath);

      // show quality dialog only when there is an issue (reasons not empty)
      if (!quality.passes) {
        final action = await _showQualityDialog(quality);
        if (action == _QualityAction.retake) {
          // user wants to retake — delete file and return
          try {
            final f = File(croppedPath);
            if (await f.exists()) await f.delete();
          } catch (_) {}
          setState(() => _isBusy = false);
          return;
        } else if (action == _QualityAction.keep) {
          await _addCapturedFile(XFile(croppedPath), quality: quality);
        } else if (action == _QualityAction.acceptAndFinish) {
          await _addCapturedFile(XFile(croppedPath), quality: quality);
          _navigateToResults();
          setState(() => _isBusy = false);
          return;
        } else {
          // fallback: keep
          await _addCapturedFile(XFile(croppedPath), quality: quality);
        }
      } else {
        await _addCapturedFile(XFile(croppedPath), quality: quality);
      }

      // After adding, propose take another angle (but let user choose)
      if (_capturedImages.length < maxImages) {
        final takeAnother = await _askForAnotherAngleAuto();
        if (!takeAnother) _navigateToResults();
      } else {
        _navigateToResults();
      }
    } catch (e) {
      debugPrint("Capture failed: $e");
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Capture failed.")));
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<String?> _cropImage(String srcPath) async {
    try {
      final croppedFile = await ImageCropper().cropImage(
        sourcePath: srcPath,
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: 'Crop & Adjust',
            toolbarColor: AppColors.darkBg,
            toolbarWidgetColor: Colors.white,
            activeControlsWidgetColor: AppColors.primaryCyan,
            backgroundColor: AppColors.darkBg,
            initAspectRatio: CropAspectRatioPreset.original,
            lockAspectRatio: false,
          ),
          IOSUiSettings(
            title: 'Crop & Adjust',
          ),
        ],
      );

      if (croppedFile == null) return null;

      // Cropper may return its own path. Copy to a temp file in app's cache to keep flow consistent.
      final bytes = await File(croppedFile.path).readAsBytes();
      final tmpDir = await getTemporaryDirectory();
      final id = DateTime.now().millisecondsSinceEpoch.toString();
      final outPath = '${tmpDir.path}/capture_cropped_$id.jpg';
      final outFile = File(outPath);
      await outFile.writeAsBytes(bytes);
      return outFile.path;
    } catch (e) {
      debugPrint("[crop] failed: $e");
      return null;
    }
  }

  Future<void> _addCapturedFile(XFile file, {required _ImageQualityResult quality}) async {
    setState(() {
      _capturedImages.add(file);
      _qualityPerPath[file.path] = quality;
    });

    final label = quality.passes ? "Saved" : "Saved (quality: ${quality.reasons.join(', ')})";
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("$label (#${_capturedImages.length})"), duration: const Duration(milliseconds: 900)));
  }

  Future<void> _replaceCapturedFile(int index) async {
    if (_isBusy) return;
    if (_controller == null || !_controller!.value.isInitialized || _controller!.value.isTakingPicture) return;
    setState(() => _isBusy = true);
    try {
      final XFile raw = await _controller!.takePicture();
      final croppedPath = await _cropImage(raw.path);
      if (croppedPath == null) {
        try {
          final f = File(raw.path);
          if (await f.exists()) await f.delete();
        } catch (_) {}
        setState(() => _isBusy = false);
        return;
      }
      final quality = await _analyzeImageQuality(croppedPath);
      if (!quality.passes) {
        final action = await _showQualityDialog(quality);
        if (action == _QualityAction.retake) {
          try {
            final f = File(croppedPath);
            if (await f.exists()) await f.delete();
          } catch (_) {}
          setState(() => _isBusy = false);
          return;
        } else if (action == _QualityAction.keep) {
          setState(() {
            _capturedImages[index] = XFile(croppedPath);
            _qualityPerPath[croppedPath] = quality;
          });
        } else if (action == _QualityAction.acceptAndFinish) {
          setState(() {
            _capturedImages[index] = XFile(croppedPath);
            _qualityPerPath[croppedPath] = quality;
          });
          _navigateToResults();
          setState(() => _isBusy = false);
          return;
        } else {
          setState(() {
            _capturedImages[index] = XFile(croppedPath);
            _qualityPerPath[croppedPath] = quality;
          });
        }
      } else {
        setState(() {
          _capturedImages[index] = XFile(croppedPath);
          _qualityPerPath[croppedPath] = quality;
        });
      }
    } catch (e) {
      debugPrint("Replace capture failed: $e");
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<_ImageQualityResult> _analyzeImageQuality(String path) async {
    try {
      final bytes = await File(path).readAsBytes();
      final im = imglib.decodeImage(bytes);
      if (im == null) return _ImageQualityResult.passes();

      final maxDim = 320;
      final w = im.width;
      final h = im.height;
      imglib.Image imSmall = im;
      if (max(w, h) > maxDim) {
        final scale = maxDim / max(w, h);
        imSmall = imglib.copyResize(im,
            width: (w * scale).round(), height: (h * scale).round(), interpolation: imglib.Interpolation.cubic);
      }
      return _evaluateImageForQuality(imSmall);
    } catch (e) {
      debugPrint("[Quality] analyze error: $e");
      return _ImageQualityResult.passes();
    }
  }

  // Use raw bytes to compute luminance and Laplacian variance (no getPixel/getLuminance calls)
  _ImageQualityResult _evaluateImageForQuality(imglib.Image im) {
    // Ensure 4-channel RGBA bytes
    final Uint8List bytes = im.getBytes();
    final int w = im.width;
    final int h = im.height;
    final int stride = 4; // RGBA

    // compute luminance map as double list
    final List<double> lum = List<double>.filled(w * h, 0.0);
    double sumL = 0.0;
    int ptr = 0;
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        // Guard against out-of-range though getBytes usually has enough data
        if (ptr + 2 >= bytes.length) break;
        final int r = bytes[ptr];
        final int g = bytes[ptr + 1];
        final int b = bytes[ptr + 2];
        // Rec. 709 luminance
        final double l = 0.2126 * r + 0.7152 * g + 0.0722 * b;
        lum[y * w + x] = l;
        sumL += l;
        ptr += stride;
      }
    }

    final int pixels = max(1, w * h);
    final double meanL = sumL / pixels;

    // Laplacian 3x3 kernel (compute on luminance)
    final List<double> lap = [];
    for (int y = 1; y < h - 1; y++) {
      for (int x = 1; x < w - 1; x++) {
        // indexes
        final double c = lum[y * w + x];
        final double up = lum[(y - 1) * w + x];
        final double down = lum[(y + 1) * w + x];
        final double left = lum[y * w + (x - 1)];
        final double right = lum[y * w + (x + 1)];
        final double val = (up + down + left + right) - 4.0 * c;
        lap.add(val.abs());
      }
    }

    final int validPixels = max(1, lap.length);
    final double meanLap = lap.fold(0.0, (a, b) => a + b) / validPixels;
    double varSum = 0.0;
    for (int i = 0; i < validPixels; i++) {
      final double d = lap[i] - meanLap;
      varSum += d * d;
    }
    final double variance = varSum / validPixels;

    // heuristics (tuned defaults)
    // Lower threshold -> more shots considered "blurry" (we want to flag true blurs)
    final double blurVarianceThreshold = 120.0; // tuned value, adjust as needed
    final bool isBlurry = variance < blurVarianceThreshold;

    // brightness thresholds
    final bool tooDark = meanL < 45.0;
    final bool tooBright = meanL > 240.0;

    final reasons = <String>[];
    if (isBlurry) reasons.add("blurry (low high-frequency content)");
    if (tooDark) reasons.add("too dark");
    if (tooBright) reasons.add("overexposed/too bright");

    return _ImageQualityResult(passes: !(isBlurry || tooDark || tooBright), variance: variance, meanLuminance: meanL, reasons: reasons);
  }

  Future<_QualityAction?> _showQualityDialog(_ImageQualityResult q) {
    final msg = StringBuffer();
    msg.writeln("Image quality warning:");
    if (q.reasons.isEmpty) {
      msg.writeln("- Unknown issue");
    } else {
      for (final r in q.reasons) msg.writeln("- $r");
    }
    msg.writeln("");
    msg.writeln("Variance: ${q.variance?.toStringAsFixed(1)}, Mean brightness: ${q.meanLuminance?.toStringAsFixed(1)}");

    return showDialog<_QualityAction>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("⚠ Image Quality Issue"),
        content: Text(msg.toString()),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, _QualityAction.retake), child: const Text("Retake")),
          TextButton(onPressed: () => Navigator.pop(context, _QualityAction.keep), child: const Text("Keep")),
          ElevatedButton(onPressed: () => Navigator.pop(context, _QualityAction.acceptAndFinish), child: const Text("Keep & Finish")),
        ],
      ),
    );
  }

  Future<bool> _askForAnotherAngleAuto() async {
    final takeAnother = await showModalBottomSheet<bool>(
      context: context,
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 14),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text("Angle ${_capturedImages.length} saved", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 8),
              Text("Take another angle for improved accuracy? (${_capturedImages.length}/$maxImages)"),
              const SizedBox(height: 12),
              Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                OutlinedButton.icon(onPressed: () => Navigator.pop(ctx, false), icon: const Icon(Icons.close), label: const Text("Finish")),
                ElevatedButton.icon(onPressed: () => Navigator.pop(ctx, true), icon: const Icon(Icons.camera_alt), label: const Text("Take Another")),
              ]),
              const SizedBox(height: 8),
            ]),
          ),
        );
      },
    );
    return takeAnother == true;
  }

  void _navigateToResults() {
    if (_capturedImages.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("No images to process.")));
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ResultsPage(imagePaths: _capturedImages.map((e) => e.path).toList()),
      ),
    );
  }

  Future<void> _openThumbnailActions(int index) async {
    final path = _capturedImages[index].path;
    final res = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) {
        return SafeArea(
          child: Wrap(
            children: [
              ListTile(leading: const Icon(Icons.remove_red_eye), title: const Text("View"), onTap: () => Navigator.pop(ctx, 'view')),
              ListTile(leading: const Icon(Icons.edit), title: const Text("Edit (crop)"), onTap: () => Navigator.pop(ctx, 'edit')),
              ListTile(leading: const Icon(Icons.refresh), title: const Text("Replace (retake)"), onTap: () => Navigator.pop(ctx, 'replace')),
              ListTile(leading: const Icon(Icons.arrow_left), title: const Text("Move Left"), onTap: () => Navigator.pop(ctx, 'left')),
              ListTile(leading: const Icon(Icons.arrow_right), title: const Text("Move Right"), onTap: () => Navigator.pop(ctx, 'right')),
              ListTile(leading: const Icon(Icons.delete, color: Colors.red), title: const Text("Delete", style: TextStyle(color: Colors.red)), onTap: () => Navigator.pop(ctx, 'delete')),
              ListTile(leading: const Icon(Icons.close), title: const Text("Close"), onTap: () => Navigator.pop(ctx, null)),
            ],
          ),
        );
      },
    );

    if (!mounted || res == null) return;

    if (res == 'view') {
      await showDialog(context: context, builder: (_) => Dialog(child: Image.file(File(path))));
    } else if (res == 'edit') {
      final newPath = await _cropImage(path);
      if (newPath != null) {
        final q = await _analyzeImageQuality(newPath);
        setState(() {
          _capturedImages[index] = XFile(newPath);
          _qualityPerPath.remove(path);
          _qualityPerPath[newPath] = q;
        });
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Edited shot saved"), duration: Duration(milliseconds: 900)));
      }
    } else if (res == 'replace') {
      await _replaceCapturedFile(index);
    } else if (res == 'left') {
      if (index > 0) {
        setState(() {
          final v = _capturedImages.removeAt(index);
          _capturedImages.insert(index - 1, v);
        });
      }
    } else if (res == 'right') {
      if (index < _capturedImages.length - 1) {
        setState(() {
          final v = _capturedImages.removeAt(index);
          _capturedImages.insert(index + 1, v);
        });
      }
    } else if (res == 'delete') {
      _removeCapturedAt(index);
    }
  }

  Future<void> _editResizeImageAt(int index) async {
    final XFile orig = _capturedImages[index];
    final newPath = await _cropImage(orig.path);
    if (newPath == null) return;
    final q = await _analyzeImageQuality(newPath);
    setState(() {
      _capturedImages[index] = XFile(newPath);
      _qualityPerPath.remove(orig.path);
      _qualityPerPath[newPath] = q;
    });
  }

  void _removeCapturedAt(int index) {
    final f = File(_capturedImages[index].path);
    try {
      if (f.existsSync()) f.deleteSync();
    } catch (_) {}
    _qualityPerPath.remove(_capturedImages[index].path);
    setState(() => _capturedImages.removeAt(index));
  }

  @override
  void dispose() {
    _controller?.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final XFile? previewImage = _capturedImages.isNotEmpty ? _capturedImages.last : null;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Capture', style: TextStyle(fontWeight: FontWeight.w600)),
        leading: Padding(
          padding: const EdgeInsets.only(left: 12),
          child: GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.10),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white.withOpacity(0.12)),
              ),
              child: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 16),
            ),
          ),
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 14),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              gradient: AppGradients.cyanBlue,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '${_capturedImages.length}/$maxImages',
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: Colors.white),
            ),
          ),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: _capturedImages.isNotEmpty
          ? Container(
              decoration: BoxDecoration(
                gradient: AppGradients.emeraldTeal,
                borderRadius: BorderRadius.circular(AppRadius.pill),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.accentEmerald.withOpacity(0.4),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: FloatingActionButton.extended(
                onPressed: _navigateToResults,
                backgroundColor: Colors.transparent,
                elevation: 0,
                label: const Text('Finish & Analyze', style: TextStyle(fontWeight: FontWeight.w600)),
                icon: const Icon(Icons.check_rounded),
              ),
            )
          : null,
      body: Container(
        decoration: const BoxDecoration(
          gradient: AppGradients.darkBackground,
        ),
        child: SafeArea(
          child: _isCameraInitialized
              ? Column(
                  children: [
                    const SizedBox(height: 4),
                    Text(
                      'Frame the circuit, then tap capture',
                      style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 13),
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.black,
                          borderRadius: BorderRadius.circular(AppRadius.xl),
                          boxShadow: [
                            BoxShadow(color: AppColors.primaryCyan.withOpacity(0.1), blurRadius: 20, offset: const Offset(0, 6)),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(AppRadius.xl),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              previewImage == null ? CameraPreview(_controller!) : Image.file(File(previewImage.path), fit: BoxFit.cover),
                              Align(
                                alignment: Alignment.center,
                                child: FractionallySizedBox(
                                  widthFactor: 0.92,
                                  heightFactor: 0.62,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      border: Border.all(color: AppColors.primaryCyan.withOpacity(0.6), width: 1.5),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                ),
                              ),
                              if (_isBusy) Container(color: Colors.black45, child: const Center(child: CircularProgressIndicator(color: AppColors.primaryCyan))),
                              Positioned(
                                left: 12,
                                bottom: 12,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withOpacity(0.5),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    'Even lighting • Fill frame • No reflections',
                                    style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 11),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Thumbnail strip
                    SizedBox(
                      height: 110,
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 250),
                        child: _capturedImages.isEmpty
                            ? Container(
                                key: const ValueKey('empty'),
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(horizontal: 20),
                                child: Center(
                                  child: Text(
                                    'No shots yet — take a photo to start',
                                    style: TextStyle(color: Colors.white.withOpacity(0.4)),
                                  ),
                                ),
                              )
                            : ListView.separated(
                                key: ValueKey('list_${_capturedImages.length}'),
                                scrollDirection: Axis.horizontal,
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                itemCount: _capturedImages.length,
                                separatorBuilder: (_, __) => const SizedBox(width: 8),
                                itemBuilder: (context, i) {
                                  final file = File(_capturedImages[i].path);
                                  final quality = _qualityPerPath[_capturedImages[i].path];
                                  final bool flagged = quality != null && !quality.passes;
                                  return GestureDetector(
                                    onTap: () => _openThumbnailActions(i),
                                    child: Container(
                                      width: 100,
                                      margin: const EdgeInsets.only(top: 6, bottom: 6),
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(AppRadius.md),
                                        border: Border.all(
                                          color: flagged
                                              ? AppColors.warning.withOpacity(0.5)
                                              : AppColors.primaryCyan.withOpacity(0.2),
                                        ),
                                        boxShadow: [
                                          BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 6, offset: const Offset(0, 3)),
                                        ],
                                      ),
                                      child: Stack(
                                        children: [
                                          ClipRRect(
                                            borderRadius: BorderRadius.circular(AppRadius.md),
                                            child: Image.file(file, width: 100, height: 100, fit: BoxFit.cover),
                                          ),
                                          Positioned(
                                            left: 6,
                                            top: 6,
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: Colors.black54,
                                                borderRadius: BorderRadius.circular(6),
                                              ),
                                              child: Text('#${i + 1}', style: const TextStyle(color: Colors.white, fontSize: 11)),
                                            ),
                                          ),
                                          if (flagged)
                                            Positioned(
                                              right: 6,
                                              top: 6,
                                              child: Tooltip(
                                                message: quality!.reasons.join(', '),
                                                child: Container(
                                                  padding: const EdgeInsets.all(5),
                                                  decoration: BoxDecoration(color: AppColors.warning, shape: BoxShape.circle),
                                                  child: const Icon(Icons.warning_amber_rounded, size: 14, color: Colors.black),
                                                ),
                                              ),
                                            ),
                                          Positioned(
                                            right: 6,
                                            bottom: 6,
                                            child: GestureDetector(
                                              onTap: () => _removeCapturedAt(i),
                                              child: Container(
                                                padding: const EdgeInsets.all(5),
                                                decoration: BoxDecoration(color: AppColors.error, shape: BoxShape.circle),
                                                child: const Icon(Icons.close_rounded, size: 14, color: Colors.white),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    // Controls bar
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              icon: const Icon(Icons.refresh_rounded, size: 18),
                              label: const Text('Reset'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppColors.textSecondary,
                                side: BorderSide(color: AppColors.darkCardBorder.withOpacity(0.4)),
                                padding: const EdgeInsets.symmetric(vertical: 12),
                              ),
                              onPressed: _capturedImages.isEmpty
                                  ? null
                                  : () {
                                      HapticFeedback.mediumImpact();
                                      _resetCapture();
                                    },
                            ),
                          ),
                          const SizedBox(width: 12),
                          // Capture button
                          GestureDetector(
                            onTap: _isBusy ? null : _captureImage,
                            child: SizedBox(
                              width: 84,
                              height: 84,
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  ScaleTransition(
                                    scale: Tween(begin: 1.0, end: 1.08).animate(
                                      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
                                    ),
                                    child: Container(
                                      width: 84,
                                      height: 84,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        gradient: AppGradients.cyanBlue,
                                        boxShadow: [
                                          BoxShadow(color: AppColors.primaryCyan.withOpacity(0.4), blurRadius: 16, offset: const Offset(0, 4)),
                                        ],
                                      ),
                                    ),
                                  ),
                                  Container(
                                    width: 64,
                                    height: 64,
                                    decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white),
                                    child: Icon(
                                      _capturedImages.length < maxImages ? Icons.camera_alt_rounded : Icons.check_rounded,
                                      color: AppColors.darkBg,
                                      size: 28,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text('${_capturedImages.length} shots', style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 13)),
                                const SizedBox(height: 6),
                                ElevatedButton.icon(
                                  icon: const Icon(Icons.send_rounded, size: 16),
                                  label: const Text('Analyze'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.primaryCyan,
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                  ),
                                  onPressed: _capturedImages.isEmpty ? null : _navigateToResults,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    // Tip bar
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 20),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.primaryCyan.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        border: Border.all(color: AppColors.primaryCyan.withOpacity(0.15)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.lightbulb_rounded, color: AppColors.primaryCyan.withOpacity(0.6), size: 16),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Take multiple angles for better matching accuracy',
                              style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                  ],
                )
              : Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(color: AppColors.primaryCyan),
                      const SizedBox(height: 16),
                      Text('Initializing camera...', style: TextStyle(color: Colors.white.withOpacity(0.5))),
                    ],
                  ),
                ),
        ),
      ),
    );
  }

  void _resetCapture() {
    for (final f in _capturedImages) {
      try {
        final fi = File(f.path);
        if (fi.existsSync()) fi.deleteSync();
      } catch (_) {}
    }
    _qualityPerPath.clear();
    setState(() => _capturedImages.clear());
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Reset captures")));
  }
}

/// Result of image quality checks
class _ImageQualityResult {
  final bool passes;
  final double? variance;
  final double? meanLuminance;
  final List<String> reasons;

  _ImageQualityResult({required this.passes, this.variance, this.meanLuminance, List<String>? reasons}) : reasons = reasons ?? [];

  factory _ImageQualityResult.passes() => _ImageQualityResult(passes: true);
}

enum _QualityAction { retake, keep, acceptAndFinish }
