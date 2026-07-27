import 'package:flutter/material.dart';
import '../models/chapter.dart';
import '../services/database_service.dart';
import '../theme/app_theme.dart';
import 'browser_screen.dart';
import 'reader_screen.dart';
import 'settings_screen.dart';

/// My Personal Library — saved chapters grouped by book, with resume shortcut.
class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  late Map<String, List<Chapter>> _library;
  Chapter? _mostRecent;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    setState(() {
      _library = DatabaseService.instance.getChaptersByBook();
      _mostRecent = DatabaseService.instance.getMostRecentChapter();
    });
  }

  Future<void> _openReader(Chapter chapter) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ReaderScreen(chapter: chapter)),
    );
    if (mounted) _reload();
  }

  Future<void> _openBrowser() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const BrowserScreen()),
    );
    if (mounted) _reload();
  }

  void _openSettings() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SettingsScreen()),
    );
  }

  Future<void> _confirmDeleteChapter(Chapter chapter) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete chapter?'),
        content: Text(
          '"${chapter.chapterTitle}" will be removed from this device. '
          'This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.danger,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await DatabaseService.instance.deleteChapter(chapter);
      if (mounted) _reload();
    }
  }

  Future<void> _confirmDeleteBook(String bookTitle, int count) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete entire book?'),
        content: Text(
          'Remove all $count chapter(s) of "$bookTitle" from this device?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.danger,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete all'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await DatabaseService.instance.deleteBook(bookTitle);
      if (mounted) _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    final bookTitles = _library.keys.toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Novel Reader'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
            onPressed: _openSettings,
          ),
          const SizedBox(width: 8),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openBrowser,
        icon: const Icon(Icons.add),
        label: const Text('Browse & Translate'),
      ),
      body: bookTitles.isEmpty
          ? _EmptyLibrary(onBrowse: _openBrowser)
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
              children: [
                if (_mostRecent != null) ...[
                  _ResumeCard(
                    chapter: _mostRecent!,
                    onTap: () => _openReader(_mostRecent!),
                  ),
                  const SizedBox(height: 20),
                ],
                for (final book in bookTitles)
                  _BookSection(
                    bookTitle: book,
                    chapters: _library[book]!,
                    onOpenChapter: _openReader,
                    onDeleteChapter: _confirmDeleteChapter,
                    onDeleteBook: () =>
                        _confirmDeleteBook(book, _library[book]!.length),
                  ),
              ],
            ),
    );
  }
}

class _EmptyLibrary extends StatelessWidget {
  final VoidCallback onBrowse;
  const _EmptyLibrary({required this.onBrowse});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.auto_stories_outlined,
              size: 64,
              color: AppTheme.textSecondary,
            ),
            const SizedBox(height: 16),
            Text(
              'Your library is empty',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'Tap "Browse & Translate" to open a novel site, load a '
              'chapter, and translate it with your own Kimi API key.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: onBrowse,
              icon: const Icon(Icons.public),
              label: const Text('Open Browser'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ResumeCard extends StatelessWidget {
  final Chapter chapter;
  final VoidCallback onTap;
  const _ResumeCard({required this.chapter, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.surfaceAlt,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              const CircleAvatar(
                radius: 24,
                backgroundColor: AppTheme.accent,
                child: Icon(Icons.play_arrow, color: Colors.black),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'RESUME READING',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppTheme.accent,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.1,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      chapter.bookTitle,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(
                      chapter.chapterTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AppTheme.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}

class _BookSection extends StatelessWidget {
  final String bookTitle;
  final List<Chapter> chapters;
  final void Function(Chapter) onOpenChapter;
  final void Function(Chapter) onDeleteChapter;
  final VoidCallback onDeleteBook;

  const _BookSection({
    required this.bookTitle,
    required this.chapters,
    required this.onOpenChapter,
    required this.onDeleteChapter,
    required this.onDeleteBook,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  bookTitle,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 20),
                color: AppTheme.textSecondary,
                tooltip: 'Delete entire book',
                onPressed: onDeleteBook,
              ),
            ],
          ),
          const SizedBox(height: 4),
          ...chapters.map(
            (chapter) => Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                title: Text(chapter.chapterTitle),
                subtitle: Text(
                  '${(chapter.scrollPosition * 100).round()}% read'
                  '${chapter.sourceDomain.isNotEmpty ? ' · ${chapter.sourceDomain}' : ''}',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                trailing: PopupMenuButton<String>(
                  icon: const Icon(
                    Icons.more_vert,
                    color: AppTheme.textSecondary,
                  ),
                  onSelected: (value) {
                    if (value == 'open') onOpenChapter(chapter);
                    if (value == 'delete') onDeleteChapter(chapter);
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'open', child: Text('Open')),
                    PopupMenuItem(
                      value: 'delete',
                      child: Text(
                        'Delete',
                        style: TextStyle(color: AppTheme.danger),
                      ),
                    ),
                  ],
                ),
                onTap: () => onOpenChapter(chapter),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
