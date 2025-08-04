// main.dart – App Entry Point with Theme Support
import 'package:circuit_detector_app/pages/theme_provider.dart';
import 'package:flutter/material.dart';
import 'pages/home_page.dart';
import 'pages/settings_page.dart';
import 'pages/history_page.dart';
import 'package:provider/provider.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => ThemeProvider(),
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, child) {
          return MaterialApp(
            title: 'Circuit Component Detector ⚡',
            themeMode: themeProvider.themeMode,
            theme: ThemeData(
              colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
              useMaterial3: true,
              fontFamily: 'Roboto',
            ),
            darkTheme: ThemeData.dark(useMaterial3: true),
            debugShowCheckedModeBanner: false,
            home: const HomePage(),
            routes: {
              '/settings': (_) => const SettingsPage(),
              '/history': (_) => const HistoryPage(),
            },
          );
        },
      ),
    );
  }
}