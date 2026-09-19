# PricePilot Bill — Universal Multi-Platform Build Guide

This comprehensive guide details step-by-step instructions for building and running **PricePilot Bill** across all supported devices and platforms (Android, Windows Desktop, Web, iOS/macOS, and Backend).

---

## 1. System Requirements & Prerequisites

Ensure the following tools are installed on your workstation:

| Component | Minimum Version | Required For |
| :--- | :--- | :--- |
| **Git** | 2.x+ | Cloning the repository |
| **Flutter SDK** | 3.22.x+ (Dart 3.4+) | All client applications |
| **Java JDK** | JDK 17 or 21 (Temurin / OpenJDK) | Android APK & AAB builds |
| **Android SDK** | API 34+ (Build Tools 34.0.0+) | Android builds |
| **Visual Studio** | 2022 with "Desktop development with C++" | Windows Desktop builds |
| **Google Chrome / Edge** | Latest | Web builds |
| **Node.js & npm** | Node 18+ / npm 9+ | Backend server & admin portal |
| **Xcode & CocoaPods** | Xcode 15+ (macOS only) | iOS & macOS builds |

### Verifying Tooling
Run the Flutter diagnostics tool:
```bash
flutter doctor -v
```
Ensure that the checks for your target platforms (Android, Windows, Chrome) show green checkmarks.

---

## 2. Quick Start: Clone & Dependencies

1. **Clone the repository**:
   ```bash
   git clone https://github.com/DReekis/Bill-App.git
   cd Bill-App
   ```

2. **Install Flutter Client Dependencies**:
   ```bash
   cd app
   flutter pub get
   ```

3. **Install Backend Server Dependencies**:
   ```bash
   cd ../backend
   npm install
   ```

---

## 3. Building for Android (Primary Mobile Target)

PricePilot Bill is optimized for Android tablets and smartphones with offline-first local SQLite persistence.

### A. Run in Development (Live Device or Emulator)
1. Connect your Android device via USB and enable **USB Debugging** (or start an Android emulator).
2. Check connected devices:
   ```bash
   flutter devices
   ```
3. Run the app:
   ```bash
   cd app
   flutter run -d <device_id>
   ```

### B. Build Release APK
Generates a standalone, installable `.apk` file:
```bash
cd app
flutter build apk --release
```
- **Output Artifact**:
  ```
  app/build/app/outputs/flutter-apk/app-release.apk
  ```

### C. Install Release APK via ADB
To install directly to a connected phone or tablet:
```bash
adb install -r build/app/outputs/flutter-apk/app-release.apk
```
*(If multiple devices are connected, specify device: `adb -s <device_id> install -r build/app/outputs/flutter-apk/app-release.apk`)*

### D. Build Google Play Store Bundle (.aab)
To generate an optimized Android App Bundle for Google Play distribution:
```bash
cd app
flutter build appbundle --release
```
- **Output Artifact**:
  ```
  app/build/app/outputs/bundle/release/app-release.aab
  ```

### E. Release Signing Configuration (Optional)
By default, Flutter creates a release APK signed with debug keys if no custom keystore is configured. To sign for production:
1. Generate an upload keystore:
   ```bash
   keytool -genkey -v -keystore pricepilot-release.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
   ```
2. Create `app/android/key.properties` (this file is excluded from Git):
   ```properties
   storePassword=your_keystore_password
   keyPassword=your_key_password
   keyAlias=upload
   storeFile=C:/path/to/pricepilot-release.jks
   ```

---

## 4. Building for Windows Desktop

PricePilot Bill natively compiles to a high-performance 64-bit Windows desktop executable for billing counters and POS setups.

### A. Prerequisites
- Install **Visual Studio 2022** (Community, Professional, or Enterprise).
- Under workloads, select and install **Desktop development with C++**.

### B. Enable Windows in Flutter
```bash
flutter config --enable-windows-desktop
```

### C. Run in Development
```bash
cd app
flutter run -d windows
```

### D. Build Release Windows Executable
```bash
cd app
flutter build windows --release
```
- **Output Directory**:
  ```
  app/build/windows/x64/runner/Release/
  ```
- **Executable**:
  ```
  app/build/windows/x64/runner/Release/billket.exe
  ```

