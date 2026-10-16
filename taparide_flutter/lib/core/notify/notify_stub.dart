/// Non-web builds: system notifications are not wired yet; reminders show in the app.
Future<bool> requestNotificationPermission() async => false;

void showSystemNotification(String title, String body) {}
