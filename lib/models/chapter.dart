import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';

part 'chapter.g.dart';

/// A single saved chapter: source URL, raw text, AI translation, and reading
/// progress so the user never loses their place.
///
/// Primary key is a stable UUID ([id]). Book/chapter titles are free-form
/// display fields and may be edited without breaking the Hive entry.
@HiveType(typeId: 0)
class Chapter extends HiveObject {
  /// Stable unique id (UUID v4). Used as the Hive box key.
  @HiveField(0)
  String id;

  /// The page URL the chapter was extracted from.
  @HiveField(1)
  String url;

  /// The novel's title, e.g. "Coiling Dragon".
  @HiveField(2)
  String bookTitle;

  /// The chapter's title, e.g. "Chapter 1: The Boy Who Was Ridiculed".
  @HiveField(3)
  String chapterTitle;

  /// The raw source text as extracted from the webpage DOM.
  @HiveField(4)
  String rawText;

  /// The Kimi (Moonshot) AI translated English text.
  @HiveField(5)
  String translatedText;

  /// Normalized 0.0–1.0 scroll position within the Reader Canvas.
  @HiveField(6)
  double scrollPosition;

  /// When this chapter was first saved locally.
  @HiveField(7)
  DateTime savedAt;

  /// When the user last opened this chapter (powers "Resume Reading").
  @HiveField(8)
  DateTime lastReadAt;

  /// Optional source domain (e.g. "example.com") for grouping / filters.
  @HiveField(9)
  String sourceDomain;

  Chapter({
    String? id,
    required this.url,
    required this.bookTitle,
    required this.chapterTitle,
    required this.rawText,
    required this.translatedText,
    this.scrollPosition = 0.0,
    DateTime? savedAt,
    DateTime? lastReadAt,
    String? sourceDomain,
  })  : id = id ?? const Uuid().v4(),
        savedAt = savedAt ?? DateTime.now(),
        lastReadAt = lastReadAt ?? DateTime.now(),
        sourceDomain = sourceDomain ?? _domainFromUrl(url);

  static String _domainFromUrl(String url) {
    try {
      return Uri.parse(url).host;
    } catch (_) {
      return '';
    }
  }
}
