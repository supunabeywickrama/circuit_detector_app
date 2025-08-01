import 'dart:io';

import 'package:flutter/material.dart';

class ResultsPage extends StatelessWidget {
  final String? firstImagePath;
  final String? secondImagePath;

  const ResultsPage({
    Key? key,
    this.firstImagePath,
    this.secondImagePath,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Detection Results"),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("🟡 Resistors:",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              const Text("• Resistor 01 → 100kΩ"),
              const Text("• Resistor 02 → 47kΩ"),
              const SizedBox(height: 30),
              const Text("🔵 ICs:",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
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
              const SizedBox(height: 30),
              if (firstImagePath != null || secondImagePath != null)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("📸 Captured Images:",
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 10),
                    if (firstImagePath != null)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text("• Angle 1:"),
                          const SizedBox(height: 5),
                          Image.file(
                            File(firstImagePath!),
                            height: 200,
                          ),
                          const SizedBox(height: 20),
                        ],
                      ),
                    if (secondImagePath != null)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text("• Angle 2:"),
                          const SizedBox(height: 5),
                          Image.file(
                            File(secondImagePath!),
                            height: 200,
                          ),
                        ],
                      ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}
