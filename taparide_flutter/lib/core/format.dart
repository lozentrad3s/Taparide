/// Small, dependency-free formatters for naira amounts, counts and times.
abstract final class Fmt {
  static String _group(int value) {
    final digits = value.abs().toString();
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
      buffer.write(digits[i]);
    }
    return '${value < 0 ? '-' : ''}$buffer';
  }

  /// ₦13,429,000
  static String naira(int amount) => '₦${_group(amount)}';

  /// ₦13.4M / ₦540K for tight spaces.
  static String nairaShort(int amount) {
    if (amount.abs() >= 1000000) return '₦${(amount / 1000000).toStringAsFixed(amount % 1000000 == 0 ? 0 : 1)}M';
    if (amount.abs() >= 10000) return '₦${(amount / 1000).round()}K';
    return naira(amount);
  }

  static String count(int value) => _group(value);

  static String compact(int value) {
    if (value >= 1000000) return '${(value / 1000000).toStringAsFixed(1)}M';
    if (value >= 10000) return '${(value / 1000).toStringAsFixed(value >= 100000 ? 0 : 1)}K';
    return _group(value);
  }

  static const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  static const _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  static String weekday(DateTime d) => _days[d.weekday - 1];
  static List<String> get weekdays => _days;

  /// 8:30 AM
  static String time(DateTime d) {
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final m = d.minute.toString().padLeft(2, '0');
    return '$h:$m ${d.hour < 12 ? 'AM' : 'PM'}';
  }

  /// Sep 27, 2026
  static String date(DateTime d) => '${_months[d.month - 1]} ${d.day}, ${d.year}';

  /// Today / Tomorrow / Sat, Oct 18
  static String day(DateTime d, {DateTime? now}) {
    final ref = now ?? DateTime.now();
    final today = DateTime(ref.year, ref.month, ref.day);
    final target = DateTime(d.year, d.month, d.day);
    final diff = target.difference(today).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Tomorrow';
    if (diff == -1) return 'Yesterday';
    return '${weekday(d)}, ${_months[d.month - 1]} ${d.day}';
  }

  static String dayTime(DateTime d) => '${day(d)} · ${time(d)}';

  static String minutes(int min) => min < 60 ? '$min mins' : '${min ~/ 60} h ${min % 60} min';

  /// "in 12 min", "2 h ago"
  static String relative(DateTime d, {DateTime? now}) {
    final diff = d.difference(now ?? DateTime.now());
    final mins = diff.inMinutes;
    if (mins.abs() < 1) return 'now';
    if (mins > 0) {
      if (mins < 60) return 'in $mins min';
      if (mins < 60 * 24) return 'in ${diff.inHours} h';
      return 'in ${diff.inDays} d';
    }
    final ago = -mins;
    if (ago < 60) return '$ago min ago';
    if (ago < 60 * 24) return '${ago ~/ 60} h ago';
    return '${ago ~/ (60 * 24)} d ago';
  }

  static String greeting(DateTime now) {
    if (now.hour < 12) return 'Good morning';
    if (now.hour < 17) return 'Good afternoon';
    return 'Good evening';
  }
}
