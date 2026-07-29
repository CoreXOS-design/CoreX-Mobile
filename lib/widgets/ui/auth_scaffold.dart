import 'package:flutter/material.dart';
import '../../theme.dart';
import 'content_width.dart';
import 'glow_background.dart';

/// Shared chrome for auth flow screens. Provides:
/// - Glow background
/// - Transparent app bar (back arrow only)
/// - Large title + uppercase tracked subtitle
/// - Centred, max-width-constrained content column
///
/// Pair the form/button content as [child]. Use [GlowButton] for the
/// primary action so the visual language matches the login screen.
class AuthScaffold extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget child;
  final bool showBack;

  const AuthScaffold({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.showBack = true,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        automaticallyImplyLeading: showBack,
        iconTheme: IconThemeData(color: AppTheme.textPrimary(context)),
      ),
      body: GlowBackground(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            // Centred, not just constrained — a bare ConstrainedBox is ignored
            // under the tight width a scroll view passes down, which left the
            // auth column full-bleed on iPad.
            child: ContentWidth.form(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 16),
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.6,
                      height: 1.1,
                      color: AppTheme.textPrimary(context),
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      subtitle!,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        height: 1.45,
                        color: AppTheme.textSecondary(context),
                      ),
                    ),
                  ],
                  const SizedBox(height: 32),
                  child,
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Inline form error — kept consistent across auth screens.
class AuthError extends StatelessWidget {
  final String message;
  const AuthError(this.message, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded,
              size: 16, color: Color(0xFFEF4444)),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: Color(0xFFEF4444),
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
