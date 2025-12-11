// lib/services/api_service.dart
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart' as http_parser;

class ApiService {
  // Update this to your backend IP if needed
  static const String _baseUrl = "http://192.168.137.69:8000";
 //192.168.137.1
 //192.168.137.69
  /// Send a single image file to the /detect endpoint.
  /// [imagePath] - local filesystem path to the image.
  /// [conf] - optional confidence threshold (backend accepts `conf` form field).
  /// Returns the decoded JSON Map from the backend.
  static Future<Map<String, dynamic>> detectSingle(String imagePath, {double conf = 0.25, Duration timeout = const Duration(seconds: 30)}) async {
    final uri = Uri.parse("$_baseUrl/detect");
    final file = File(imagePath);

    if (!await file.exists()) {
      throw Exception("File not found: $imagePath");
    }

    final req = http.MultipartRequest('POST', uri)
      ..fields['conf'] = conf.toString()
      ..files.add(await http.MultipartFile.fromPath('file', imagePath));

    http.StreamedResponse streamed;
    try {
      streamed = await req.send().timeout(timeout);
    } catch (e) {
      throw Exception("Network error while uploading $imagePath: $e");
    }

    final resp = await http.Response.fromStream(streamed);

    // Helpful logging for debugging in debug console
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

  /// Send multiple images one-by-one and return list of backend responses.
  /// This is useful if your backend currently accepts only single-file POSTs.
  /// It performs the uploads concurrently (but bounded to avoid explosion).
  static Future<List<Map<String, dynamic>>> detectMultiple(List<String> imagePaths, {double conf = 0.25, int concurrency = 3}) async {
    if (imagePaths.isEmpty) return [];

    // Bound concurrency with simple queueing
    final results = <Map<String, dynamic>>[];
    final errors = <String>[];

    // Create an iterator
    final iterator = imagePaths.iterator;
    final active = <Future>[];

    Future<void> runOne() async {
      while (true) {
        String? path;
        // get next path in a safe sync block
        if (iterator.moveNext()) {
          path = iterator.current;
        } else {
          break;
        }

        try {
          final res = await detectSingle(path, conf: conf);
          results.add(res);
        } catch (e) {
          errors.add("Error for $path: $e");
        }
      }
    }

    // spawn up to [concurrency] workers
    for (var i = 0; i < concurrency; i++) {
      active.add(runOne());
    }

    await Future.wait(active);

    if (errors.isNotEmpty) {
      // Log but don't throw — caller can inspect returned list (partial results)
      print("ApiService.detectMultiple encountered errors:\n${errors.join('\n')}");
    }

    return results;
  }

  /// Helper: upload raw bytes (not currently used by UI, but handy)
  static Future<Map<String, dynamic>> detectBytes(List<int> bytes, {String filename = "upload.jpg", double conf = 0.25, Duration timeout = const Duration(seconds: 30)}) async {
    final uri = Uri.parse("$_baseUrl/detect");
    final req = http.MultipartRequest('POST', uri)
      ..fields['conf'] = conf.toString()
      ..files.add(http.MultipartFile.fromBytes('file', bytes, filename: filename, contentType: http_parser.MediaType('image', 'jpeg')));

    http.StreamedResponse streamed;
    try {
      streamed = await req.send().timeout(timeout);
    } catch (e) {
      throw Exception("Network error while uploading bytes: $e");
    }

    final resp = await http.Response.fromStream(streamed);
    print("DETECT status: ${resp.statusCode}");
    print("DETECT body: ${resp.body}");

    if (resp.statusCode != 200) {
      throw Exception("Backend error ${resp.statusCode}: ${resp.body}");
    }

    final decoded = jsonDecode(resp.body);
    if (decoded is! Map<String, dynamic>) {
      throw Exception("Unexpected JSON format (expected object): ${resp.body}");
    }

    return decoded;
  }

  static detectMulti(List<String> imagePaths) {}
}
