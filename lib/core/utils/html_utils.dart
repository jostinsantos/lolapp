class HtmlUtils {
  static String stripTags(String html) =>
      html.replaceAll(RegExp(r'<[^>]*>'), '');
}
