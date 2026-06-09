import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/branding.dart';
import '../theme.dart';
import '../providers/auth_provider.dart';
import '../widgets/ui/section_header.dart';
import '../widgets/ui/status_chip.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.user;
    final brand = BrandColors.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          child: Column(
            children: [
            const SizedBox(height: 12),
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: brand.defaultColor,
                borderRadius: BorderRadius.circular(24),
                boxShadow: AppTheme.brandGlow(brand.button, intensity: 0.3),
              ),
              child: Center(
                child: Text(
                  _initials(auth.userName),
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                    color: Branding.onColor(brand.defaultColor),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              auth.userName,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.4,
                color: AppTheme.textPrimary(context),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              user?['email'] ?? '',
              style: TextStyle(
                fontSize: 14,
                color: AppTheme.textSecondary(context),
              ),
            ),
            if (user?['role'] != null) ...[
              const SizedBox(height: 12),
              StatusChip(
                label: (user!['role'] as String).toUpperCase(),
                color: brand.button,
              ),
            ],
            const SizedBox(height: 32),
            const Align(
              alignment: Alignment.centerLeft,
              child: SectionHeader(label: 'Account'),
            ),
            const SizedBox(height: 12),
            _InfoCard(items: [
              _InfoRow(label: 'Name', value: auth.userName),
              _InfoRow(label: 'Email', value: user?['email'] ?? '-'),
              _InfoRow(label: 'Role', value: user?['role'] ?? '-'),
            ]),
          ],
          ),
        ),
      ),
    );
  }

  String _initials(String name) {
    final parts = name.trim().split(' ');
    if (parts.length >= 2) {
      return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    }
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }
}

class _InfoRow {
  final String label;
  final String value;
  const _InfoRow({required this.label, required this.value});
}

class _InfoCard extends StatelessWidget {
  final List<_InfoRow> items;
  const _InfoCard({required this.items});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: AppTheme.cardGradient(context),
        borderRadius: BorderRadius.circular(AppTheme.radius),
        boxShadow: AppTheme.softShadow(context),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Divider(
                    height: 1, color: AppTheme.borderColor(context)),
              ),
            Row(
              children: [
                SizedBox(
                  width: 80,
                  child: Text(
                    items[i].label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textMuted(context),
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    items[i].value,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary(context),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
