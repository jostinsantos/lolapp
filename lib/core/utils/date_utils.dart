class AppDateUtils {
  static String formatYear(String? date) {
    if (date == null || date.length < 4) return '';
    return date.substring(0, 4);
  }
}
