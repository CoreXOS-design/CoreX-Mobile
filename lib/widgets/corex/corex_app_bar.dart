import 'package:flutter/material.dart';
import 'package:tabler_icons/tabler_icons.dart';

import '../../theme/corex_accent_theme.dart';
import '../../theme/corex_tokens.dart';

class CorexAppBar extends StatelessWidget implements PreferredSizeWidget {
  /// Null hides the avatar entirely — surfaces that reach the profile some
  /// other way (a "Me" tab, say) don't need an identity badge up here.
  final String? userInitials;
  final int unreadBadge;
  final VoidCallback? onMenuTap;
  final VoidCallback? onBellTap;
  final VoidCallback? onAvatarTap;
  final VoidCallback? onQrTap;

  const CorexAppBar({
    super.key,
    this.userInitials,
    this.unreadBadge = 0,
    this.onMenuTap,
    this.onBellTap,
    this.onAvatarTap,
    this.onQrTap,
  });

  @override
  Size get preferredSize => const Size.fromHeight(60);

  @override
  Widget build(BuildContext context) {
    final t = CorexAccentTheme.of(context);
    return SafeArea(
      bottom: false,
      child: SizedBox(
        height: 60,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              IconButton(
                onPressed: onMenuTap,
                icon: Icon(TablerIcons.menu_2,
                    color: CorexTokens.textPrimary(context)),
              ),
              const SizedBox(width: 4),
              _Wordmark(accent: t.accent),
              const Spacer(),
              if (onQrTap != null)
                IconButton(
                  tooltip: 'My QR Code',
                  onPressed: onQrTap,
                  icon: Icon(TablerIcons.qrcode,
                      color: CorexTokens.textPrimary(context)),
                ),
              // Only show the bell when a handler is wired — avoids a
              // dead/disabled icon on surfaces without a notifications screen.
              if (onBellTap != null)
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    IconButton(
                      onPressed: onBellTap,
                      icon: Icon(TablerIcons.bell,
                          color: CorexTokens.textPrimary(context)),
                    ),
                    if (unreadBadge > 0)
                      Positioned(
                        top: 10,
                        right: 10,
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: t.accent,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                  ],
                ),
              if (userInitials != null) ...[
                const SizedBox(width: 4),
                GestureDetector(
                  onTap: onAvatarTap,
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: t.accentSoft,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: t.accentBorder),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      userInitials!,
                      style: TextStyle(
                        color: t.accent,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Wordmark extends StatelessWidget {
  final Color accent;
  const _Wordmark({required this.accent});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'CoreX',
          style: TextStyle(
            color: CorexTokens.textPrimary(context),
            fontSize: 18,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.4,
          ),
        ),
        const SizedBox(width: 4),
        ShaderMask(
          shaderCallback: (rect) => LinearGradient(
            colors: [
              Color.lerp(accent, Colors.white, 0.15)!,
              accent,
            ],
          ).createShader(rect),
          child: const Text(
            'OS',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.4,
            ),
          ),
        ),
      ],
    );
  }
}
