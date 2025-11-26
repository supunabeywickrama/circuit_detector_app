// lib/services/api_service.dart
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

class ApiService {
  static const String _baseUrl = "http://172.19.44.45:8000"; // or your LAN IP

  static Future<Map<String, dynamic>> detectSingle(String imagePath) async {
    final uri = Uri.parse("$_baseUrl/detect");
    final req = http.MultipartRequest('POST', uri)
      ..files.add(await http.MultipartFile.fromPath('file', imagePath));

    final streamed = await req.send();
    final resp = await http.Response.fromStream(streamed);

    // Helpful logging
    print("DETECT status: ${resp.statusCode}");
    print("DETECT body: ${resp.body}");

    if (resp.statusCode != 200) {
      throw Exception("Backend error ${resp.statusCode}: ${resp.body}");
    }

    final decoded = jsonDecode(resp.body);
    if (decoded is! Map<String, dynamic>) {
      throw Exception("Unexpected JSON: ${resp.body}");
    }
    return decoded;
  }
}
