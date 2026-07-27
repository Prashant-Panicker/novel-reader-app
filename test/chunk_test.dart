import 'package:flutter_test/flutter_test.dart';
import 'package:novel_reader/services/kimi_translation_service.dart';

void main() {
  group('KimiTranslationService.chunkText', () {
    test('returns empty list for empty input', () {
      expect(KimiTranslationService.chunkText('', maxChars: 100), isEmpty);
    });

    test('keeps short text as a single chunk', () {
      const text = 'Hello world.\n\nSecond paragraph.';
      final chunks = KimiTranslationService.chunkText(text, maxChars: 500);
      expect(chunks.length, 1);
      expect(chunks.first.contains('Hello world'), isTrue);
      expect(chunks.first.contains('Second paragraph'), isTrue);
    });

    test('splits on paragraph boundaries under maxChars', () {
      final paragraphs = List.generate(10, (i) => 'Paragraph number $i. ' * 5);
      final text = paragraphs.join('\n\n');
      final chunks = KimiTranslationService.chunkText(text, maxChars: 200);
      expect(chunks.length, greaterThan(1));
      for (final c in chunks) {
        expect(c.length, lessThanOrEqualTo(220)); // small slack for newlines
      }
      // All original paragraphs should still appear somewhere.
      for (final p in paragraphs) {
        final found = chunks.any((c) => c.contains(p.trim()));
        expect(found, isTrue, reason: 'Missing paragraph: $p');
      }
    });
  });
}
