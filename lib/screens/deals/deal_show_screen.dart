import 'package:flutter/material.dart';
import '../../theme.dart';

/// Stub — full deal show coming in a later release. Present in PR 1 so that
/// cockpit pillar links have a destination (dead taps feel broken; a named
/// placeholder communicates "the link works, the screen is next").
class DealShowScreen extends StatelessWidget {
  final int dealId;

  const DealShowScreen({super.key, required this.dealId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Deal #$dealId'),
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: AppTheme.textPrimary(context)),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: const Color(0xFF3B82F6).withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.handshake_outlined, size: 34, color: Color(0xFF3B82F6)),
                ),
                const SizedBox(height: 16),
                Text(
                  'Deal details coming in next release',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: AppTheme.textPrimary(context),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'This pillar link is wired — the full show screen lands next.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: AppTheme.textMuted(context)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
