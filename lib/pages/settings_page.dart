import 'package:circuit_detector_app/pages/theme_provider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  int maxAngles = 3;
  String aspectRatio = '4:3';
  bool blurWarningEnabled = true;

  final List<String> aspectRatios = ['4:3', '1:1', '16:9'];

  void _confirmClearHistory() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Clear History"),
        content: const Text("Are you sure you want to clear all scan history?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("History cleared (mock).")),
              );
              // TODO: Add actual history clearing logic here
            },
            child: const Text("Clear"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);

    return Scaffold(
      appBar: AppBar(title: const Text('⚙️ Settings')),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: ListView(
          children: [
            SwitchListTile(
              title: const Text('🌙 Dark Mode'),
              value: themeProvider.isDarkMode,
              onChanged: (value) => themeProvider.toggleTheme(),
            ),
            const Divider(),

            ListTile(
              title: const Text('📷 Max Number of Angles'),
              subtitle: Text('$maxAngles image(s)'),
              trailing: SizedBox(
                width: 150,
                child: Slider(
                  value: maxAngles.toDouble(),
                  min: 1,
                  max: 5,
                  divisions: 4,
                  label: maxAngles.toString(),
                  onChanged: (value) {
                    setState(() {
                      maxAngles = value.toInt();
                    });
                  },
                ),
              ),
            ),
            const Divider(),

            ListTile(
              title: const Text('🖼️ Preferred Aspect Ratio'),
              trailing: DropdownButton<String>(
                value: aspectRatio,
                items: aspectRatios
                    .map((ratio) =>
                        DropdownMenuItem(value: ratio, child: Text(ratio)))
                    .toList(),
                onChanged: (value) {
                  setState(() {
                    aspectRatio = value!;
                  });
                },
              ),
            ),
            const Divider(),

            SwitchListTile(
              title: const Text('⚠️ Enable Image Blur Warning'),
              value: blurWarningEnabled,
              onChanged: (value) {
                setState(() {
                  blurWarningEnabled = value;
                });
              },
            ),
            const Divider(),

            ListTile(
              leading: const Icon(Icons.delete_forever, color: Colors.red),
              title: const Text('🗑️ Clear Scan History'),
              onTap: _confirmClearHistory,
            ),
          ],
        ),
      ),
    );
  }
}
