import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/gradients.dart';
import 'theme_provider.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool blurWarningEnabled = true;
  double confidenceThreshold = 0.25;

  void _confirmClearHistory() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Clear History'),
        content: const Text('Are you sure you want to clear all local scan history? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('History cleared.')),
              );
            },
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Settings'),
        leading: _buildBackButton(context),
      ),
      body: Stack(
        children: [
          // ── Background ──────────────────────────────────────────────
          SizedBox.expand(
            child: Image.asset(
              'assets/images/settings_bg.png',
              fit: BoxFit.cover,
              color: Colors.black.withOpacity(isDark ? 0.5 : 0.7),
              colorBlendMode: BlendMode.darken,
            ),
          ),

          // ── Content ─────────────────────────────────────────────────
          SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 30),
              children: [
                // ── Appearance ─────────────────────────────────────────
                _SectionHeader(title: 'Appearance', icon: Icons.palette_rounded),
                const SizedBox(height: 10),
                _GlassCard(
                  isDark: isDark,
                  child: Column(
                    children: [
                      _SettingRow(
                        icon: Icons.dark_mode_rounded,
                        iconColor: AppColors.primaryViolet,
                        title: 'Dark Mode',
                        trailing: Switch(
                          value: themeProvider.isDarkMode,
                          onChanged: (_) => themeProvider.toggleTheme(),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // ── Detection Settings ─────────────────────────────────
                _SectionHeader(title: 'Detection', icon: Icons.search_rounded),
                const SizedBox(height: 10),
                _GlassCard(
                  isDark: isDark,
                  child: Column(
                    children: [
                      _SettingRow(
                        icon: Icons.blur_on_rounded,
                        iconColor: AppColors.accentAmber,
                        title: 'Blur Warning',
                        subtitle: 'Warn when image quality is low',
                        trailing: Switch(
                          value: blurWarningEnabled,
                          onChanged: (v) => setState(() => blurWarningEnabled = v),
                        ),
                      ),
                      Divider(
                        height: 1,
                        color: isDark
                            ? AppColors.darkCardBorder.withOpacity(0.3)
                            : Colors.grey.shade200,
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    color: AppColors.accentEmerald.withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: const Icon(Icons.tune_rounded,
                                      color: AppColors.accentEmerald, size: 18),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Confidence Threshold',
                                        style: Theme.of(context).textTheme.titleMedium,
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        '${(confidenceThreshold * 100).toInt()}% minimum',
                                        style: Theme.of(context).textTheme.bodySmall,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            SliderTheme(
                              data: SliderTheme.of(context).copyWith(
                                activeTrackColor: AppColors.accentEmerald,
                                thumbColor: AppColors.accentEmerald,
                                inactiveTrackColor:
                                    AppColors.accentEmerald.withOpacity(0.2),
                              ),
                              child: Slider(
                                value: confidenceThreshold,
                                min: 0.10,
                                max: 0.90,
                                divisions: 16,
                                label: '${(confidenceThreshold * 100).toInt()}%',
                                onChanged: (v) =>
                                    setState(() => confidenceThreshold = v),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // ── Data & Storage ─────────────────────────────────────
                _SectionHeader(title: 'Data & Storage', icon: Icons.storage_rounded),
                const SizedBox(height: 10),
                _GlassCard(
                  isDark: isDark,
                  child: Column(
                    children: [
                      _SettingRow(
                        icon: Icons.delete_forever_rounded,
                        iconColor: AppColors.error,
                        title: 'Clear Scan History',
                        subtitle: 'Remove all saved detections',
                        onTap: _confirmClearHistory,
                        trailing: Icon(
                          Icons.chevron_right_rounded,
                          color: isDark
                              ? AppColors.textSecondary
                              : AppColors.textDarkSecondary,
                        ),
                      ),
                      Divider(
                        height: 1,
                        color: isDark
                            ? AppColors.darkCardBorder.withOpacity(0.3)
                            : Colors.grey.shade200,
                      ),
                      _SettingRow(
                        icon: Icons.file_download_rounded,
                        iconColor: AppColors.primaryCyan,
                        title: 'Export All Data',
                        subtitle: 'Save scans as JSON file',
                        onTap: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Export feature coming soon.')),
                          );
                        },
                        trailing: Icon(
                          Icons.chevron_right_rounded,
                          color: isDark
                              ? AppColors.textSecondary
                              : AppColors.textDarkSecondary,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // ── About ──────────────────────────────────────────────
                _SectionHeader(title: 'About', icon: Icons.info_outline_rounded),
                const SizedBox(height: 10),
                _GlassCard(
                  isDark: isDark,
                  child: Column(
                    children: [
                      _SettingRow(
                        icon: Icons.code_rounded,
                        iconColor: AppColors.primaryBlue,
                        title: 'Version',
                        trailing: Text(
                          '1.0.0',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: isDark
                                    ? AppColors.textSecondary
                                    : AppColors.textDarkSecondary,
                              ),
                        ),
                      ),
                      Divider(
                        height: 1,
                        color: isDark
                            ? AppColors.darkCardBorder.withOpacity(0.3)
                            : Colors.grey.shade200,
                      ),
                      _SettingRow(
                        icon: Icons.bolt_rounded,
                        iconColor: AppColors.accentAmber,
                        title: 'AI Models',
                        trailing: Text(
                          'YOLOv8 + GPT-4o',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: isDark
                                    ? AppColors.textSecondary
                                    : AppColors.textDarkSecondary,
                              ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBackButton(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 12),
      child: GestureDetector(
        onTap: () => Navigator.pop(context),
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.10),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white.withOpacity(0.12)),
          ),
          child: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 16),
        ),
      ),
    );
  }
}

// ── Section header ──────────────────────────────────────────────────────────
class _SectionHeader extends StatelessWidget {
  final String title;
  final IconData icon;

  const _SectionHeader({required this.title, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppColors.primaryCyan),
        const SizedBox(width: 8),
        Text(
          title.toUpperCase(),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: AppColors.primaryCyan,
                letterSpacing: 1.2,
              ),
        ),
      ],
    );
  }
}

// ── Glassmorphism card wrapper ──────────────────────────────────────────────
class _GlassCard extends StatelessWidget {
  final Widget child;
  final bool isDark;

  const _GlassCard({required this.child, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          decoration: BoxDecoration(
            color: isDark
                ? Colors.white.withOpacity(0.06)
                : Colors.white.withOpacity(0.75),
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(
              color: isDark
                  ? Colors.white.withOpacity(0.10)
                  : Colors.grey.shade300.withOpacity(0.5),
              width: 1,
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}

// ── Individual setting row ──────────────────────────────────────────────────
class _SettingRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  const _SettingRow({
    required this.icon,
    required this.iconColor,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: iconColor.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: iconColor, size: 18),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleMedium),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(subtitle!, style: Theme.of(context).textTheme.bodySmall),
                  ],
                ],
              ),
            ),
            if (trailing != null) trailing!,
          ],
        ),
      ),
    );
  }
}
