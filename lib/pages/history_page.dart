import 'dart:io';

import 'package:flutter/material.dart';

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  final List<Map<String, dynamic>> _historyList = [
    {
      'timestamp': '2025-07-14 14:30',
      'resistors': ['100kΩ', '47kΩ'],
      'ics': ['NE555'],
      'thumbnailPath': null, // Add image path if available
    },
    {
      'timestamp': '2025-07-13 09:10',
      'resistors': ['220Ω'],
      'ics': ['IC Unreadable'],
      'thumbnailPath': null,
    },
  ];

  void _deleteEntry(int index) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Delete Entry"),
        content: const Text("Are you sure you want to delete this record?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () {
              setState(() {
                _historyList.removeAt(index);
              });
              Navigator.pop(context);
            },
            child: const Text("Delete"),
          ),
        ],
      ),
    );
  }

  void _viewDetails(Map<String, dynamic> entry) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text("Scan from ${entry['timestamp']}"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (entry['thumbnailPath'] != null)
              Image.file(
                File(entry['thumbnailPath']),
                height: 150,
                fit: BoxFit.cover,
              ),
            const SizedBox(height: 10),
            Text("🟡 Resistors: ${entry['resistors'].join(', ')}"),
            Text("🔵 ICs: ${entry['ics'].join(', ')}"),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Close"),
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("📜 Scan History")),
      body: _historyList.isEmpty
          ? const Center(child: Text("No history available."))
          : ListView.separated(
              padding: const EdgeInsets.all(16.0),
              itemCount: _historyList.length,
              separatorBuilder: (_, __) => const Divider(),
              itemBuilder: (context, index) {
                final entry = _historyList[index];
                return ListTile(
                  leading: entry['thumbnailPath'] != null
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.file(
                            File(entry['thumbnailPath']),
                            width: 50,
                            height: 50,
                            fit: BoxFit.cover,
                          ),
                        )
                      : const Icon(Icons.image_not_supported,
                          size: 40, color: Colors.grey),
                  title: Text("📅 ${entry['timestamp']}"),
                  subtitle: Text(
                    "🟡 ${entry['resistors'].join(', ')}\n🔵 ${entry['ics'].join(', ')}",
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red),
                    onPressed: () => _deleteEntry(index),
                  ),
                  onTap: () => _viewDetails(entry),
                );
              },
            ),
    );
  }
}
