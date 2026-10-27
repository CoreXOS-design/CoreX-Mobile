import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:tabler_icons/tabler_icons.dart';

import '../services/messaging_service.dart';
import '../theme.dart';

/// Shown on the notification settings screens while this phone blocks CoreX
/// notifications: the switches there do nothing until it is allowed again.
/// Empty otherwise. Re-checks when the person comes back from Settings.
class NotificationsBlockedNotice extends StatefulWidget {
  const NotificationsBlockedNotice({super.key});

  @override
  State<NotificationsBlockedNotice> createState() =>
      _NotificationsBlockedNoticeState();
}

class _NotificationsBlockedNoticeState extends State<NotificationsBlockedNotice>
    with WidgetsBindingObserver {
  final _messaging = MessagingService.instance;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _messaging.refreshPermissionStatus();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _messaging.refreshPermissionStatus();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: _messaging.notificationsBlocked,
      builder: (context, blocked, _) {
        if (!blocked) return const SizedBox.shrink();
        const tint = Color(0xFFF59E0B);
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            decoration: BoxDecoration(
              color: tint.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(AppTheme.radius),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Icon(TablerIcons.bell_off, size: 18, color: tint),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Notifications are turned off for CoreX on this phone, '
                      "so alerts can't reach you. Turn them on in your "
                      "phone's Settings.",
                      style: TextStyle(
                          fontSize: 13,
                          height: 1.4,
                          color: AppTheme.textPrimary(context)),
                    ),
                  ),
                ]),
                const Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: openAppSettings,
                    child: Text('Open Settings'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
