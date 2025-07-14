import 'package:flutter/material.dart';

class HistoryPage extends StatelessWidget {
  const HistoryPage({super.key});

  @override
  Widget build(BuildContext context) {
    final List<Map<String, dynamic>> dummyHistory = [
      {
        'timestamp': '2025-07-14 14:30',
        'resistors': ['100kΩ', '47kΩ'],
        'ics': ['NE555']
      },
      {
        'timestamp': '2025-07-13 09:10',
        'resistors': ['220Ω'],
        'ics': ['IC Unreadable']
      },
    ];

    return Scaffold(
      appBar: AppBar(title: const Text("📜 Scan History")),
      body: ListView.separated(
        padding: const EdgeInsets.all(16.0),
        itemCount: dummyHistory.length,
        separatorBuilder: (_, __) => const Divider(),
        itemBuilder: (context, index) {
          final entry = dummyHistory[index];
          return ListTile(
            leading: const Icon(Icons.history, color: Colors.blue),
            title: Text("📅 ${entry['timestamp']}"),
            subtitle: Text(
              "🟡 Resistors: ${entry['resistors'].join(', ')}\n🔵 ICs: ${entry['ics'].join(', ')}",
            ),
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Preview not implemented yet.')),
              );
            },
          );
        },
      ),
    );
  }
}
