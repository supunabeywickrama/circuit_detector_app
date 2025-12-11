// lib/services/api_service.dart
import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart' as http_parser;
import 'dart:math' as math;

/// API client that tries several candidate hosts (useful for real phone vs emulator).
class ApiService {
  // PRIMARY: your laptop where uvicorn runs (you provided this IP)
  static const String _primaryBase = "http://192.168.8.123:8000";

  // Candidate hosts tried in order. Primary first, then emulator loopbacks, then localhost.
  static final List<String> _candidateBaseUrls = [
    _primaryBase,
    "http://10.0.2.2:8000", // Android emulator -> host
    "http://10.0.3.2:8000", // Genymotion -> host
    "http://127.0.0.1:8000", // localhost (rarely useful on device)
  ];

  /// Internal: try POST multipart across candidate hosts until one succeeds.
  static Future<http.Response> _postMultipartWithHosts(
    String path,
    List<http.MultipartFile> files, {
    Map<String, String>? fields,
    Duration timeout = const Duration(seconds: 45),
  }) async {
    Exception? lastEx;
    for (final base in _candidateBaseUrls) {
      final uri = Uri.parse("$base$path");
      final req = http.MultipartRequest('POST', uri);
      if (fields != null) req.fields.addAll(fields);
      for (final f in files) req.files.add(f);

      try {
        final streamed = await req.send().timeout(timeout);
        final resp = await http.Response.fromStream(streamed);
        if (resp.statusCode >= 200 && resp.statusCode < 300) {
          // success
          return resp;
        } else {
          // server returned error (e.g. 4xx/5xx) — treat as failure but provide body for debugging
          throw Exception("HTTP ${resp.statusCode}: ${resp.body}");
        }
      } on Exception catch (e) {
        lastEx = e;
        // log and try next host
        print("[ApiService] POST $uri failed: $e");
        // short delay to avoid spamming network
        await Future.delayed(const Duration(milliseconds: 250));
        continue;
      }
    }
    throw Exception("All candidate hosts failed. Last error: ${lastEx ?? 'unknown'}");
  }

  /// Upload a single image file to /detect. Returns decoded JSON map.
  static Future<Map<String, dynamic>> detectSingle(
    String imagePath, {
    double conf = 0.25,
    Duration timeout = const Duration(seconds: 45),
  }) async {
    final file = File(imagePath);
    if (!await file.exists()) throw Exception("File not found: $imagePath");

    final bytes = await file.readAsBytes();
    final filename = imagePath.split(Platform.pathSeparator).last;
    final multipartFile = http.MultipartFile.fromBytes(
      'file',
      bytes,
      filename: filename,
      contentType: http_parser.MediaType('image', 'jpeg'),
    );

    http.Response resp;
    try {
      resp = await _postMultipartWithHosts(
        "/detect",
        [multipartFile],
        fields: {'conf': conf.toString()},
        timeout: timeout,
      );
    } catch (e) {
      final tried = _candidateBaseUrls.join(", ");
      throw Exception(
          "Network error while uploading $imagePath: $e\nTried hosts: $tried\nEnsure your phone and laptop are on the same Wi-Fi and uvicorn was started with --host 0.0.0.0.");
    }

    print("DETECT status: ${resp.statusCode}");
    print("DETECT body: ${resp.body}");

    if (resp.statusCode != 200) {
      throw Exception("Backend error ${resp.statusCode}: ${resp.body}");
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(resp.body);
    } catch (e) {
      throw Exception("Failed to parse JSON response: $e\nBody: ${resp.body}");
    }
    if (decoded is! Map<String, dynamic>) {
      throw Exception("Unexpected JSON format (expected object): ${resp.body}");
    }
    return decoded;
  }

  /// Try upload multiple files to /detect_multi (if backend supports it).
  /// If /detect_multi isn't available, falls back to per-file uploads (concurrent).
  /// Returns either Map (aggregated server response) or List<Map> per-file results.
  static Future<dynamic> detectMulti(
    List<String> imagePaths, {
    double conf = 0.25,
    Duration timeout = const Duration(seconds: 60),
  }) async {
    if (imagePaths.isEmpty) return <Map<String, dynamic>>[];

    // prepare files named file0, file1, ...
    final files = <http.MultipartFile>[];
    for (var i = 0; i < imagePaths.length; i++) {
      final path = imagePaths[i];
      final f = File(path);
      if (!await f.exists()) throw Exception("File not found: $path");
      final bytes = await f.readAsBytes();
      files.add(http.MultipartFile.fromBytes(
        'file$i',
        bytes,
        filename: 'file$i.jpg',
        contentType: http_parser.MediaType('image', 'jpeg'),
      ));
    }

    // first try /detect_multi
    try {
      final resp = await _postMultipartWithHosts("/detect_multi", files, fields: {'conf': conf.toString()}, timeout: timeout);
      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        final decoded = jsonDecode(resp.body);
        return decoded;
      }
    } catch (e) {
      print("[ApiService] /detect_multi failed: $e");
      // fall-through to per-file uploads
    }

    // FALLBACK: upload one-by-one with bounded concurrency
    final results = <Map<String, dynamic>>[];
    final errors = <String>[];
    final concurrency = math.min(3, imagePaths.length);
    final iterator = imagePaths.iterator;
    final active = <Future>[];

    Future<void> worker() async {
      while (true) {
        String? path;
        if (iterator.moveNext()) {
          path = iterator.current;
        } else {
          break;
        }
        try {
          final res = await detectSingle(path, conf: conf, timeout: timeout);
          results.add(res);
        } catch (e) {
          errors.add("Error for $path: $e");
        }
      }
    }

    for (var i = 0; i < concurrency; i++) active.add(worker());
    await Future.wait(active);

    if (errors.isNotEmpty) {
      print("ApiService.detectMulti errors:\n${errors.join('\n')}");
    }

    return results;
  }

  /// Upload raw bytes as a single file (helper).
  static Future<Map<String, dynamic>> detectBytes(
    List<int> bytes, {
    String filename = "upload.jpg",
    double conf = 0.25,
    Duration timeout = const Duration(seconds: 45),
  }) async {
    final multipartFile = http.MultipartFile.fromBytes('file', bytes, filename: filename, contentType: http_parser.MediaType('image', 'jpeg'));
    http.Response resp;
    try {
      resp = await _postMultipartWithHosts("/detect", [multipartFile], fields: {'conf': conf.toString()}, timeout: timeout);
    } catch (e) {
      final tried = _candidateBaseUrls.join(", ");
      throw Exception("Network error while uploading bytes: $e\nTried hosts: $tried");
    }

    if (resp.statusCode != 200) {
      throw Exception("Backend error ${resp.statusCode}: ${resp.body}");
    }

    final decoded = jsonDecode(resp.body);
    if (decoded is! Map<String, dynamic>) {
      throw Exception("Unexpected JSON format (expected object): ${resp.body}");
    }
    return decoded;
  }
}

// You may need math import used above:

