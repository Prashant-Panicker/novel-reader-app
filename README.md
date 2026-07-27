# Novel Reader

A personal Flutter app for reading web novels bilingually.

You browse Chinese (or other) novel sites in a **full in-app browser** — you
log in, scroll, and solve any CAPTCHA / Cloudflare check yourself, exactly
like a normal mobile browser. When a chapter is on screen, you extract the
visible text, translate it with **your own** Moonshot AI (Kimi) API key, and
read offline with Chinese + English side by side.

Nothing in this app automates or bypasses site protections. Translation
traffic goes **directly from your device to Moonshot**; the API key never
leaves your phone except in those requests.

## Features

- In-app browser with address bar, back/forward, and standard mobile UA
- Smarter chapter text extraction (common novel content selectors + cleaned body)
- Preview extracted text and edit book/chapter titles before spending API tokens
- Chunked translation with automatic retry on rate limits / transient errors
- Offline library grouped by book, with resume reading + progress %
- Bilingual / English-only / source-only reader modes
- Adjustable font size, re-translate any saved chapter
- Delete chapter or entire book
- Encrypted on-device API key storage
- Clear browser cookies & cache from Settings
- GitHub Actions workflow builds a release APK on every push to `main`

## Getting started (local)

```bash
# From the repo root (lib/ + pubspec.yaml already present)
flutter create --project-name novel_reader --org com.novelreader --platforms=android .
flutter pub get
flutter run
```

If you already have an `android/` folder from CI or a previous create, you can
skip the `flutter create` step.

### AndroidManifest

CI applies `android/app/src/main/AndroidManifest.xml.overlay` (INTERNET
permission, app label "Novel Reader", hardware acceleration). For local runs
after `flutter create`, either copy that overlay over
`android/app/src/main/AndroidManifest.xml` or ensure at least:

```xml
<uses-permission android:name="android.permission.INTERNET"/>
```

## Project structure

```
lib/
  main.dart
  models/
    chapter.dart          # Hive model (UUID primary key)
    chapter.g.dart        # hand-written TypeAdapter (CI-friendly)
  services/
    database_service.dart
    secure_storage_service.dart
    kimi_translation_service.dart
  screens/
    library_screen.dart
    reader_screen.dart
    browser_screen.dart
    settings_screen.dart
  theme/
    app_theme.dart
test/
  chunk_test.dart
.github/workflows/
  build.yml               # analyze → test → release APK artifact
```

## How translation works

1. Open **Browse & Translate**, type a URL (or search), and use the site
   normally — including solving any CAPTCHA yourself.
2. When the chapter body is visible, tap **Translate This Page**.
3. The app reads text already rendered in the WebView via
   `evaluateJavascript` (targeted selectors first, then cleaned `body`).
   It does **not** re-fetch the page headlessly.
4. You preview the extract and confirm book/chapter titles.
5. Text is sent from your device to your Moonshot account
   (`https://api.moonshot.cn/v1/chat/completions`, model `moonshot-v1-auto`).
6. The result is saved in Hive and opened in the bilingual reader.

## CI / APK

Push to `main` (or run the workflow manually). The job:

1. Scaffolds `android/` if missing (`flutter create … --platforms=android`)
2. Applies the manifest overlay (permissions + label)
3. `flutter analyze` (fails the job on issues)
4. `flutter test`
5. `flutter build apk --release`
6. Uploads `novel-reader-release` artifact (`app-release.apk`)

Download the artifact from the Actions run page. No signing keys or Play
Store credentials are required for this personal build.

## Privacy

- API key: encrypted via platform keystore / keychain only.
- Translations: stored only in the local Hive box on device.
- No analytics, no proxy server, no telemetry.
