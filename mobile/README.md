# GroopX Mobile

Flutter client for private direct messaging, groups, communities, statuses,
reminders, notifications, and LiveKit audio/video calls.

## Requirements

- Flutter stable with Dart 3.4+
- Android SDK and Java 17
- A running GroopX API

## Configure and run

```powershell
flutter pub get
flutter run --dart-define=API_BASE_URL=https://groopx.onrender.com/api/v1 --dart-define=WS_BASE_URL=wss://groopx.onrender.com
```

For Firebase push notifications, download `google-services.json` for application
ID `com.futureittouch.groopx` and place it in `android/app/`. Do not commit it.

## Release signing

Create a release keystore, copy `android/key.properties.example` to
`android/key.properties`, then replace all placeholder values. Both files are
excluded from Git.

## Build release APK

```powershell
flutter clean
flutter pub get
flutter build apk --release --dart-define=API_BASE_URL=https://groopx.onrender.com/api/v1 --dart-define=WS_BASE_URL=wss://groopx.onrender.com
```

Output: `build/app/outputs/flutter-apk/app-release.apk`.
