import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/chapter.dart';
import '../services/database_service.dart';
import '../services/kimi_translation_service.dart';
import '../services/secure_storage_service.dart';
import '../theme/app_theme.dart';
import 'settings_screen.dart';

enum _ViewMode { bilingual, englishOnly, sourceOnly }

/// Bilingual (or single-language) reading canvas with saved scroll position,
/// adjustable type size, and re-translate support.
class ReaderScreen extends StatefulWidget {
  final Chapter chapter;
  const ReaderScreen({super.key, required this.chapter});

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  late final ScrollController _scrollController;
  Timer? _saveDebounce;
  late List<_ParagraphPair> _pairs;
  _ViewMode _viewMode = _ViewMode.bilingual;
  double _fontSize = 18;
  bool _isRetranslating = false;
  late Chapter _chapter;

  @override
  void initState() {
    super.initState();
    _chapter = widget.chapter;
    _pairs = _buildPairs(_chapter.rawText, _chapter.translatedText);
    _scrollController = ScrollController();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      final target =
          _chapter.scrollPosition * _scrollController.position.maxScrollExtent;
      if (target.isFinite && target > 0) {
        _scrollController.jumpTo(target);
      }
    });

    _scrollController.addListener(_onScroll);
    // Keep the screen awake while reading.
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  List<_ParagraphPair> _buildPairs(String raw, String translated) {
    final rawParas =
        raw.split(RegExp(r'\n+')).where((p) => p.trim().isNotEmpty).toList();
    final trParas = translated
        .split(RegExp(r'\n+'))
        .where((p) => p.trim().isNotEmpty)
        .toList();

    // Prefer pairing by min length when counts diverge so we don't invent
    // empty counterparts at the end of a long side.
    final count =
        rawParas.length > trParas.length ? rawParas.length : trParas.length;
    return List.generate(count, (i) {
      return _ParagraphPair(
        chinese: i < rawParas.length ? rawParas[i] : '',
        english: i < trParas.length ? trParas[i] : '',
      );
    });
  }

  void _onScroll() {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 400), () {
      if (!_scrollController.hasClients) return;
      final maxExtent = _scrollController.position.maxScrollExtent;
      final progress = maxExtent <= 0
          ? 0.0
          : (_scrollController.offset / maxExtent).clamp(0.0, 1.0);
      DatabaseService.instance.updateProgress(_chapter, progress);
    });
  }

  Future<void> _retranslate() async {
    final hasKey = await SecureStorageService.instance.hasApiKey();
    if (!hasKey) {
      if (!mounted) return;
      final go = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('API key needed'),
          content: const Text(
            'Add your Moonshot (Kimi) API key in Settings to re-translate.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Open Settings'),
            ),
          ],
        ),
      );
      if (go == true && mounted) {
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const SettingsScreen()),
        );
      }
      return;
    }

    setState(() => _isRetranslating = true);
    try {
      final translated =
          await KimiTranslationService.instance.translateText(_chapter.rawText);
      await DatabaseService.instance.updateTranslation(
        _chapter,
        translatedText: translated,
      );
      if (!mounted) return;
      setState(() {
        _pairs = _buildPairs(_chapter.rawText, translated);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Chapter re-translated.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Re-translate failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _isRetranslating = false);
    }
  }

  @override
  void dispose() {
    _saveDebounce?.cancel();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final progressPct = (_chapter.scrollPosition * 100).round();

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _chapter.chapterTitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          PopupMenuButton<_ViewMode>(
            tooltip: 'View mode',
            initialValue: _viewMode,
            onSelected: (m) => setState(() => _viewMode = m),
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: _ViewMode.bilingual,
                child: Text('Bilingual'),
              ),
              PopupMenuItem(
                value: _ViewMode.englishOnly,
                child: Text('English only'),
              ),
              PopupMenuItem(
                value: _ViewMode.sourceOnly,
                child: Text('Source only'),
              ),
            ],
            icon: const Icon(Icons.view_agenda_outlined),
          ),
          PopupMenuButton<String>(
            tooltip: 'More',
            onSelected: (value) {
              if (value == 'retranslate') _retranslate();
              if (value == 'font_up') {
                setState(() => _fontSize = (_fontSize + 1).clamp(14, 28));
              }
              if (value == 'font_down') {
                setState(() => _fontSize = (_fontSize - 1).clamp(14, 28));
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'font_up',
                child: Text('Larger text'),
              ),
              const PopupMenuItem(
                value: 'font_down',
                child: Text('Smaller text'),
              ),
              const PopupMenuDivider(),
              PopupMenuItem(
                value: 'retranslate',
                enabled: !_isRetranslating,
                child: Text(
                  _isRetranslating ? 'Re-translating…' : 'Re-translate chapter',
                ),
              ),
            ],
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(3),
          child: LinearProgressIndicator(
            value: _chapter.scrollPosition.clamp(0.0, 1.0),
            minHeight: 3,
            backgroundColor: AppTheme.surface,
            color: AppTheme.accent,
          ),
        ),
      ),
      body: Stack(
        children: [
          ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 48),
            itemCount: _pairs.length + 1,
            itemBuilder: (context, index) {
              if (index == 0) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _chapter.bookTitle,
                        style: const TextStyle(
                          color: AppTheme.accent,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$progressPct% · ${_pairs.length} paragraphs',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                );
              }
              final pair = _pairs[index - 1];
              return _BilingualBlock(
                pair: pair,
                viewMode: _viewMode,
                fontSize: _fontSize,
              );
            },
          ),
          if (_isRetranslating)
            Container(
              color: Colors.black54,
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: AppTheme.accent),
                    SizedBox(height: 16),
                    Text(
                      'Re-translating with Kimi…',
                      style: TextStyle(color: Colors.white),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ParagraphPair {
  final String chinese;
  final String english;
  _ParagraphPair({required this.chinese, required this.english});
}

class _BilingualBlock extends StatelessWidget {
  final _ParagraphPair pair;
  final _ViewMode viewMode;
  final double fontSize;

  const _BilingualBlock({
    required this.pair,
    required this.viewMode,
    required this.fontSize,
  });

  @override
  Widget build(BuildContext context) {
    final showSource = viewMode == _ViewMode.bilingual ||
        viewMode == _ViewMode.sourceOnly;
    final showEnglish = viewMode == _ViewMode.bilingual ||
        viewMode == _ViewMode.englishOnly;

    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showSource && pair.chinese.isNotEmpty)
            Text(
              pair.chinese,
              style: TextStyle(
                fontSize: fontSize,
                height: 1.8,
                color: viewMode == _ViewMode.sourceOnly
                    ? AppTheme.textPrimary
                    : AppTheme.textSecondary,
                fontFamilyFallback: const ['Noto Sans SC', 'PingFang SC'],
              ),
            ),
          if (showSource &&
              showEnglish &&
              pair.chinese.isNotEmpty &&
              pair.english.isNotEmpty)
            const SizedBox(height: 8),
          if (showEnglish && pair.english.isNotEmpty)
            Text(
              pair.english,
              style: TextStyle(
                fontSize: fontSize,
                height: 1.8,
                color: AppTheme.textPrimary,
              ),
            ),
        ],
      ),
    );
  }
}