### E. Distributing the Windows App
To distribute to another Windows PC without developer tools:
1. Zip the entire `app/build/windows/x64/runner/Release/` directory.
2. Ensure `billket.exe`, `flutter_windows.dll`, and the `data/` folder remain in the same root folder.

---

## 5. Building for Web

PricePilot Bill can run in any modern web browser.

### A. Enable Web in Flutter
```bash
flutter config --enable-web
```

### B. Run in Development
```bash
cd app
flutter run -d chrome
```

### C. Build Production Web Bundle
```bash
cd app
flutter build web --release
```
- **Output Directory**:
  ```
  app/build/web/
  ```

### D. Previewing the Web Build
You can test the static web build locally using Python or Node:
```bash
cd app/build/web
python -m http.server 8080
```
Then navigate to `http://localhost:8080`.

---

## 6. Building for iOS & macOS (Apple Devices)

*(Requires macOS with Xcode installed)*

### A. Run on iOS Simulator or Device
```bash
cd app
flutter run -d ios
```

### B. Build Production IPA
```bash
cd app
flutter build ipa --release
```
- **Output Directory**: `app/build/ios/archive/`

### C. Build macOS Desktop App
```bash
flutter config --enable-macos-desktop
cd app
flutter build macos --release
```
- **Output Directory**: `app/build/macos/Build/Products/Release/`

---

## 7. Running & Building the Backend Server

The backend provides real-time multi-device sync, SQLite cloud backups, and a web admin portal.

### A. Initial Database Setup
```bash
cd backend
npx prisma db push
```
This generates the Prisma client and initializes the local SQLite database.

### B. Run in Development
```bash
cd backend
npm run dev
```
- Server starts at: `http://localhost:3000`
- Web Admin Portal: `http://localhost:3000/admin/`

### C. Build & Run for Production
```bash
cd backend
npm run build
npm start
```

### D. Run Backend Automated Tests
```bash
cd backend
npm test
```

---

## 8. Running Automated Test Suites

Before deploying or submitting pull requests, run all automated test suites to ensure zero regressions:

### App Client Tests (74 unit & integration tests):
```bash
cd app
flutter test
```

### Testing Specific Modules:
```bash
# Database, repository, and calculations:
flutter test test/data/repository_db_test.dart

# Critical business flows (Stock, Offline, Ledgers):
flutter test test/core/critical_business_flows_test.dart

# GST summary and tax reports:
flutter test test/data/repository_gst_test.dart
```

---

## 9. Troubleshooting & FAQ

### 1. `local.properties` Not Found (Android)
- `local.properties` contains your machine-specific Android SDK path and is automatically generated by Flutter.
- Run `flutter pub get` followed by `flutter build apk`.
- If needed, manually create `app/android/local.properties`:
  ```properties
  sdk.dir=C:\\Users\\<YourUsername>\\AppData\\Local\\Android\\Sdk
  flutter.sdk=C:\\path\\to\\flutter
  ```

### 2. Android SDK Licenses Not Accepted
If Gradle complains about missing licenses:
```bash
flutter doctor --android-licenses
```
Press `y` to accept all SDK licenses.

### 3. Java Version Compatibility
- Gradle 9.3+ requires **Java JDK 17 or 21**.
- Check your Java version:
  ```bash
  java -version
  ```
- Ensure `JAVA_HOME` points to your JDK 17+ installation.

### 4. Windows Desktop Build Fails with "Visual Studio is missing components"
- Open **Visual Studio Installer**.
- Click **Modify** on Visual Studio 2022.
- Under the **Workloads** tab, make sure **Desktop development with C++** is checked.
- Under Installation details, ensure **MSVC v143** and **Windows 10/11 SDK** are selected.

---

## 10. Summary Command Cheatsheet

| Target | Command |
| :--- | :--- |
| **Android Release APK** | `cd app && flutter build apk --release` |
| **Android Play Store (.aab)** | `cd app && flutter build appbundle --release` |
| **Android USB Install** | `adb install -r app/build/app/outputs/flutter-apk/app-release.apk` |
| **Windows Desktop (.exe)** | `cd app && flutter build windows --release` |
| **Web Production** | `cd app && flutter build web --release` |
| **Backend Server** | `cd backend && npm run build && npm start` |
| **Test Suite** | `cd app && flutter test` |
