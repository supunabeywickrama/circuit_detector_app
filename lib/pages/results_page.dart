import 'package:flutter/material.dart';

class ResultsPage extends StatelessWidget {
  const ResultsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Detection Results")),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("🟡 Resistors:", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            const Text("• Resistor 01 → 100kΩ"),
            const Text("• Resistor 02 → 47kΩ"),
            const SizedBox(height: 30),
            const Text("🔵 ICs:", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Row(
              children: [
                const Text("IC 01:", style: TextStyle(fontSize: 16)),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    decoration: const InputDecoration(
                      hintText: 'Enter IC value manually',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
