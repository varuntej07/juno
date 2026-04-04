import 'package:intl/intl.dart';

class AppDateUtils {
  AppDateUtils._();

  static final _timeFormat = DateFormat('h:mm a');
  static final _dateFormat = DateFormat('MMM d, yyyy');
  static final _dateTimeFormat = DateFormat('MMM d, yyyy h:mm a');
  static String formatTime(DateTime dt) => _timeFormat.format(dt.toLocal());
  static String formatDate(DateTime dt) => _dateFormat.format(dt.toLocal());
  static String formatDateTime(DateTime dt) => _dateTimeFormat.format(dt.toLocal());

  static String formatRelative(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);

    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return formatDate(dt);
  }

  static DateTime? tryParse(String? value) {
    if (value == null) return null;
    return DateTime.tryParse(value);
  }

  static String toIso(DateTime dt) => dt.toUtc().toIso8601String();
}
