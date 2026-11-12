/// VO-10: ren routningslogik för delat innehåll (delad URL/text/fil).
/// Hålls fri från plugin-typer så den är enkel att enhetstesta.
enum ShareRouteKind { url, text, file }

class ShareRouteDecision {
  const ShareRouteDecision(this.kind, {this.text});

  final ShareRouteKind kind;

  /// Trimmad text — själva URL:en för [ShareRouteKind.url], anteckningstexten för [.text].
  final String? text;
}

/// Avgör hur ett delat objekt ska hanteras utifrån mime-typ och textinnehåll.
///
/// [mimeType] kan vara null (t.ex. rena textdelningar på vissa avsändare).
/// [text] är delningens råtextinnehåll om typen är text/url, annars null.
ShareRouteDecision classifyShare({
  required String pluginType,
  String? mimeType,
  String? text,
}) {
  final trimmed = text?.trim() ?? '';
  if (pluginType == 'text' || pluginType == 'url') {
    if (_looksLikeUrl(trimmed)) {
      return ShareRouteDecision(ShareRouteKind.url, text: trimmed);
    }
    return ShareRouteDecision(ShareRouteKind.text, text: trimmed);
  }
  return const ShareRouteDecision(ShareRouteKind.file);
}

bool _looksLikeUrl(String value) {
  if (value.isEmpty || value.contains(' ') || value.contains('\n')) {
    return false;
  }
  final uri = Uri.tryParse(value);
  if (uri == null) return false;
  return (uri.scheme == 'http' || uri.scheme == 'https') && uri.host.isNotEmpty;
}
