# PricePilot Bill

Android-first Flutter billing app for invoices, inventory, customers, cash,
bank activity, and reports.

## Features

- Material 3 dashboard and mobile navigation
- Sales, invoices, inventory, customers, suppliers, expenses, payments, and reports
- Local persistence with session/PIN protection
- Android package: `com.billket.app`

## Tech Stack

- Flutter
- Dart 3.x
- Material 3
- Provider (configured for state management)
- GoRouter (configured for navigation)
- SQLite via `sqflite` (configured for local persistence)
- `shared_preferences` for preferences
- `fl_chart` and custom painting for charts
- `google_fonts` for typography
- `flutter_svg`, `cached_network_image`, and `flutter_animate` for media and UI support

## Requirements

- Flutter SDK with Dart 3.x support
- Android SDK and an Android device or emulator
- Flutter SDK with Dart 3.x support

Check the local setup with:

```bash
flutter doctor
flutter devices
```

## Run On Android

From the `app` directory:

```bash
flutter pub get
```

Run on a connected Android device or emulator:

```bash
flutter devices
flutter run -d <android-device-id>
```

Chrome and Windows remain available for testing, but Android is the release
target.

## Play Store Release

Create an upload keystore and keep it outside source control. Then create
`android/key.properties` using this template:

```properties
storePassword=...
keyPassword=...
keyAlias=upload
storeFile=C:/secure/pricepilot-upload.jks
```

Build the Play Store bundle:

```bash
flutter build appbundle --release
```

Upload `build/app/outputs/bundle/release/app-release.aab` to Google Play
Console. Increase the version in `pubspec.yaml` for every release and complete
the Play Console privacy, data safety, content rating, and store listing
requirements before publishing.

## Quality Checks

```bash
flutter analyze
flutter test
```

## Project Structure

```text
lib/
  main.dart             Application entry point and AppGate
  core/                 Shared models, session, dates, and billing logic
  data/                 Local database, repositories, and seed data
  features/             Auth, dashboard, sales, inventory, and other screens
  sync/                 Synchronization engine
  theme/                Material 3 application theme
Pages/
  *.txt                 Page design/reference exports
Components/             Component resources
Pubspec/                Supporting project resources
pubspec.yaml            Dependencies and Flutter configuration
```

## Production Status

The Android package identity and store label are configured. Release signing
uses `android/key.properties` when present; debug signing is not used for a
configured release build. Complete keystore setup, privacy/data-safety
declarations, backend services, and remote synchronization before launch.

See `SECURITY.md` for vulnerability reporting guidance.




