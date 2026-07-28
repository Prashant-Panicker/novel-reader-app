import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../models/chapter.dart';
import '../services/database_service.dart';
import '../services/kimi_translation_service.dart';
import '../services/secure_storage_service.dart';
import '../theme/app_theme.dart';
import 'reader_screen.dart';
import 'settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/chapter.dart';
import '../services/database_service.dart';
import '../services/kimi_translation_service.dart';
import '../services/secure_storage_service.dart';
import '../theme/app_theme.dart';
import 'reader_screen.dart';
import 'settings_screen.dart';

/// In-app browser: user navigates and solves CAPTCHAs themselves, then
/// extracts on-screen text for translation with their own Kimi key.
class BrowserScreen extends StatefulWidget {
  const BrowserScreen({super.key});

  @override
  State<BrowserScreen> createState() => _BrowserScreenState();
}

class _BrowserScreenState extends State<BrowserScreen> {
  InAppWebViewController? _webViewController;
  final TextEditingController _urlBarController = TextEditingController();
  bool _isLoading = false;
  bool _isTranslating = false;
  double _loadProgress = 0;
  bool _canGoBack = false;
  bool _canGoForward = false;

  /// Progressive translation state.
  int _translateCurrent = 0;
  int _translateTotal = 0;
  bool _cancelTranslation = false;
  String _partialTranslation = '';

  static const String _prefsLastUrlKey = 'browser_last_url';
  static const String _fallbackStartUrl = 'about:blank';

  /// JS that prefers common novel content containers, then falls back to a
  /// cleaned body. Runs only on the page the user already loaded.
  static const String _extractScript = r'''
(function() {
  function cleanText(root) {
    var clone = root.cloneNode(true);
    var junk = clone.querySelectorAll(
      'script, style, nav, header, footer, noscript, iframe, aside, form, ' +
      'button, input, select, textarea, .ad, .ads, .advertisement, ' +
      '[class*="comment"], [id*="comment"], [class*="sidebar"], [id*="sidebar"]'
    );
    for (var i = 0; i < junk.length; i++) {
      try { junk[i].remove(); } catch (e) {}
    }
    var text = (clone.innerText || clone.textContent || '').replace(/\r/g, '');
    // Collapse 3+ blank lines to 2.
    text = text.replace(/\n{3,}/g, '\n\n').trim();
    return text;
  }

  var selectors = [
    '#content', '#chaptercontent', '#chapter-content', '#chapter_content',
    '.content', '.chapter-content', '.chapter_content', '.novel-content',
    '.read-content', '.txt', '.text', 'article', '#BookText', '#booktext',
    '.book-content', '#htmlContent', '.chapter', '#chapters'
  ];

  for (var s = 0; s < selectors.length; s++) {
    var el = document.querySelector(selectors[s]);
    if (el) {
      var t = cleanText(el);
      if (t && t.length > 200) return t;
    }
  }

  return cleanText(document.body || document.documentElement);
})();
''';

  @override
  void initState() {
    super.initState();
    _restoreLastUrlIntoBar();
  }

  Future<void> _restoreLastUrlIntoBar() async {
    final prefs = await SharedPreferences.getInstance();
    final last = prefs.getString(_prefsLastUrlKey);
    if (!mounted) return;
    if (last != null && last.isNotEmpty && last != 'about:blank') {
      _urlBarController.text = last;
    }
  }

  Future<String> _resolveStartUrl() async {
    final prefs = await SharedPreferences.getInstance();
    final last = prefs.getString(_prefsLastUrlKey);
    if (last != null && last.isNotEmpty && last != 'about:blank') {
      return last;
    }
    return _fallbackStartUrl;
  }

