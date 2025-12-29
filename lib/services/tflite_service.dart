// lib/services/tflite_service.dart
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as imglib;
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:tflite_flutter_helper/tflite_flutter_helper.dart';

class TFLiteService {
  Interpreter? _interpreter;
  List<String>? _labels;
  int inputWidth = 0;
  int inputHeight = 0;
  TfLiteType inputType = TfLiteType.float32;
  TfLiteType outputType = TfLiteType.float32;

  static final TFLiteService _instance = TFLiteService._internal();
  factory TFLiteService() => _instance;
  TFLiteService._internal();

  Future<void> loadModelFromAssets(String modelAsset, {String? labelsAsset}) async {
    final modelData = await rootBundle.load(modelAsset);
    final buffer = modelData.buffer;
    final opts = InterpreterOptions();
    opts.threads = 2;
    _interpreter = Interpreter.fromBuffer(buffer.asUint8List(), options: opts);
    final inputTensors = _interpreter!.getInputTensors();
    if (inputTensors.isNotEmpty) {
      final shape = inputTensors.first.shape;
      if (shape.length >= 3) {
        inputHeight = shape[1];
        inputWidth = shape[2];
      }
      inputType = inputTensors.first.type;
    }
    final outTensors = _interpreter!.getOutputTensors();
    if (outTensors.isNotEmpty) outputType = outTensors.first.type;
    if (labelsAsset != null) {
      final raw = await rootBundle.loadString(labelsAsset);
      _labels = raw.split('\n').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    }
  }

  void close() {
    _interpreter?.close();
    _interpreter = null;
  }

  Future<Map<String, dynamic>> detectImageFile(String imagePath, {double confThreshold = 0.25, int maxDetections = 200}) async {
    final f = File(imagePath);
    if (!f.existsSync()) throw Exception("Image not found: $imagePath");
    final bytes = await f.readAsBytes();
    final img = imglib.decodeImage(bytes);
    if (img == null) throw Exception("Failed to decode image");

    final originalW = img.width.toDouble();
    final originalH = img.height.toDouble();

    if (_interpreter == null) throw Exception("Interpreter not loaded. Call loadModelFromAssets(...) first.");

    final preprocessed = _preprocess(img);

    dynamic input;
    if (inputType == TfLiteType.float32) {
      // Use the TensorImage's internal buffer which provides a Float32List
      input = preprocessed.buffer.asFloat32List();
      final shape = [1, inputHeight, inputWidth, 3];
      // TensorImage.fromList does not exist in the helper API; the preprocessed TensorImage buffer is already suitable.
    }

    final ti = TensorImage.fromImage(img);
    final imageProcessor = ImageProcessorBuilder()
        .add(ResizeOp(inputHeight, inputWidth, ResizeMethod.BILINEAR))
        .add(NormalizeOp(0, 255)) // assumes model expects 0..1; if it expects -1..1 change to NormalizeOp(127.5,127.5)
        .build();
    imageProcessor.process(ti);

    final inputBuffer = ti.buffer;

    final outputs = <int, Object>{};
    final outputTensors = _interpreter!.getOutputTensors();
    for (var i = 0; i < outputTensors.length; i++) {
      final t = outputTensors[i];
      final shape = t.shape;
      final dtype = t.type;
      if (dtype == TfLiteType.float32) {
        outputs[i] = List.filled(shape.reduce((a, b) => a * b), 0.0);
      } else if (dtype == TfLiteType.uint8) {
        outputs[i] = List.filled(shape.reduce((a, b) => a * b), 0);
      } else {
        outputs[i] = List.filled(shape.reduce((a, b) => a * b), 0.0);
      }
    }

    try {
      _interpreter!.runForMultipleInputs([inputBuffer.asUint8List()], outputs);
    } catch (e) {
      // fallback: try single input/run where input is a float32 List shaped [1,h,w,3]
      final floatInput = _imageToFloatList(ti, inputHeight, inputWidth);
      final runOutputs = <Object>[];
      for (var t in outputTensors) {
        runOutputs.add(List.filled(t.shape.reduce((a, b) => a * b), 0.0));
      }
      try {
        _interpreter!.run(floatInput, runOutputs);
        // convert runOutputs into map-like outputs by index
        for (var i = 0; i < runOutputs.length; i++) {
          outputs[i] = runOutputs[i];
        }
      } catch (e2) {
        throw Exception("Interpreter run failed: $e / $e2");
      }
    }

    // Parse outputs heuristically
    final parsed = _parseOutputs(outputs, originalW.toInt(), originalH.toInt(), confThreshold, maxDetections);

    return {
      "detections": parsed,
      "image": {"width": originalW.toInt(), "height": originalH.toInt()},
      "blurred": false
    };
  }

  imglib.Image _resizeForInput(imglib.Image img) {
    return imglib.copyResize(img, width: inputWidth, height: inputHeight, interpolation: imglib.Interpolation.cubic);
  }

  TensorImage _preprocess(imglib.Image img) {
    final ti = TensorImage(inputType == TfLiteType.uint8 ? TfLiteType.uint8 : TfLiteType.float32);
    ti.loadImage(imglib.copyResize(img, width: inputWidth, height: inputHeight));
    final proc = ImageProcessorBuilder().add(ResizeOp(inputHeight, inputWidth, ResizeMethod.BILINEAR)).add(NormalizeOp(0, 255)).build();
    return proc.process(ti);
  }

