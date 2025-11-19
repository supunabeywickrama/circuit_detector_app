class AppConfig {
  static const bool useMock = false; // set true if you want UI-only
  // PC LAN IP or emulator loopback:
  // Phone on Wi-Fi -> "http://192.168.X.X:8000"
  // Android emulator -> "http://10.0.2.2:8000"
  static const String baseUrl = "http://127.0.0.1:8000";
}