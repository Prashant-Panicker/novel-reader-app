import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../services/secure_storage_service.dart';
import '../theme/app_theme.dart';

/// Settings: API key, WebView privacy controls, and about text.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final TextEditingController _apiKeyController = TextEditingController();
  bool _obscure = true;
  bool _isSaving = false;
  bool _hasExistingKey = false;
  bool _clearingWebData = false;

  @override
  void initState() {
    super.initState();
    _loadExistingKey();
  }

  Future<void> _loadExistingKey() async {
    final key = await SecureStorageService.instance.getApiKey();
    if (key != null && mounted) {
      setState(() {
        _apiKeyController.text = key;
        _hasExistingKey = true;
      });
    }
  }

  Future<void> _saveKey() async {
    final key = _apiKeyController.text.trim();
    if (key.isEmpty) {
      _showSnack('Please paste a valid API key first.');
      return;
    }

    setState(() => _isSaving = true);
    await SecureStorageService.instance.saveApiKey(key);
    if (!mounted) return;
    setState(() {
      _isSaving = false;
      _hasExistingKey = true;
    });
    _showSnack('API key saved securely on this device.');
  }

  Future<void> _clearKey() async {
    await SecureStorageService.instance.clearApiKey();
    if (!mounted) return;
    setState(() {
      _apiKeyController.clear();
      _hasExistingKey = false;
    });
    _showSnack('API key removed.');
  }

  Future<void> _clearWebData() async {
    setState(() => _clearingWebData = true);
    try {
      await InAppWebViewController.clearAllCache();
      final cookieManager = CookieManager.instance();
      await cookieManager.deleteAllCookies();
      if (!mounted) return;
      _showSnack('Browser cache and cookies cleared.');
    } catch (e) {
      if (!mounted) return;
      _showSnack('Could not clear web data: $e');
    } finally {
      if (mounted) setState(() => _clearingWebData = false);
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Moonshot AI (Kimi) API Key',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          Text(
            'Your key is stored encrypted on this device only, and is used '
            'solely to call your own Moonshot account when you translate a page. '
            'Nothing is proxied through any third-party server.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 18),
          TextField(
            controller: _apiKeyController,
            obscureText: _obscure,
            style: const TextStyle(color: AppTheme.textPrimary),
            decoration: InputDecoration(
              hintText: 'sk-••••••••••••••••••••••••••',
              suffixIcon: IconButton(
                icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isSaving ? null : _saveKey,
              child: _isSaving
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.black,
                      ),
                    )
                  : const Text('Save'),
            ),
          ),
          if (_hasExistingKey) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: _clearKey,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.danger,
                  side: const BorderSide(color: AppTheme.danger),
                ),
                child: const Text('Clear Saved Key'),
              ),
            ),
          ],
          const SizedBox(height: 32),
          const Divider(),
          const SizedBox(height: 12),
          Text('Browser privacy', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(
            'Clear cookies and cache from the in-app browser (logs you out '
            'of novel sites and frees storage).',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _clearingWebData ? null : _clearWebData,
              icon: _clearingWebData
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.cleaning_services_outlined),
              label: const Text('Clear browser cache & cookies'),
            ),
          ),
          const SizedBox(height: 32),
          const Divider(),
          const SizedBox(height: 12),
          Text('About', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(
            'Novel Reader is a personal reading tool. You browse and manually '
            'sign in / solve any CAPTCHA on the site yourself in the built-in '
            'browser — nothing here automates or bypasses site protections. '
            'Once a page is loaded, you choose to translate its visible text '
            'using your own Moonshot AI account. Translations are stored only '
            'on this device.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          Text(
            'Version 1.1.0',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppTheme.textSecondary,
                ),
          ),
        ],
      ),
    );
  }
}
