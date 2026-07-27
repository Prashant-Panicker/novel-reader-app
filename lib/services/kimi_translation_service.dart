import 'package:dio/dio.dart';
import 'secure_storage_service.dart';

/// Thrown when a translation request cannot proceed because the user has
/// not yet configured their personal Kimi API key.
class MissingApiKeyException implements Exception {
  @override
  String toString() =>
      'No Kimi API key found. Please add your personal Moonshot API key in Settings.';
}

/// Thrown when the Moonshot API itself returns an error.
class KimiApiException implements Exception {
  final String message;
  final int? statusCode;
  KimiApiException(this.message, {this.statusCode});
  @override
  String toString() => 'Kimi API error: $message';
}

/// Talks to the user's personal Moonshot AI (Kimi) account to translate
/// novel text into natural English.
///
/// Never bundles or shares an API key — only uses the key the user pasted
/// into Settings, stored locally and encrypted via [SecureStorageService].
class KimiTranslationService {
  KimiTranslationService._();
  static final KimiTranslationService instance = KimiTranslationService._();

  static const String _baseUrl = 'https://api.moonshot.ai/v1';
  static const String _model = 'kimi-k2.6';

  static const String _systemPrompt =
      'You are an expert translator specializing in Chinese web novels '
      '(Wuxia, Xianxia, Xuanhuan, and modern web fiction). Translate the '
      'provided text into natural, high-quality English. Keep proper names '
      'in Pinyin (do not translate them literally). Ensure cultivation '
      'realms, techniques, and idioms fit progression-fantasy lore. '
      'Translate paragraph-by-paragraph without summarization. Preserve '
      'paragraph breaks. Do not add commentary or notes.';

  final Dio _dio = Dio(
    BaseOptions(
      baseUrl: _baseUrl,
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(minutes: 3),
      headers: {'Content-Type': 'application/json'},
    ),
  );

  /// Translates [rawText] into English using the user's own Kimi key.
  ///
  /// Long chapters are chunked by paragraphs (with clear markers) so the
  /// model stays within context limits and paragraph order is preserved
  /// for the bilingual reader.
  Future<String> translateText(String rawText, {int maxRetries = 2}) async {
    final apiKey = await SecureStorageService.instance.getApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      throw MissingApiKeyException();
    }

    final chunks = chunkText(rawText, maxChars: 1800);
    final translatedChunks = <String>[];

    for (var i = 0; i < chunks.length; i++) {
      final translated = await _translateChunkWithRetry(
        chunks[i],
        apiKey,
        maxRetries: maxRetries,
      );
      translatedChunks.add(translated);
    }

    return translatedChunks.join('\n\n');
  }

  Future<String> _translateChunkWithRetry(
    String chunk,
    String apiKey, {
    required int maxRetries,
  }) async {
    Object? lastError;
    for (var attempt = 0; attempt <= maxRetries; attempt++) {
      try {
        return await _translateChunk(chunk, apiKey);
      } on KimiApiException catch (e) {
        lastError = e;
        // Retry on rate-limit / transient server errors.
        final retryable = e.statusCode == 429 ||
            e.statusCode == 500 ||
            e.statusCode == 502 ||
            e.statusCode == 503;
        if (!retryable || attempt == maxRetries) rethrow;
        await Future<void>.delayed(Duration(seconds: 2 * (attempt + 1)));
      } on DioException catch (e) {
        lastError = e;
        if (attempt == maxRetries) {
          throw KimiApiException(e.message ?? 'Network error');
        }
        await Future<void>.delayed(Duration(seconds: 2 * (attempt + 1)));
      }
    }
    throw KimiApiException(lastError?.toString() ?? 'Unknown translation error');
  }

  Future<String> _translateChunk(String chunk, String apiKey) async {
    try {
      final response = await _dio.post(
        '/chat/completions',
        options: Options(headers: {'Authorization': 'Bearer $apiKey'}),
        data: {
          'model': _model,
          'temperature': 1,
          'messages': [
            {'role': 'system', 'content': _systemPrompt},
            {
              'role': 'user',
              'content':
                  'Translate the following novel text into English. '
                  'Keep paragraph breaks.\n\n$chunk',
            },
          ],
        },
      );

      final content =
          response.data['choices']?[0]?['message']?['content'] as String?;
      if (content == null || content.trim().isEmpty) {
        throw KimiApiException('Empty response from Moonshot API.');
      }
      return content.trim();
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      final serverMessage = (e.response?.data is Map)
        ? (e.response?.data['error']?['message'] as String?)
        : null;
      throw KimiApiException(
        serverMessage ?? e.message ?? 'Network error',
        statusCode: status,
      );
    }
  }

  /// Splits text into paragraph-respecting chunks under [maxChars].
  /// Exposed for unit tests.
  static List<String> chunkText(String text, {required int maxChars}) {
    final paragraphs =
        text.split(RegExp(r'\n+')).where((p) => p.trim().isNotEmpty).toList();
    if (paragraphs.isEmpty) return text.trim().isEmpty ? [] : [text];

    final chunks = <String>[];
    final buffer = StringBuffer();

    for (final paragraph in paragraphs) {
      final addition = buffer.isEmpty ? paragraph : '\n\n$paragraph';
      if (buffer.length + addition.length > maxChars && buffer.isNotEmpty) {
        chunks.add(buffer.toString());
        buffer.clear();
        buffer.write(paragraph);
      } else {
        if (buffer.isNotEmpty) buffer.write('\n\n');
        buffer.write(paragraph);
      }
    }
    if (buffer.isNotEmpty) chunks.add(buffer.toString());

    return chunks;
  }
}
