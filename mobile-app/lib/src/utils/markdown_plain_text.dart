/// Converts markdown to plain text for display where markdown is not rendered.
String markdownToPlainText(String markdown) {
  if (markdown.isEmpty) return markdown;
  String s = markdown;
  s = s.replaceAll(RegExp(r'^#{1,6}\s+', multiLine: true), '');
  s = s.replaceAll(RegExp(r'\*\*([^*]+)\*\*'), r'$1');
  s = s.replaceAll(RegExp(r'\*([^*]+)\*'), r'$1');
  s = s.replaceAll(RegExp(r'\[([^\]]+)\]\([^)]+\)'), r'$1');
  s = s.replaceAll(RegExp(r'`([^`]+)`'), r'$1');
  return s.trim();
}
