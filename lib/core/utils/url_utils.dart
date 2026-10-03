class UrlUtils {
  static bool isValid(String? url) {
    if (url == null || url.isEmpty) return false;
    final u = Uri.tryParse(url);
    return u != null && (u.isScheme('http') || u.isScheme('https'));
  }
}