  Future<void> _saveLastUrl(String? url) async {
    if (url == null || url.isEmpty || url == 'about:blank') return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsLastUrlKey, url);
  }

  @override
  void dispose() {
    _urlBarController.dispose();
    super.dispose();
  }

  Future<void> _updateNavState() async {
    final c = _webViewController;
    if (c == null) return;
    final back = await c.canGoBack();
    final forward = await c.canGoForward();
    if (!mounted) return;
    setState(() {
      _canGoBack = back;
      _canGoForward = forward;
    });
  }

  void _loadUrlFromBar() {
    var input = _urlBarController.text.trim();
    if (input.isEmpty) return;
    if (!input.startsWith('http://') && !input.startsWith('https://')) {
      if (input.contains('.') && !input.contains(' ')) {
        input = 'https://$input';
      } else {
        input =
            'https://www.google.com/search?q=${Uri.encodeComponent(input)}';
      }
    }
    _webViewController?.loadUrl(urlRequest: URLRequest(url: WebUri(input)));
  }

  Future<String> _extractPageText() async {
    final result =
        await _webViewController?.evaluateJavascript(source: _extractScript);
    if (result == null) return '';
    // evaluateJavascript may return a JSON-encoded string.
    var text = result.toString().trim();
    if (text.startsWith('"') && text.endsWith('"')) {
      try {
        text = text
            .substring(1, text.length - 1)
            .replaceAll(r'\n', '\n')
            .replaceAll(r'\"', '"')
            .replaceAll(r'\\', r'\\');
      } catch (_) {}
    }
    return text.trim();
  }

  Future<String> _extractPageTitle() async {
    final title = await _webViewController?.getTitle();
    return (title == null || title.trim().isEmpty)
        ? 'Untitled Chapter'
        : title.trim();
  }

  Future<String?> _previewAndConfirm(String rawText, String pageTitle) async {
    final preview = rawText.length > 1200
        ? '${rawText.substring(0, 1200)}\n\n… (${rawText.length} chars total)'
        : rawText;

    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        final bookCtrl = TextEditingController();
        final chapterCtrl = TextEditingController();

        // Best-effort split of "Book – Chapter" style titles.
        final parts = pageTitle.split(RegExp(r'[-–_|]'));
        bookCtrl.text = parts.isNotEmpty ? parts.first.trim() : pageTitle;
        chapterCtrl.text = parts.length > 1
            ? parts.sublist(1).join('-').trim()
            : pageTitle;

        return AlertDialog(
          title: const Text('Translate this page?'),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: bookCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Book title',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: chapterCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Chapter title',
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Extracted text preview',
                    style: Theme.of(ctx).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 6),
                  Container(
                    constraints: const BoxConstraints(maxHeight: 220),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceAlt,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: SingleChildScrollView(
                      child: Text(
                        preview,
                        style: const TextStyle(
                          fontSize: 12,
                          height: 1.4,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final book = bookCtrl.text.trim().isEmpty
                    ? 'Unsorted'
                    : bookCtrl.text.trim();
                final chapter = chapterCtrl.text.trim().isEmpty
                    ? pageTitle
                    : chapterCtrl.text.trim();
                Navigator.pop(ctx, '$book|||$chapter');
              },
              child: const Text('Translate'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _translateCurrentPage() async {
    final hasKey = await SecureStorageService.instance.hasApiKey();
    if (!hasKey) {
      if (!mounted) return;
      _promptForApiKey();
      return;
    }

    setState(() {
      _isTranslating = true;
      _cancelTranslation = false;
      _translateCurrent = 0;
      _translateTotal = 0;
      _partialTranslation = '';
    });

    try {
      final rawText = await _extractPageText();
      if (rawText.isEmpty || rawText.length < 40) {
        _showSnack(
          'No readable chapter text found yet. Wait for the page to finish '
          'loading, or scroll so the chapter body is visible.',
        );
        return;
      }

      final pageTitle = await _extractPageTitle();
      final currentUrl = (await _webViewController?.getUrl())?.toString() ?? '';

      if (!mounted) return;
      // Temporarily clear the overlay so the dialog is usable.
      setState(() => _isTranslating = false);

      final titles = await _previewAndConfirm(rawText, pageTitle);
      if (titles == null || !mounted) return;

      setState(() {
        _isTranslating = true;
        _cancelTranslation = false;
        _translateCurrent = 0;
        _translateTotal = 0;
        _partialTranslation = '';
      });

      final split = titles.split('|||');
      final bookTitle = split.isNotEmpty ? split[0] : 'Unsorted';
      final chapterTitle = split.length > 1 ? split[1] : pageTitle;

      final translated = await KimiTranslationService.instance.translateText(
        rawText,
        onProgress: (current, total, partial) {
          if (!mounted) return;
          setState(() {
            _translateCurrent = current;
            _translateTotal = total;
            _partialTranslation = partial;
          });
        },
        shouldCancel: () => _cancelTranslation,
      );

      final chapter = Chapter(
        url: currentUrl,
        bookTitle: bookTitle,
        chapterTitle: chapterTitle,
        rawText: rawText,
        translatedText: translated,
      );

      await DatabaseService.instance.saveChapter(chapter);

      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => ReaderScreen(chapter: chapter)),
      );
    } on MissingApiKeyException {
      _promptForApiKey();
    } on TranslationCancelledException {
      if (!mounted) return;
      if (_partialTranslation.isNotEmpty) {
        _showSnack(
          'Translation cancelled after $_translateCurrent/$_translateTotal '
          'chunks. Partial result was not saved — translate again to finish.',
        );
      } else {
        _showSnack('Translation cancelled.');
      }
    } catch (e) {
      if (!mounted) return;
      final retry = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Translation failed'),
          content: Text('$e'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Dismiss'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Retry'),
            ),
          ],
        ),
      );
      if (retry == true && mounted) {
        await _translateCurrentPage();
        return;
      }
    } finally {
      if (mounted) {
        setState(() {
          _isTranslating = false;
          _cancelTranslation = false;
        });
      }
    }
  }

  void _promptForApiKey() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Kimi API Key Needed'),
        content: const Text(
          'Add your personal Moonshot (Kimi) API key in Settings before '
          'translating a page.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              );
            },
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  void _showLoadError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 6),
        action: SnackBarAction(
          label: 'Retry',
          onPressed: () => _webViewController?.reload(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: _AddressBar(
          controller: _urlBarController,
          onSubmitted: (_) => _loadUrlFromBar(),
          onGo: _loadUrlFromBar,
        ),
        toolbarHeight: 64,
        actions: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_new, size: 18),
            tooltip: 'Back',
            onPressed: _canGoBack
                ? () async {
                    await _webViewController?.goBack();
                    await _updateNavState();
                  }
                : null,
          ),
          IconButton(
            icon: const Icon(Icons.arrow_forward_ios, size: 18),
            tooltip: 'Forward',
            onPressed: _canGoForward
                ? () async {
                    await _webViewController?.goForward();
                    await _updateNavState();
                  }
                : null,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Reload',
            onPressed: () => _webViewController?.reload(),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_isLoading)
            LinearProgressIndicator(
              value: _loadProgress == 0 ? null : _loadProgress,
              minHeight: 2,
              backgroundColor: AppTheme.surface,
              color: AppTheme.accent,
            ),
          Expanded(
            child: Stack(
              children: [
                FutureBuilder<String>(
                  future: _resolveStartUrl(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const Center(
                        child: CircularProgressIndicator(
                          color: AppTheme.accent,
                        ),
                      );
                    }
                    final startUrl = snapshot.data!;
                    return InAppWebView(
                      initialUrlRequest: URLRequest(url: WebUri(startUrl)),
                      initialSettings: InAppWebViewSettings(
                        javaScriptEnabled: true,
                        domStorageEnabled: true,
                        databaseEnabled: true,
                        cacheEnabled: true,
                        cacheMode: CacheMode.LOAD_DEFAULT,
                        hardwareAcceleration: true,
                        thirdPartyCookiesEnabled: true,
                        supportZoom: true,
                        mediaPlaybackRequiresUserGesture: true,
                        allowsInlineMediaPlayback: true,
                        javaScriptCanOpenWindowsAutomatically: false,
                        mixedContentMode:
                            MixedContentMode.MIXED_CONTENT_COMPATIBILITY_MODE,
                        // Text-first: big win on ad-heavy novel sites.
                        blockNetworkImage: true,
                        userAgent:
                            'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 '
                            '(KHTML, like Gecko) Chrome/126.0.0.0 Mobile Safari/537.36',
                        // Hardening: block file-URL access & geolocation.
                        allowFileAccessFromFileURLs: false,
                        allowUniversalAccessFromFileURLs: false,
                        geolocationEnabled: false,
                      ),
                      onWebViewCreated: (controller) {
                        _webViewController = controller;
                      },
                      onLoadStart: (controller, url) {
                        setState(() {
                          _isLoading = true;
                          if (url != null) {/* intentionally empty */}
                        });
                      },
                      onProgressChanged: (controller, progress) {
                        setState(() => _loadProgress = progress / 100);
                      },
                      onLoadStop: (controller, url) async {
                        setState(() {
                          _isLoading = false;
                          if (url != null) {/* intentionally empty */}
                        });
                        await _saveLastUrl(url?.toString());
                        await _updateNavState();
                      },
                      onUpdateVisitedHistory: (controller, url, isReload) {
                        if (url != null) {
                          _urlBarController.text = url.toString();
                          _saveLastUrl(url.toString());
                        }
                        _updateNavState();
                      },
                      onReceivedError: (controller, request, error) {
                        // Only surface main-frame failures.
                        if (request.isForMainFrame == true) {
                          _showLoadError(
                            'Page failed to load. Check the URL or your network.',
                          );
                        }
                      },
                      onReceivedHttpError: (controller, request, response) {
                        final code = response.statusCode ?? 0;
                        if (request.isForMainFrame == true && code >= 400) {
                          _showLoadError(
                            'Page returned HTTP $code.',
                          );
                        }
                      },
                    );
                  },
                ),
                if (_isTranslating)
                  Container(
                    color: Colors.black87,
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const CircularProgressIndicator(
                            color: AppTheme.accent,
                          ),
                          const SizedBox(height: 14),
                          Text(
                            _translateTotal == 0
                                ? 'Preparing translation…'
                                : 'Translating chunk $_translateCurrent/$_translateTotal',
                            style: const TextStyle(color: Colors.white),
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: 300,
                            height: 120,
                            child: SingleChildScrollView(
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.black54,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  _partialTranslation.isEmpty
                                      ? 'Waiting for first chunk…'
                                      : _partialTranslation,
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 13,
                                    height: 1.4,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          ElevatedButton(
                            onPressed: () {
                              setState(() => _cancelTranslation = true);
                            },
                            child: const Text('Cancel Translation'),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isTranslating ? null : _translateCurrentPage,
                  icon: const Icon(Icons.translate),
                  label: const Text('Translate This Page'),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AddressBar extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onGo;

  const _AddressBar({
    required this.controller,
    required this.onSubmitted,
    required this.onGo,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 42,
      decoration: BoxDecoration(
        color: AppTheme.surfaceAlt,
        borderRadius: BorderRadius.circular(10),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          const Icon(
            Icons.lock_outline,
            size: 16,
            color: AppTheme.textSecondary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: controller,
              onSubmitted: onSubmitted,
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.go,
              style: const TextStyle(
                fontSize: 14,
                color: AppTheme.textPrimary,
              ),
              decoration: const InputDecoration(
                isDense: true,
                border: InputBorder.none,
                filled: false,
                contentPadding: EdgeInsets.zero,
                hintText: 'Enter novel site URL…',
              ),
            ),
          ),
          IconButton(
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            icon: const Icon(
              Icons.arrow_forward,
              size: 18,
              color: AppTheme.accent,
            ),
            onPressed: onGo,
          ),
        ],
      ),
    );
  }
}
