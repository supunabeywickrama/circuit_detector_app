import 'package:flutter/material.dart';
import 'results_page.dart';

class CameraPage extends StatelessWidget {
  const CameraPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text("📷 Image Capture", style: TextStyle(fontWeight: FontWeight.bold)),
        leading: BackButton(color: Colors.white),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF4B2EF5), Color(0xFF00C9FF)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              // Title + Camera Icon
              Column(
                children: const [
                  SizedBox(height: 16),
                  Icon(Icons.camera_alt, size: 64, color: Colors.white),
                  SizedBox(height: 10),
                  Text(
                    "Capture the Circuit",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),

              // Fake Preview Box
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 30),
                height: 250,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  image: const DecorationImage(
                    image: AssetImage('assets/images/circuit_placeholder.png'),
                    fit: BoxFit.cover,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 10,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
              ),

              // Retake & Process Buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildRoundedButton(
                    label: "Retake",
                    color1: Colors.deepPurple,
                    color2: Colors.indigo,
                    icon: Icons.refresh,
                    onPressed: () {
                      // Implement camera reset
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text("Camera reset not implemented")),
                      );
                    },
                  ),
                  _buildRoundedButton(
                    label: "Process",
                    color1: Colors.teal,
                    color2: Colors.cyan,
                    icon: Icons.check,
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const ResultsPage()),
                      );
                    },
                  ),
                ],
              ),

              // Optional helper section
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 20),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.deepPurple.shade800.withOpacity(0.8),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: const Text(
                  "⚡ Want Examples?\nWould you like me to enhance accuracy with blur check and alternate angles?",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRoundedButton({
    required String label,
    required Color color1,
    required Color color2,
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [color1, color2]),
        borderRadius: BorderRadius.circular(30),
      ),
      child: ElevatedButton.icon(
        icon: Icon(icon, color: Colors.white),
        label: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          child: Text(label, style: const TextStyle(fontSize: 16)),
        ),
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
        ),
      ),
    );
  }
}
