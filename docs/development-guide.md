# Development Guide: TAPIX

## Prerequisites

### Required Software

1. **Flutter SDK** (version 3.10.7 or higher)
   - Download from [flutter.dev](https://flutter.dev/docs/get-started/install)
   - Add Flutter to your PATH
   - Run `flutter doctor` to verify installation

2. **Dart SDK** (included with Flutter)
   - Automatically installed with Flutter SDK
   - Version 3.10.7 or higher

3. **IDE/Editor** (choose one)
   - **Android Studio** with Flutter plugin (recommended)
   - **VS Code** with Flutter extension
   - **IntelliJ IDEA** with Flutter plugin

4. **Platform-Specific Requirements**
   
   **For Android Development:**
   - Android Studio (Android SDK)
   - Java Development Kit (JDK) 17 or higher
   
   **For iOS Development:**
   - Xcode 14.0 or higher
   - iOS Simulator
   - CocoaPods

   **For Web Development:**
   - Chrome browser (for debugging)

   **For Desktop Development:**
   - Windows: Visual Studio 2022 (with C++ workload)
   - Linux: Clang, CMake, GTK development libraries

## Environment Setup

### 1. Clone the Repository

```bash
git clone <repository-url>
cd tapix
```

### 2. Install Dependencies

```bash
flutter pub get
```

### 3. Verify Setup

```bash
flutter doctor -v
```

Ensure all components show "✓" or follow the suggested fixes.

### 4. Platform Setup

#### Android
```bash
flutter config --enable-android
```
- Accept Android licenses if prompted
- Set up an Android device or emulator

#### iOS
```bash
flutter config --enable-ios
```
- Install Xcode if not already installed
- Run `sudo xcode-select --install` if needed

#### Web
```bash
flutter config --enable-web
```

#### Windows Desktop
```bash
flutter config --enable-windows-desktop
```

#### Linux Desktop
```bash
flutter config --enable-linux-desktop
```

## Running the Application

### Development Mode

#### Run on Connected Device
```bash
flutter run
```

#### Run on Specific Platform
```bash
# Android
flutter run -d android

# iOS
flutter run -d ios

# Web
flutter run -d chrome

# Windows
flutter run -d windows

# Linux
flutter run -d linux
```

#### Run with Hot Reload
```bash
flutter run --hot
```
- Press `r` in terminal for hot reload
- Press `R` for hot restart
- Press `q` to quit

### Debug Mode

```bash
flutter run --debug
```

### Profile Mode

```bash
flutter run --profile
```

### Release Mode

```bash
flutter run --release
```

## Build Commands

### Build for Production

#### Android APK
```bash
flutter build apk --release
```

#### Android App Bundle (Recommended for Play Store)
```bash
flutter build appbundle --release
```

#### iOS
```bash
flutter build ios --release
```

#### Web
```bash
flutter build web --release
```

#### Windows
```bash
flutter build windows --release
```

#### Linux
```bash
flutter build linux --release
```

## Testing

### Run All Tests
```bash
flutter test
```

### Run Specific Test File
```bash
flutter test test/widget_test.dart
```

### Run Tests with Coverage
```bash
flutter test --coverage
```

### View Coverage Report
```bash
genhtml coverage/lcov.info -o coverage/html
open coverage/html/index.html
```

### Integration Tests
```bash
flutter drive --target=integration_test/app_test.dart
```

## Development Workflow

### 1. Create a Feature Branch
```bash
git checkout -b feature/your-feature-name
```

### 2. Make Changes
- Edit source files in `lib/` directory
- Add tests in `test/` directory
- Run tests frequently

### 3. Hot Reload During Development
- Run the app with `flutter run`
- Make code changes
- Press `r` in terminal for hot reload

### 4. Run Tests
```bash
flutter test
```

### 5. Analyze Code
```bash
flutter analyze
```

### 6. Format Code
```bash
dart format .
```

### 7. Commit Changes
```bash
git add .
git commit -m "feat: add your feature"
```

### 8. Push and Create PR
```bash
git push origin feature/your-feature-name
```

## Common Development Tasks

### Adding Dependencies

1. Edit `pubspec.yaml`:
```yaml
dependencies:
  flutter:
    sdk: flutter
  your_package: ^1.0.0
```

2. Install:
```bash
flutter pub get
```

### Creating a New Screen

1. Create file `lib/screens/your_screen.dart`:
```dart
import 'package:flutter/material.dart';

class YourScreen extends StatelessWidget {
  const YourScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Your Screen'),
      ),
      body: const Center(
        child: Text('Your Screen Content'),
      ),
    );
  }
}
```

2. Update routing in your app

### Adding Assets

1. Create `assets/` directory
2. Add to `pubspec.yaml`:
```yaml
flutter:
  uses-material-design: true
  assets:
    - assets/images/
    - assets/fonts/
```

### Platform-Specific Code

Use platform channels for native functionality:

```dart
import 'package:flutter/services.dart';

class NativeService {
  static const platform = MethodChannel('com.example.tapix/native');
  
  static Future<String> getNativeData() async {
    try {
      final String result = await platform.invokeMethod('getNativeData');
      return result;
    } on PlatformException catch (e) {
      return "Error: ${e.message}";
    }
  }
}
```

## Debugging

### Flutter Inspector
- Run app in debug mode
- Open Flutter Inspector in your IDE
- Inspect widget tree and properties

### Debugging in Code
```dart
import 'package:flutter/foundation.dart';

// Print debug information
debugPrint('Debug info: $variable');

// Assert statements for debugging
assert(condition, 'Error message if false');
```

### Performance Profiling
```bash
flutter run --profile
```
- Use Flutter Performance overlay
- Check Dart DevTools for detailed profiling

## Environment Variables

Create `.env` file in root (add to `.gitignore`):
```
API_URL=https://api.example.com
DEBUG_MODE=true
```

Use in code with flutter_dotenv package.

## Code Style and Linting

### Current Linting Rules
- Uses `flutter_lints` package
- Configured in `analysis_options.yaml`

### Common Linting Issues and Fixes

1. **prefer_const_constructors**
   ```dart
   // Before
   Text('Hello')
   
   // After
   const Text('Hello')
   ```

2. **prefer_const_literals_to_create_immutables**
   ```dart
   // Before
   final list = [1, 2, 3];
   
   // After
   final list = const [1, 2, 3];
   ```

### Format Code Automatically
```bash
dart format --set-exit-if-changed .
```

## Troubleshooting

### Common Issues

1. **"Flutter command not found"**
   - Verify Flutter installation
   - Check PATH environment variable

2. **"Unable to locate adb"**
   - Install Android Studio
   - Set ANDROID_HOME environment variable

3. **"Pod install failed" (iOS)**
   ```bash
   cd ios
   pod install --repo-update
   cd ..
   ```

4. **Clean build if needed**
   ```bash
   flutter clean
   flutter pub get
   ```

### Getting Help

- Flutter documentation: [flutter.dev/docs](https://flutter.dev/docs)
- Stack Overflow: Search with "flutter" tag
- Flutter Discord community
- GitHub issues for project-specific problems
