import 'package:flutter/material.dart';

import 'push_notification_service.dart';

class NotificationSettingsPage extends StatefulWidget {
  const NotificationSettingsPage({super.key});

  @override
  State<NotificationSettingsPage> createState() =>
      _NotificationSettingsPageState();
}

class _NotificationSettingsPageState extends State<NotificationSettingsPage> {
  static const _blue = Color(0xFF173A8A);

  bool? _announcementsEnabled;
  bool _isUpdating = false;

  @override
  void initState() {
    super.initState();
    _loadPreference();
  }

  Future<void> _loadPreference() async {
    final enabled =
        await PushNotificationService.getAnnouncementNotificationsEnabled();
    if (!mounted) return;
    setState(() => _announcementsEnabled = enabled);
  }

  Future<void> _setAnnouncementsEnabled(bool enabled) async {
    if (_isUpdating) return;

    setState(() => _isUpdating = true);
    final didUpdate =
        await PushNotificationService.setAnnouncementNotificationsEnabled(
          enabled,
        );

    if (!mounted) return;
    setState(() {
      _isUpdating = false;
      if (didUpdate) _announcementsEnabled = enabled;
    });

    final message = didUpdate
        ? enabled
              ? 'Οι ειδοποιήσεις ανακοινώσεων ενεργοποιήθηκαν.'
              : 'Οι ειδοποιήσεις ανακοινώσεων απενεργοποιήθηκαν.'
        : enabled
        ? 'Ενεργοποίησε τις ειδοποιήσεις από τις ρυθμίσεις της συσκευής.'
        : 'Δεν μπορέσαμε να απενεργοποιήσουμε τις ειδοποιήσεις.';

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: _blue,
        title: const Text(
          'Ειδοποιήσεις',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 28, 20, 32),
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(18, 17, 12, 17),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x12000000),
                  blurRadius: 18,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEAFBE5),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.campaign_rounded,
                    color: Color(0xFF2D7D10),
                  ),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Ειδοποιήσεις ανακοινώσεων',
                        style: TextStyle(
                          color: Color(0xFF111827),
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      SizedBox(height: 5),
                      Text(
                        'Ενημέρωση όταν δημοσιεύεται νέα ανακοίνωση.',
                        style: TextStyle(
                          color: Color(0xFF6B7280),
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (_announcementsEnabled == null || _isUpdating)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: SizedBox.square(
                      dimension: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    ),
                  )
                else
                  Switch.adaptive(
                    value: _announcementsEnabled!,
                    activeTrackColor: const Color(0xFF2D7D10),
                    onChanged: _setAnnouncementsEnabled,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
