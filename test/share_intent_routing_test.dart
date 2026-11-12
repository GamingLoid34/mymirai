import 'package:flutter_test/flutter_test.dart';
import 'package:my_mirai/util/share_intent_routing.dart';

void main() {
  group('classifyShare', () {
    test('routes plain https URL to url flow', () {
      final d = classifyShare(pluginType: 'text', text: 'https://example.com/artikel');
      expect(d.kind, ShareRouteKind.url);
      expect(d.text, 'https://example.com/artikel');
    });

    test('routes http URL to url flow', () {
      final d = classifyShare(pluginType: 'url', text: 'http://example.com');
      expect(d.kind, ShareRouteKind.url);
    });

    test('routes free text to text flow', () {
      final d = classifyShare(pluginType: 'text', text: 'Kom ihåg att ringa Anna imorgon');
      expect(d.kind, ShareRouteKind.text);
      expect(d.text, 'Kom ihåg att ringa Anna imorgon');
    });

    test('routes text containing a URL plus more words to text flow', () {
      final d = classifyShare(pluginType: 'text', text: 'Kolla https://example.com senare');
      expect(d.kind, ShareRouteKind.text);
    });

    test('routes multi-line text to text flow even if first line is a URL', () {
      final d = classifyShare(pluginType: 'text', text: 'https://example.com\noch lite mer');
      expect(d.kind, ShareRouteKind.text);
    });

    test('routes image/file plugin types to file flow regardless of text', () {
      final d = classifyShare(pluginType: 'image', mimeType: 'image/jpeg');
      expect(d.kind, ShareRouteKind.file);
    });

    test('routes file plugin type to file flow', () {
      final d = classifyShare(pluginType: 'file', mimeType: 'application/pdf');
      expect(d.kind, ShareRouteKind.file);
    });

    test('empty text falls back to text flow (not url)', () {
      final d = classifyShare(pluginType: 'text', text: '');
      expect(d.kind, ShareRouteKind.text);
      expect(d.text, '');
    });

    test('non-http scheme is not treated as url', () {
      final d = classifyShare(pluginType: 'text', text: 'mailto:test@example.com');
      expect(d.kind, ShareRouteKind.text);
    });
  });
}
