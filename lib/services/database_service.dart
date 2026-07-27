import 'package:hive_flutter/hive_flutter.dart';
import '../models/chapter.dart';

/// Local offline database of translated chapters, backed by Hive.
class DatabaseService {
  DatabaseService._();
  static final DatabaseService instance = DatabaseService._();

  static const String _boxName = 'chapters';
  Box<Chapter>? _box;

  /// Registers the Hive adapter and opens the local box. Call once at
  /// app startup before runApp().
  Future<void> init() async {
    await Hive.initFlutter();
    if (!Hive.isAdapterRegistered(0)) {
      Hive.registerAdapter(ChapterAdapter());
    }
    _box = await Hive.openBox<Chapter>(_boxName);
  }

  Box<Chapter> get _chapters {
    final box = _box;
    if (box == null) {
      throw StateError('DatabaseService.init() must be called before use.');
    }
    return box;
  }

  /// Saves (or overwrites) a translated chapter, keyed by its stable UUID.
  Future<void> saveChapter(Chapter chapter) async {
    await _chapters.put(chapter.id, chapter);
  }

  /// Updates only the reading progress without rewriting large text fields.
  Future<void> updateProgress(Chapter chapter, double scrollPosition) async {
    chapter.scrollPosition = scrollPosition;
    chapter.lastReadAt = DateTime.now();
    await chapter.save();
  }

  /// Replaces the translation (and optionally raw text) for an existing chapter.
  Future<void> updateTranslation(
    Chapter chapter, {
    required String translatedText,
    String? rawText,
  }) async {
    chapter.translatedText = translatedText;
    if (rawText != null) chapter.rawText = rawText;
    chapter.lastReadAt = DateTime.now();
    await chapter.save();
  }

  /// All saved chapters, newest-read first.
  List<Chapter> getAllChapters() {
    final list = _chapters.values.toList();
    list.sort((a, b) => b.lastReadAt.compareTo(a.lastReadAt));
    return list;
  }

  /// Chapters grouped by book title. Within each book, chapters are ordered
  /// by when they were first saved.
  Map<String, List<Chapter>> getChaptersByBook() {
    final grouped = <String, List<Chapter>>{};
    for (final chapter in _chapters.values) {
      grouped.putIfAbsent(chapter.bookTitle, () => []).add(chapter);
    }
    for (final list in grouped.values) {
      list.sort((a, b) => a.savedAt.compareTo(b.savedAt));
    }
    return grouped;
  }

  /// The single most-recently-read chapter across the whole library.
  Chapter? getMostRecentChapter() {
    final all = getAllChapters();
    return all.isEmpty ? null : all.first;
  }

  Future<void> deleteChapter(Chapter chapter) async {
    await chapter.delete();
  }

  Future<void> deleteBook(String bookTitle) async {
    final toDelete = _chapters.values
        .where((c) => c.bookTitle == bookTitle)
        .toList();
    for (final c in toDelete) {
      await c.delete();
    }
  }

  int get chapterCount => _chapters.length;
}
