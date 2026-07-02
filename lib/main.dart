import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

import 'providers/theme_provider.dart';
import 'providers/navigation_provider.dart';
import 'providers/storage_provider.dart';
import 'services/storage_service.dart';
import 'services/sync_service.dart';
import 'services/download_service.dart';

import 'tabs/home_tab.dart';
import 'tabs/library_tab.dart';
import 'tabs/updates_tab.dart';
import 'tabs/browse_tab.dart';
import 'tabs/history_tab.dart';
import 'tabs/settings_tab.dart';
import 'tabs/onboarding_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize WebView platform for Android/iOS
  if (Platform.isAndroid) {
    AndroidWebViewPlatform.registerWith();
  } else if (Platform.isIOS) {
    WebKitWebViewPlatform.registerWith();
  }

  final storage = StorageService();
  
  // Initialize storage with error handling
  try {
    await storage.init();
  } catch (e, stackTrace) {
    // Log the error but continue to show the app
    debugPrint('Storage initialization error: $e');
    debugPrint('Stack trace: $stackTrace');
  }

  // Apply the configured desktop download folder, if one was picked.
  try {
    DownloadService.configureDirectory(
      storage.settingsBox.get('download_dir') as String?,
    );
  } catch (e) {
    debugPrint('Download folder configuration error: $e');
  }

  // Initialize sync service (notifications and background tasks)
  try {
    await SyncService.initializeNotifications();
    await SyncService.initializeBackgroundSync();
  } catch (e) {
    debugPrint('Sync service initialization error: $e');
  }

  runApp(
    ProviderScope(
      overrides: [storageProvider.overrideWithValue(storage)],
      child: const Ao3ReaderApp(),
    ),
  );
}

class Ao3ReaderApp extends ConsumerWidget {
  const Ao3ReaderApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeProvider);

    return MaterialApp(
      title: 'AO3 Reader',
      debugShowCheckedModeBanner: false,
      themeMode: themeMode,
      theme: ThemeData.light().copyWith(useMaterial3: true),
      darkTheme: ThemeData.dark().copyWith(useMaterial3: true),
      home: const RootGate(),
    );
  }
}

/// Shows first-run onboarding until it has been completed, then the main app.
/// If storage is unavailable, defaults to the main app rather than blocking.
class RootGate extends ConsumerStatefulWidget {
  const RootGate({super.key});

  @override
  ConsumerState<RootGate> createState() => _RootGateState();
}

class _RootGateState extends ConsumerState<RootGate> {
  bool _showOnboarding = false;

  @override
  void initState() {
    super.initState();
    try {
      final storage = ref.read(storageProvider);
      _showOnboarding =
          storage.settingsBox.get('onboarding_complete', defaultValue: false) !=
              true;
    } catch (e) {
      debugPrint('Onboarding flag unavailable, skipping onboarding: $e');
      _showOnboarding = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_showOnboarding) {
      return OnboardingScreen(
        onDone: () => setState(() => _showOnboarding = false),
      );
    }
    return const MainScaffold();
  }
}

class MainScaffold extends ConsumerWidget {
  const MainScaffold({super.key});

  static const List<Widget> _tabs = <Widget>[
    HomeTab(),
    LibraryTab(),
    UpdatesTab(),
    BrowseTab(),
    HistoryTab(),
    SettingsTab(),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final index = ref.watch(navigationProvider);
    final notifier = ref.read(navigationProvider.notifier);

    return Scaffold(
      body: IndexedStack(index: index, children: _tabs),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: notifier.setIndex,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home), label: 'Home'),
          NavigationDestination(
            icon: Icon(Icons.library_books),
            label: 'Library',
          ),
          NavigationDestination(icon: Icon(Icons.update), label: 'Updates'),
          NavigationDestination(icon: Icon(Icons.language), label: 'Browse'),
          NavigationDestination(icon: Icon(Icons.history), label: 'History'),
          NavigationDestination(icon: Icon(Icons.settings), label: 'Settings'),
        ],
      ),
    );
  }
}