  List<double> _imageToFloatList(TensorImage ti, int targetH, int targetW) {
    final buffer = ti.buffer;
    final bytes = buffer.asUint8List();
    final out = <double>[];
    for (var i = 0; i < bytes.length; i++) {
      out.add(bytes[i] / 255.0);
    }
    return out;
  }

  List<Map<String, dynamic>> _parseOutputs(Map<int, Object> outputs, int origW, int origH, double confThreshold, int maxDetections) {
    final List<Map<String, dynamic>> detections = [];
    // Try common formats: (A) single output [1, N, 6] or [1,N,7]  (x,y,w,h,score,class) OR (x1,y1,x2,y2,score,class)
    for (final entry in outputs.entries) {
      final out = entry.value;
      if (out is List) {
        final flat = out.cast<num>().map((e) => e.toDouble()).toList();
        // try to determine shape by dividing with known dims
        if (flat.length % 6 == 0) {
          final n = flat.length ~/ 6;
          for (int i = 0; i < n; i++) {
            final base = i * 6;
            final a = flat[base + 0];
            final b = flat[base + 1];
            final c = flat[base + 2];
            final d = flat[base + 3];
            final score = flat[base + 4];
            final cls = flat[base + 5].round();
            if (score < confThreshold) continue;
            double x1 = a, y1 = b, x2 = c, y2 = d;
            // heuristics: if values look like center+wh (small range), convert to x1,y1,x2,y2
            if (x2 <= 1.5 && y2 <= 1.5 && origW > 0 && origH > 0) {
              final cx = a * origW;
              final cy = b * origH;
              final w = c * origW;
              final h = d * origH;
              x1 = (cx - w / 2).clamp(0.0, origW.toDouble());
              y1 = (cy - h / 2).clamp(0.0, origH.toDouble());
              x2 = (cx + w / 2).clamp(0.0, origW.toDouble());
              y2 = (cy + h / 2).clamp(0.0, origH.toDouble());
            } else {
              // assume absolute pixel coords; if too large, clamp
              x1 = a.clamp(0.0, origW.toDouble());
              y1 = b.clamp(0.0, origH.toDouble());
              x2 = c.clamp(0.0, origW.toDouble());
              y2 = d.clamp(0.0, origH.toDouble());
            }
            final label = (_labels != null && cls >= 0 && cls < _labels!.length) ? _labels![cls] : cls.toString();
            detections.add({"type": label, "confidence": score, "bbox": [x1, y1, x2, y2], "extra": {}});
            if (detections.length >= maxDetections) break;
          }
          if (detections.isNotEmpty) return _nms(detections, 0.45);
        }
        // if length suggests shape [1,N,85] (e.g. COCO style)
        if (flat.length % 85 == 0) {
          final n = flat.length ~/ 85;
          for (int i = 0; i < n; i++) {
            final base = i * 85;
            final cx = flat[base + 0];
            final cy = flat[base + 1];
            final w = flat[base + 2];
            final h = flat[base + 3];
            final objectness = flat[base + 4];
            // class probs start at base+5
            double bestP = 0.0;
            int bestC = 0;
            for (int c = 0; c < 80; c++) {
              final p = flat[base + 5 + c];
              if (p > bestP) {
                bestP = p;
                bestC = c;
              }
            }
            final score = objectness * bestP;
            if (score < confThreshold) continue;
            final x1 = ((cx - w / 2) * origW).clamp(0.0, origW.toDouble());
            final y1 = ((cy - h / 2) * origH).clamp(0.0, origH.toDouble());
            final x2 = ((cx + w / 2) * origW).clamp(0.0, origW.toDouble());
            final y2 = ((cy + h / 2) * origH).clamp(0.0, origH.toDouble());
            final label = (_labels != null && bestC >= 0 && bestC < _labels!.length) ? _labels![bestC] : bestC.toString();
            detections.add({"type": label, "confidence": score, "bbox": [x1, y1, x2, y2], "extra": {}});
            if (detections.length >= maxDetections) break;
          }
          if (detections.isNotEmpty) return _nms(detections, 0.45);
        }
      }
    }

    return _nms(detections, 0.45);
  }

  List<Map<String, dynamic>> _nms(List<Map<String, dynamic>> dets, double iouThreshold) {
    if (dets.isEmpty) return dets;
    final out = <Map<String, dynamic>>[];
    dets.sort((a, b) => (b["confidence"] as double).compareTo(a["confidence"] as double));
    final used = List<bool>.filled(dets.length, false);
    for (int i = 0; i < dets.length; i++) {
      if (used[i]) continue;
      final a = dets[i];
      out.add(a);
      for (int j = i + 1; j < dets.length; j++) {
        if (used[j]) continue;
        if ((a["type"] == dets[j]["type"])) {
          final iou = _iou(a["bbox"] as List<double>, dets[j]["bbox"] as List<double>);
          if (iou > iouThreshold) used[j] = true;
        }
      }
    }
    return out;
  }

  double _iou(List<double> A, List<double> B) {
    final double x1 = max(A[0], B[0]);
    final double y1 = max(A[1], B[1]);
    final double x2 = min(A[2], B[2]);
    final double y2 = min(A[3], B[3]);
    final w = max(0.0, x2 - x1);
    final h = max(0.0, y2 - y1);
    final inter = w * h;
    final areaA = max(0.0, (A[2] - A[0])) * max(0.0, (A[3] - A[1]));
    final areaB = max(0.0, (B[2] - B[0])) * max(0.0, (B[3] - B[1]));
    final union = areaA + areaB - inter;
    if (union <= 0.0) return 0.0;
    return inter / union;
  }
}
