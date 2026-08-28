import 'package:flutter/material.dart';

import 'announcements.dart';

final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

bool openAnnouncementFromNotification(String notificationId) {
  final navigator = rootNavigatorKey.currentState;
  if (navigator == null || notificationId.trim().isEmpty) return false;

  navigator.push(
    MaterialPageRoute<void>(
      builder: (_) =>
          AnnouncementsPage(initialNotificationId: notificationId.trim()),
    ),
  );
  return true;
}
