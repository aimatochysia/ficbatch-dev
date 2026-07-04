import 'dart:io' show Platform, File;
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/theme_provider.dart';
import '../providers/storage_provider.dart';
import '../services/sync_service.dart';
import '../services/library_export_service.dart';
import '../services/download_service.dart';
import '../services/lan_sync_service.dart' show LanPeer;
import 'onboarding_screen.dart';
import 'reader_screen.dart' show ReaderScreen;

/// Reader mode options for controlling content source
enum ReaderMode {
  preferOnline('Prefer Online', 'Use online version when available, fallback to downloaded'),
  preferDownloaded('Prefer Downloaded', 'Use downloaded version when available to save data'),
  alwaysOnline('Always Online', 'Force online version only (no offline reading)'),
  alwaysDownloaded('Always Downloaded', 'Force downloaded version only (no online loading)');

  final String label;
  final String description;
  const ReaderMode(this.label, this.description);
}

/// Provider for reader mode setting
final readerModeProvider = StateNotifierProvider<ReaderModeNotifier, ReaderMode>((ref) {
  final storage = ref.watch(storageProvider);
  final savedIndex = storage.settingsBox.get('reader_mode', defaultValue: 0);
  final index = (savedIndex is int && savedIndex >= 0 && savedIndex < ReaderMode.values.length) 
      ? savedIndex 
      : 0;
  return ReaderModeNotifier(ReaderMode.values[index], storage);
});

class ReaderModeNotifier extends StateNotifier<ReaderMode> {
  final dynamic _storage;
  
  ReaderModeNotifier(super.state, this._storage);
  
  Future<void> setMode(ReaderMode mode) async {
    state = mode;
    await _storage.settingsBox.put('reader_mode', mode.index);
  }
}

/// Provider for library grid columns setting
final libraryGridColumnsProvider = StateNotifierProvider<LibraryGridColumnsNotifier, int>((ref) {
  final storage = ref.watch(storageProvider);
  final saved = storage.settingsBox.get('library_grid_columns', defaultValue: 4);
  return LibraryGridColumnsNotifier(saved is int ? saved : 4, storage);
});

class LibraryGridColumnsNotifier extends StateNotifier<int> {
  final dynamic _storage;
  
  LibraryGridColumnsNotifier(super.state, this._storage);
  
  Future<void> setColumns(int columns) async {
    state = columns;
    await _storage.settingsBox.put('library_grid_columns', columns);
  }
}

/// Library view mode (grid or list)
enum LibraryViewMode {
  grid('Grid', 'Display works as cards in a grid'),
  list('List', 'Display works in a compact list');

  final String label;
  final String description;
  const LibraryViewMode(this.label, this.description);
}

/// Provider for library view mode setting (grid vs list)
final libraryViewModeProvider = StateNotifierProvider<LibraryViewModeNotifier, LibraryViewMode>((ref) {
  final storage = ref.watch(storageProvider);
  final savedIndex = storage.settingsBox.get('library_view_mode', defaultValue: 0);
  final index = (savedIndex is int && savedIndex >= 0 && savedIndex < LibraryViewMode.values.length) 
      ? savedIndex 
      : 0;
  return LibraryViewModeNotifier(LibraryViewMode.values[index], storage);
});

class LibraryViewModeNotifier extends StateNotifier<LibraryViewMode> {
  final dynamic _storage;
  
  LibraryViewModeNotifier(super.state, this._storage);
  
  Future<void> setMode(LibraryViewMode mode) async {
    state = mode;
    await _storage.settingsBox.put('library_view_mode', mode.index);
  }
}

/// Provider for sync settings
final syncSettingsProvider = StateNotifierProvider<SyncSettingsNotifier, SyncSettings>((ref) {
  final storage = ref.watch(storageProvider);
  return SyncSettingsNotifier(storage);
});

class SyncSettings {
  final bool autoSyncEnabled;
  final SyncInterval interval;
  final SyncNetworkPreference networkPreference;
  final DateTime? lastSyncTime;
  
  SyncSettings({
    this.autoSyncEnabled = false,
    this.interval = SyncInterval.daily,
    this.networkPreference = SyncNetworkPreference.wifiOnly,
    this.lastSyncTime,
  });
  
  SyncSettings copyWith({
    bool? autoSyncEnabled,
    SyncInterval? interval,
    SyncNetworkPreference? networkPreference,
    DateTime? lastSyncTime,
  }) => SyncSettings(
    autoSyncEnabled: autoSyncEnabled ?? this.autoSyncEnabled,
    interval: interval ?? this.interval,
    networkPreference: networkPreference ?? this.networkPreference,
    lastSyncTime: lastSyncTime ?? this.lastSyncTime,
  );
}

class SyncSettingsNotifier extends StateNotifier<SyncSettings> {
  final dynamic _storage;
  
  SyncSettingsNotifier(this._storage) : super(SyncSettings()) {
    _loadSettings();
  }
  
  Future<void> _loadSettings() async {
    try {
      final box = _storage.settingsBox;
      final enabled = box.get('auto_sync_enabled', defaultValue: false);
      final intervalIndex = box.get('sync_interval', defaultValue: 1);
      final networkIndex = box.get('sync_network_preference', defaultValue: 0);
      final lastSyncStr = box.get('last_sync_time');
      
      state = SyncSettings(
        autoSyncEnabled: enabled == true,
        interval: SyncInterval.values[intervalIndex is int ? intervalIndex : 1],
        networkPreference: SyncNetworkPreference.values[networkIndex is int ? networkIndex : 0],
        lastSyncTime: lastSyncStr != null ? DateTime.tryParse(lastSyncStr.toString()) : null,
      );
      
      // Initialize Windows sync timer if auto-sync was enabled
      if (Platform.isWindows && state.autoSyncEnabled) {
        WindowsSyncManager().startSync(state.interval, state.networkPreference);
      }
    } catch (e) {
      debugPrint('Error loading sync settings: $e');
    }
  }
  
  Future<void> setAutoSyncEnabled(bool enabled) async {
    state = state.copyWith(autoSyncEnabled: enabled);
    await _storage.settingsBox.put('auto_sync_enabled', enabled);

    // Ask for the notification permission up-front so update alerts can appear
    // (Android 13+ requires a runtime grant).
    if (enabled) {
      await SyncService.ensureNotificationPermission();
    }

    if (Platform.isWindows) {
      // Use Windows in-app timer
      if (enabled) {
        WindowsSyncManager().startSync(state.interval, state.networkPreference);
      } else {
        WindowsSyncManager().stopSync();
      }
    } else {
      // Use Workmanager for mobile
      if (enabled) {
        await SyncService.scheduleSync(
          interval: state.interval,
          networkPreference: state.networkPreference,
        );
      } else {
        await SyncService.cancelSync();
      }
    }
  }
  
  Future<void> setInterval(SyncInterval interval) async {
    state = state.copyWith(interval: interval);
    await _storage.settingsBox.put('sync_interval', interval.index);
    
    if (state.autoSyncEnabled) {
      if (Platform.isWindows) {
        WindowsSyncManager().startSync(interval, state.networkPreference);
      } else {
        await SyncService.scheduleSync(
          interval: interval,
          networkPreference: state.networkPreference,
        );
      }
    }
  }
  
  Future<void> setNetworkPreference(SyncNetworkPreference preference) async {
    state = state.copyWith(networkPreference: preference);
    await _storage.settingsBox.put('sync_network_preference', preference.index);
    
    if (state.autoSyncEnabled) {
      if (Platform.isWindows) {
        WindowsSyncManager().startSync(state.interval, preference);
      } else {
        await SyncService.scheduleSync(
          interval: state.interval,
          networkPreference: preference,
        );
      }
    }
  }
  
  void updateLastSyncTime(DateTime time) {
    state = state.copyWith(lastSyncTime: time);
  }
}

class SettingsTab extends ConsumerStatefulWidget {
  const SettingsTab({super.key});

  @override
  ConsumerState<SettingsTab> createState() => _SettingsTabState();
}

/// Windows in-app sync manager (singleton pattern since Workmanager doesn't work on Windows)
class WindowsSyncManager {
  static final WindowsSyncManager _instance = WindowsSyncManager._internal();
  factory WindowsSyncManager() => _instance;
  WindowsSyncManager._internal();
  
  Timer? _syncTimer;
  
  void startSync(SyncInterval interval, SyncNetworkPreference networkPreference) {
    _syncTimer?.cancel();
    if (!Platform.isWindows) return;
    
    _syncTimer = Timer.periodic(Duration(hours: interval.hours), (timer) async {
      debugPrint('[WindowsSync] Running scheduled sync...');
      try {
        final syncService = SyncService();
        final canSync = await syncService.canSyncWithCurrentNetwork(networkPreference);
        if (canSync) {
          await syncService.performSync();
        }
      } catch (e) {
        debugPrint('[WindowsSync] Sync error: $e');
      }
    });
    debugPrint('[WindowsSync] Started timer for every ${interval.hours} hours');
  }
  
  void stopSync() {
    _syncTimer?.cancel();
    _syncTimer = null;
    debugPrint('[WindowsSync] Stopped timer');
  }
  
  bool get isRunning => _syncTimer != null && _syncTimer!.isActive;
}

class _SettingsTabState extends ConsumerState<SettingsTab> {
  bool _isSyncing = false;
  bool _isExporting = false;
  bool _isImporting = false;

  Future<void> _performManualSync() async {
    setState(() => _isSyncing = true);

    try {
      await SyncService.ensureNotificationPermission();
      final syncService = SyncService();
      final syncSettings = ref.read(syncSettingsProvider);
      
      // Check network preference
      final canSync = await syncService.canSyncWithCurrentNetwork(
        syncSettings.networkPreference,
      );
      
      if (!canSync) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Cannot sync: Wi-Fi required but not connected'),
            ),
          );
        }
        return;
      }
      
      final updates = await syncService.performSync();
      
      if (mounted) {
        ref.read(syncSettingsProvider.notifier).updateLastSyncTime(DateTime.now());
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              updates.isEmpty 
                  ? 'Sync complete. No updates found.'
                  : 'Sync complete. Found ${updates.length} update(s).',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sync error: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSyncing = false);
      }
    }
  }

  Future<void> _exportLibrary() async {
    setState(() => _isExporting = true);

    try {
      final storage = ref.read(storageProvider);
      final exportService = LibraryExportService(storage);
      final json = await exportService.exportToJson();
      final fileName =
          'ficbatch_library_${DateTime.now().toIso8601String().replaceAll(':', '-').split('.').first}.json';

      // Prefer a native save dialog; fall back to writing to the default
      // export directory if the picker is unavailable on this platform.
      String? savedPath;
      try {
        savedPath = await FilePicker.saveFile(
          dialogTitle: 'Save library export',
          fileName: fileName,
          bytes: Uint8List.fromList(utf8.encode(json)),
        );
        // On desktop the picker returns the chosen path but does not write the
        // file; do it ourselves. On mobile the bytes are already written.
        if (savedPath != null &&
            (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
          await File(savedPath).writeAsString(json);
        }
      } catch (e) {
        debugPrint('Save dialog unavailable, using default path: $e');
        savedPath = await exportService.exportToFile();
      }

      if (savedPath == null) return; // user cancelled
      if (mounted) _showExportSuccessDialog(savedPath);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export error: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isExporting = false);
      }
    }
  }

  void _showExportSuccessDialog(String filePath) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Export Successful'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Library exported successfully to:'),
            const SizedBox(height: 8),
            SelectableText(
              filePath,
              style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
            ),
            const SizedBox(height: 16),
            const Text(
              'You can copy this file to another device and import it there.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: filePath));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Path copied to clipboard')),
              );
            },
            child: const Text('Copy Path'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _importLibrary() async {
    String? content;
    try {
      final result = await FilePicker.pickFiles(
        dialogTitle: 'Select library JSON',
        type: FileType.custom,
        allowedExtensions: const ['json'],
        withData: true,
      );
      if (result == null) return; // cancelled
      final picked = result.files.single;
      if (picked.bytes != null) {
        content = utf8.decode(picked.bytes!);
      } else if (picked.path != null) {
        content = await File(picked.path!).readAsString();
      }
    } catch (e) {
      debugPrint('File picker unavailable, falling back to paste: $e');
      await _importViaPaste();
      return;
    }

    if (content == null || content.isEmpty) return;
    final mode = await _askImportMode();
    if (mode == null) return;
    await _runImport(content, mode);
  }

  Future<ImportMode?> _askImportMode() {
    return showDialog<ImportMode>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Import Mode'),
        content: const Text(
          '• Merge: add new works, update existing (preserves reading progress)\n'
          '• Replace: clear the library and import all data',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, ImportMode.merge),
              child: const Text('Merge')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, ImportMode.replace),
              child: const Text('Replace All')),
        ],
      ),
    );
  }

  Future<void> _runImport(String content, ImportMode mode) async {
    setState(() => _isImporting = true);
    try {
      final storage = ref.read(storageProvider);
      final exportService = LibraryExportService(storage);
      final importResult = _isFilePath(content)
          ? await exportService.importFromFile(content.trim(), mode: mode)
          : await exportService.importFromJson(content, mode: mode);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Import complete: ${importResult.toSummary()}'),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Import error: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isImporting = false);
      }
    }
  }

  /// Fallback import for platforms where the native file picker is unavailable:
  /// paste the library JSON or a file path.
  Future<void> _importViaPaste() async {
    final controller = TextEditingController();
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Import Library'),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Paste the library JSON content below, or enter a file path:',
                style: TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                maxLines: 10,
                decoration: const InputDecoration(
                  hintText:
                      '{"version": 1, "works": [...], ...}\n\nOr paste file path',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, {
              'content': controller.text,
              'mode': ImportMode.merge,
            }),
            child: const Text('Merge Import'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, {
              'content': controller.text,
              'mode': ImportMode.replace,
            }),
            child: const Text('Replace All'),
          ),
        ],
      ),
    );

    controller.dispose();
    if (result == null) return;
    final content = result['content'] as String;
    final mode = result['mode'] as ImportMode;
    if (content.isEmpty) return;
    await _runImport(content, mode);
  }

  bool _isFilePath(String content) {
    final trimmed = content.trim();
    // Check if it looks like a file path
    if (Platform.isWindows) {
      return trimmed.contains(':\\') || trimmed.startsWith('\\\\');
    } else {
      return trimmed.startsWith('/');
    }
  }

  Future<void> _showStorageInfo() async {
    final storage = ref.read(storageProvider);
    final works = storage.getAllWorks();
    final categories = await storage.getCategories();
    final downloadSize = await DownloadService.getStorageUsage();
    
    if (!mounted) return;
    
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Storage Info'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _storageInfoRow('Works in library', '${works.length}'),
            _storageInfoRow('Categories', '${categories.length}'),
            _storageInfoRow('Downloaded works', '${works.where((w) => w.isDownloaded).length}'),
            _storageInfoRow('Download storage', _formatBytes(downloadSize)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  bool _isFolderSyncing = false;

  /// On Android, writing to a user-visible folder (where Syncthing/Dropbox
  /// can see it) requires all-files access. Returns true when we may proceed.
  Future<bool> _ensureStorageAccess() async {
    if (!Platform.isAndroid) return true;
    var status = await Permission.manageExternalStorage.status;
    if (status.isGranted) return true;
    status = await Permission.manageExternalStorage.request();
    if (status.isGranted) return true;
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Folder sync needs "All files access" — enable it for FicBatch '
              'in the system settings page that just opened, then try again.'),
          duration: Duration(seconds: 6),
        ),
      );
    }
    return false;
  }

  /// Pick the sync folder and enable folder sync.
  Future<void> _pickSyncFolder() async {
    if (!await _ensureStorageAccess()) return;
    String? selected;
    try {
      selected = await FilePicker.getDirectoryPath(
          dialogTitle: 'Choose sync folder');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Folder picker unavailable: $e')),
        );
      }
      return;
    }
    if (selected == null) return;

    final syncFolder = ref.read(syncFolderProvider);
    await syncFolder.configure(enabled: true, path: selected);
    if (mounted) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Sync folder set to $selected')),
      );
    }
  }

  /// Manual import-then-export against the sync folder.
  Future<void> _syncFolderNow() async {
    setState(() => _isFolderSyncing = true);
    try {
      final result = await ref.read(syncFolderProvider).syncNow();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result == null
                ? 'Sync folder up to date (exported current state)'
                : 'Synced: ${result.toSummary()}'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Folder sync error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isFolderSyncing = false);
    }
  }

  /// Edit the LAN sync device name and pairing code.
  Future<void> _configureLanSync() async {
    final lanSync = ref.read(lanSyncProvider);
    final nameController = TextEditingController(text: lanSync.deviceName);
    final codeController = TextEditingController(text: lanSync.pairingCode);
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('LAN Sync Settings'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: 'Device name',
                helperText: 'Shown to other devices on the network',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: codeController,
              decoration: const InputDecoration(
                labelText: 'Pairing code (optional)',
                helperText: 'Devices only sync when their codes match',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Save')),
        ],
      ),
    );
    if (saved == true) {
      await lanSync.configure(
        enabled: lanSync.enabled,
        deviceName: nameController.text,
        code: codeController.text,
      );
      if (mounted) setState(() {});
    }
  }

  String _formatAgo(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inSeconds < 60) return '${d.inSeconds}s ago';
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    return '${d.inHours}h ago';
  }

  /// Sync with one specific discovered device right now.
  Future<void> _syncWithLanPeer(LanPeer peer) async {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Syncing with ${peer.name}…')),
    );
    await ref
        .read(lanSyncProvider)
        .syncWithPeer(peer.address, peer.port, name: peer.name);
    if (mounted) setState(() {});
  }

  /// Manual LAN sync: re-announce immediately so nearby peers handshake now.
  Future<void> _lanSyncNow() async {
    await ref.read(lanSyncProvider).syncNow();
    if (mounted) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Announced to the network — devices on this Wi-Fi '
              'with the same pairing code merge within a few seconds'),
        ),
      );
    }
  }

  /// Clear the reading history list (works and downloads are untouched).
  Future<void> _clearReadingHistory() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear Reading History'),
        content: const Text(
            'Delete all reading history entries? Your library, reading '
            'progress and downloads are not affected.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Clear')),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(storageProvider).clearHistory();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Reading history cleared')),
      );
    }
  }

  /// Wipe everything: library, categories, history, updates, settings and
  /// downloaded files. Requires typing RESET to confirm.
  Future<void> _resetAppData() async {
    final controller = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Reset App Data'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'This permanently deletes your entire library, categories, '
                'reading history, update list, settings and all downloaded '
                'files. This cannot be undone.\n\n'
                'Type RESET to confirm:',
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'RESET',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (_) => setDialogState(() {}),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            TextButton(
              onPressed: controller.text.trim() == 'RESET'
                  ? () => Navigator.pop(ctx, true)
                  : null,
              child: const Text('Reset Everything'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (confirmed != true) return;

    try {
      final storage = ref.read(storageProvider);
      await DownloadService.clearAllDownloads();
      await storage.clearAll(); // works box
      await storage.settingsBox.clear(); // categories, history, settings…
      // Also clear SharedPreferences (theme mode lives there).
      final sp = await SharedPreferences.getInstance();
      await sp.clear();
      DownloadService.configureDirectory(null);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('App data reset. Restart the app to start fresh.'),
            duration: Duration(seconds: 5),
          ),
        );
        setState(() {});
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Reset error: $e')),
        );
      }
    }
  }

  /// Pick a desktop download folder, persist it, and optionally migrate
  /// existing downloads into it.
  Future<void> _pickDownloadFolder() async {
    final storage = ref.read(storageProvider);
    String? selected;
    try {
      selected = await FilePicker.getDirectoryPath(
          dialogTitle: 'Choose download folder');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Folder picker unavailable: $e')),
        );
      }
      return;
    }
    if (selected == null) return; // cancelled

    final oldDir = await DownloadService.getDownloadsDirectory();
    await storage.settingsBox.put('download_dir', selected);
    DownloadService.configureDirectory(selected);
    if (!mounted) return;
    setState(() {});

    if (oldDir.path == selected) return;
    final migrate = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Move existing downloads?'),
        content: Text(
          'Copy already-downloaded works into the new folder?\n\n'
          'From: ${oldDir.path}\nTo: $selected',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Skip')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Move')),
        ],
      ),
    );
    if (migrate == true) {
      final count = await DownloadService.migrateDownloadsFrom(oldDir);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Migrated $count download(s)')),
        );
      }
    }
  }

  /// Delete all downloaded work files and clear their downloaded flags.
  Future<void> _clearAllDownloads() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear All Downloads'),
        content: const Text(
          'Delete all downloaded work files? Works stay in your library and '
          'can be re-downloaded.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Clear')),
        ],
      ),
    );
    if (confirm != true) return;

    final count = await DownloadService.clearAllDownloads();
    final storage = ref.read(storageProvider);
    for (final w in storage.getAllWorks()) {
      if (w.isDownloaded) {
        await storage.saveWork(w.copyWith(isDownloaded: false));
      }
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Cleared $count download(s)')),
      );
    }
  }

  Widget _storageInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  /// Edit the default reader appearance. These defaults are stored under the
  /// `reader_settings` key and read by ReaderScreen each time a work is opened.
  Future<void> _showReaderSettingsDialog() async {
    final storage = ref.read(storageProvider);
    final raw = storage.settingsBox.get('reader_settings');
    final settings =
        raw != null ? Map<String, dynamic>.from(raw) : <String, dynamic>{};

    double fontSize = (settings['fontSize'] ?? 16.0).toDouble();
    double lineHeight = (settings['lineHeight'] ?? 1.5).toDouble();
    String fontFamily = settings['fontFamily'] ?? 'Default';
    String readingTheme = settings['readingTheme'] ?? 'default';
    bool chapterJump = settings['chapterJump'] ?? true;
    bool autosave = settings['autosave'] ?? true;

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Font & Reader Settings'),
        content: SizedBox(
          width: double.maxFinite,
          child: StatefulBuilder(
            builder: (ctx, setDialogState) => SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    title: const Text('Font Size'),
                    subtitle: Slider(
                      value: fontSize,
                      min: 12,
                      max: 32,
                      divisions: 20,
                      label: fontSize.round().toString(),
                      onChanged: (v) => setDialogState(() => fontSize = v),
                    ),
                    trailing: Text('${fontSize.round()}'),
                  ),
                  ListTile(
                    title: const Text('Line Height'),
                    subtitle: Slider(
                      value: lineHeight,
                      min: 1.0,
                      max: 2.5,
                      divisions: 15,
                      label: lineHeight.toStringAsFixed(1),
                      onChanged: (v) => setDialogState(() => lineHeight = v),
                    ),
                    trailing: Text(lineHeight.toStringAsFixed(1)),
                  ),
                  ListTile(
                    title: const Text('Font Family'),
                    trailing: DropdownButton<String>(
                      value: fontFamily,
                      onChanged: (v) =>
                          setDialogState(() => fontFamily = v ?? 'Default'),
                      items: const [
                        DropdownMenuItem(
                            value: 'Default', child: Text('Default')),
                        DropdownMenuItem(value: 'Serif', child: Text('Serif')),
                        DropdownMenuItem(
                            value: 'Sans-serif', child: Text('Sans-serif')),
                        DropdownMenuItem(
                            value: 'Monospace', child: Text('Monospace')),
                      ],
                    ),
                  ),
                  ListTile(
                    title: const Text('Reading Theme'),
                    subtitle:
                        const Text('Palettes override the app light/dark'),
                    trailing: DropdownButton<String>(
                      value: readingTheme,
                      onChanged: (v) =>
                          setDialogState(() => readingTheme = v ?? 'default'),
                      items: ReaderScreen.readingThemeLabels.entries
                          .map((e) => DropdownMenuItem(
                              value: e.key, child: Text(e.value)))
                          .toList(),
                    ),
                  ),
                  SwitchListTile(
                    title: const Text('Chapter Jump Button'),
                    value: chapterJump,
                    onChanged: (v) => setDialogState(() => chapterJump = v),
                  ),
                  SwitchListTile(
                    title: const Text('Autosave Reading Progress'),
                    value: autosave,
                    onChanged: (v) => setDialogState(() => autosave = v),
                  ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (saved == true) {
      await storage.settingsBox.put('reader_settings', {
        'fontSize': fontSize,
        'lineHeight': lineHeight,
        'fontFamily': fontFamily,
        'readingTheme': readingTheme,
        'chapterJump': chapterJump,
        'autosave': autosave,
        // Preserve any scrollSpeed already stored (set from the reader).
        'scrollSpeed': (settings['scrollSpeed'] ?? 1.0),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Reader settings saved')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider);
    final themeNotifier = ref.read(themeProvider.notifier);
    final gridColumns = ref.watch(libraryGridColumnsProvider);
    final gridNotifier = ref.read(libraryGridColumnsProvider.notifier);
    final viewMode = ref.watch(libraryViewModeProvider);
    final viewModeNotifier = ref.read(libraryViewModeProvider.notifier);
    final syncSettings = ref.watch(syncSettingsProvider);
    final syncNotifier = ref.read(syncSettingsProvider.notifier);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: ListView(
          children: [
            // Theme setting
            ListTile(
              leading: const Icon(Icons.palette),
              title: const Text('Theme'),
              subtitle: Text(
                theme == ThemeMode.dark
                    ? 'Dark'
                    : theme == ThemeMode.light
                        ? 'Light'
                        : 'System',
              ),
              trailing: PopupMenuButton<ThemeMode>(
                onSelected: themeNotifier.setMode,
                itemBuilder: (context) => const [
                  PopupMenuItem(
                    value: ThemeMode.system,
                    child: Text('System'),
                  ),
                  PopupMenuItem(
                    value: ThemeMode.light,
                    child: Text('Light'),
                  ),
                  PopupMenuItem(
                    value: ThemeMode.dark,
                    child: Text('Dark'),
                  ),
                ],
              ),
            ),

            // App color personality (Material 3 seed — tints buttons, cards…)
            Builder(
              builder: (context) {
                final appColor = ref.watch(appColorProvider);
                final notifier = ref.read(appColorProvider.notifier);
                return ListTile(
                  leading: Icon(Icons.color_lens, color: appColor.seed),
                  title: const Text('App Color'),
                  subtitle: Text(appColor.label),
                  trailing: PopupMenuButton<AppColorTheme>(
                    onSelected: notifier.setTheme,
                    itemBuilder: (context) => AppColorTheme.values
                        .map((t) => PopupMenuItem(
                              value: t,
                              child: Row(
                                children: [
                                  Container(
                                    width: 18,
                                    height: 18,
                                    decoration: BoxDecoration(
                                      color: t.seed,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Text(t.label),
                                ],
                              ),
                            ))
                        .toList(),
                  ),
                );
              },
            ),

            const Divider(),

            // Library View Mode (Grid vs List)
            ListTile(
              leading: Icon(viewMode == LibraryViewMode.grid ? Icons.grid_view : Icons.list),
              title: const Text('Library View Mode'),
              subtitle: Text(viewMode.label),
              trailing: PopupMenuButton<LibraryViewMode>(
                onSelected: viewModeNotifier.setMode,
                itemBuilder: (context) => LibraryViewMode.values
                    .map((mode) => PopupMenuItem(
                          value: mode,
                          child: Row(
                            children: [
                              Icon(mode == LibraryViewMode.grid ? Icons.grid_view : Icons.list, size: 20),
                              const SizedBox(width: 8),
                              Text(mode.label),
                            ],
                          ),
                        ))
                    .toList(),
              ),
            ),
            
            // Library Grid Size (only show when in grid mode)
            if (viewMode == LibraryViewMode.grid)
              ListTile(
                leading: const Icon(Icons.grid_on),
                title: const Text('Library Grid Columns'),
                subtitle: Text('$gridColumns columns'),
              trailing: PopupMenuButton<int>(
                onSelected: gridNotifier.setColumns,
                itemBuilder: (context) => [
                  const PopupMenuItem(value: 2, child: Text('2 columns')),
                  const PopupMenuItem(value: 3, child: Text('3 columns')),
                  const PopupMenuItem(value: 4, child: Text('4 columns')),
                  const PopupMenuItem(value: 5, child: Text('5 columns')),
                  const PopupMenuItem(value: 6, child: Text('6 columns')),
                ],
              ),
            ),
            
            const Divider(),
            
            // Sync Settings Section
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                'Sync Settings',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey,
                ),
              ),
            ),
            
            // Auto Sync Toggle
            SwitchListTile(
              secondary: const Icon(Icons.sync),
              title: const Text('Auto Sync'),
              subtitle: Text(
                Platform.isWindows
                    ? 'In-app sync (requires app to be running)'
                    : 'Automatically check for work updates',
              ),
              value: syncSettings.autoSyncEnabled,
              onChanged: syncNotifier.setAutoSyncEnabled,
            ),
            
            // Sync Interval
            ListTile(
              leading: const Icon(Icons.schedule),
              title: const Text('Sync Interval'),
              subtitle: Text(syncSettings.interval.label),
              enabled: syncSettings.autoSyncEnabled,
              trailing: PopupMenuButton<SyncInterval>(
                enabled: syncSettings.autoSyncEnabled,
                onSelected: syncNotifier.setInterval,
                itemBuilder: (context) => SyncInterval.values
                    .map((i) => PopupMenuItem(value: i, child: Text(i.label)))
                    .toList(),
              ),
            ),
            
            // Network Preference
            ListTile(
              leading: const Icon(Icons.wifi),
              title: const Text('Sync Network'),
              subtitle: Text(syncSettings.networkPreference.label),
              trailing: PopupMenuButton<SyncNetworkPreference>(
                onSelected: syncNotifier.setNetworkPreference,
                itemBuilder: (context) => SyncNetworkPreference.values
                    .map((p) => PopupMenuItem(value: p, child: Text(p.label)))
                    .toList(),
              ),
            ),
            
            // Last Sync Time
            ListTile(
              leading: const Icon(Icons.history),
              title: const Text('Last Sync'),
              subtitle: Text(
                syncSettings.lastSyncTime != null
                    ? _formatDateTime(syncSettings.lastSyncTime!)
                    : 'Never',
              ),
            ),
            
            // Manual Sync Button
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: ElevatedButton.icon(
                onPressed: _isSyncing ? null : _performManualSync,
                icon: _isSyncing
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.sync),
                label: Text(_isSyncing ? 'Syncing...' : 'Sync Now'),
              ),
            ),
            
            const Divider(),
            
            // Data Management Section
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                'Data Management',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey,
                ),
              ),
            ),
            
            // Export Library
            ListTile(
              leading: const Icon(Icons.upload),
              title: const Text('Export Library'),
              subtitle: const Text('Save library to JSON file'),
              trailing: _isExporting
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.chevron_right),
              onTap: _isExporting ? null : _exportLibrary,
            ),
            
            // Import Library
            ListTile(
              leading: const Icon(Icons.download),
              title: const Text('Import Library'),
              subtitle: const Text('Load library from JSON file or data'),
              trailing: _isImporting
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.chevron_right),
              onTap: _isImporting ? null : _importLibrary,
            ),
            
            // Storage Info
            ListTile(
              leading: const Icon(Icons.storage),
              title: const Text('Storage Info'),
              subtitle: const Text('View storage usage'),
              trailing: const Icon(Icons.chevron_right),
              onTap: _showStorageInfo,
            ),

            // Clear reading history
            ListTile(
              leading: const Icon(Icons.history_toggle_off),
              title: const Text('Clear Reading History'),
              subtitle: const Text('Delete the history list only'),
              onTap: _clearReadingHistory,
            ),

            // Reset app data (danger)
            ListTile(
              leading: Icon(Icons.delete_forever,
                  color: Theme.of(context).colorScheme.error),
              title: Text(
                'Reset App Data',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              subtitle: const Text(
                  'Erase library, settings, history and downloads'),
              onTap: _resetAppData,
            ),

            const Divider(),

            // Downloads Section
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                'Downloads',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey,
                ),
              ),
            ),

            // Download folder (desktop only; mobile uses the sandboxed app dir)
            if (Platform.isWindows || Platform.isLinux || Platform.isMacOS)
              ListTile(
                leading: const Icon(Icons.folder),
                title: const Text('Download Folder'),
                subtitle: Text(
                  DownloadService.customDirPath ?? 'Default app folder',
                ),
                trailing: const Icon(Icons.edit),
                onTap: _pickDownloadFolder,
              ),

            // Global auto-download toggle
            Builder(
              builder: (context) {
                final storage = ref.read(storageProvider);
                final enabled = storage.settingsBox
                        .get('auto_download_global', defaultValue: false) ==
                    true;
                return SwitchListTile(
                  secondary: const Icon(Icons.download_for_offline),
                  title: const Text('Auto-download new works'),
                  subtitle:
                      const Text('Download works automatically when imported'),
                  value: enabled,
                  onChanged: (v) async {
                    await storage.settingsBox.put('auto_download_global', v);
                    setState(() {});
                  },
                );
              },
            ),

            // Throttle delay selector
            Builder(
              builder: (context) {
                final storage = ref.read(storageProvider);
                final raw = storage.settingsBox
                    .get('download_throttle_ms', defaultValue: 1000);
                final ms = raw is int ? raw : 1000;
                return ListTile(
                  leading: const Icon(Icons.speed),
                  title: const Text('Download Throttle'),
                  subtitle: Text('${(ms / 1000).toStringAsFixed(1)}s between downloads'),
                  trailing: PopupMenuButton<int>(
                    onSelected: (v) async {
                      await storage.settingsBox.put('download_throttle_ms', v);
                      setState(() {});
                    },
                    itemBuilder: (context) => const [
                      PopupMenuItem(value: 500, child: Text('0.5s (faster)')),
                      PopupMenuItem(value: 1000, child: Text('1s (default)')),
                      PopupMenuItem(value: 2000, child: Text('2s')),
                      PopupMenuItem(value: 3000, child: Text('3s (gentler)')),
                    ],
                  ),
                );
              },
            ),

            // Clear all downloads
            ListTile(
              leading: const Icon(Icons.delete_sweep),
              title: const Text('Clear All Downloads'),
              subtitle: const Text('Delete all downloaded work files'),
              onTap: _clearAllDownloads,
            ),

            const Divider(),

            // Sync Folder Section (cross-device sync via a shared folder)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                'Sync Folder (Cross-Device)',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey,
                ),
              ),
            ),
            Builder(
              builder: (context) {
                final syncFolder = ref.read(syncFolderProvider);
                // Desktop + Android (Android needs the all-files permission,
                // requested when picking the folder). iOS keeps export/import.
                final supported = Platform.isWindows ||
                    Platform.isLinux ||
                    Platform.isMacOS ||
                    Platform.isAndroid;
                return Column(
                  children: [
                    SwitchListTile(
                      secondary: const Icon(Icons.folder_shared),
                      title: const Text('Sync via folder'),
                      subtitle: Text(
                        syncFolder.enabled
                            ? (syncFolder.folderPath ?? 'No folder chosen')
                            : 'Auto-export library, progress & history to a '
                                'folder; pair with Syncthing/Dropbox/iCloud',
                      ),
                      value: syncFolder.enabled,
                      onChanged: !supported
                          ? null
                          : (v) async {
                              if (v && syncFolder.folderPath == null) {
                                await _pickSyncFolder();
                              } else {
                                await syncFolder.configure(enabled: v);
                              }
                              if (mounted) setState(() {});
                            },
                    ),
                    if (!supported)
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 16),
                        child: Text(
                          'Folder sync is not available on this platform yet — '
                          'use Export/Import Library above.',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ),
                    if (supported && syncFolder.enabled) ...[
                      ListTile(
                        leading: const Icon(Icons.drive_folder_upload),
                        title: const Text('Change Sync Folder'),
                        subtitle: Text(syncFolder.folderPath ?? 'Not set'),
                        onTap: _pickSyncFolder,
                      ),
                      ListTile(
                        leading: _isFolderSyncing
                            ? const SizedBox(
                                width: 24,
                                height: 24,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.sync_alt),
                        title: const Text('Sync Now'),
                        subtitle: Text(
                          syncFolder.lastRun != null
                              ? 'Last sync: ${_formatDateTime(syncFolder.lastRun!)}'
                              : 'Never synced',
                        ),
                        onTap: _isFolderSyncing ? null : _syncFolderNow,
                      ),
                    ],
                  ],
                );
              },
            ),

            const Divider(),

            // LAN Sync Section (automatic sync between devices on one network)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                'LAN Sync (Same Network)',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey,
                ),
              ),
            ),
            Builder(
              builder: (context) {
                final lanSync = ref.read(lanSyncProvider);
                return Column(
                  children: [
                    SwitchListTile(
                      secondary: const Icon(Icons.wifi_tethering),
                      title: const Text('Sync over local network'),
                      subtitle: Text(
                        lanSync.enabled
                            ? 'Announcing as "${lanSync.deviceName}" — devices '
                                'with the same pairing code merge automatically'
                            : 'Find your other devices on this Wi-Fi and merge '
                                'library, progress & history automatically',
                      ),
                      value: lanSync.enabled,
                      onChanged: (v) async {
                        await lanSync.configure(enabled: v);
                        if (mounted) setState(() {});
                      },
                    ),
                    if (lanSync.enabled) ...[
                      ListTile(
                        leading: const Icon(Icons.badge),
                        title: const Text('Device Name & Pairing Code'),
                        subtitle: Text(
                          lanSync.pairingCode.isEmpty
                              ? '${lanSync.deviceName} · no pairing code'
                              : '${lanSync.deviceName} · code set',
                        ),
                        onTap: _configureLanSync,
                      ),
                      ListTile(
                        leading: const Icon(Icons.sync),
                        title: const Text('Sync Now'),
                        subtitle: Text(
                          lanSync.lastRun != null
                              ? 'Last sync: ${_formatDateTime(lanSync.lastRun!)}'
                                  '${lanSync.lastPeer != null ? ' with ${lanSync.lastPeer}' : ''}'
                              : 'Never synced',
                        ),
                        onTap: _lanSyncNow,
                      ),
                      // Live list of devices announcing on this network —
                      // tap one to sync with it immediately.
                      ValueListenableBuilder<List<LanPeer>>(
                        valueListenable: lanSync.peers,
                        builder: (context, peerList, _) {
                          if (peerList.isEmpty) {
                            return const Padding(
                              padding: EdgeInsets.symmetric(
                                  horizontal: 72, vertical: 4),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  'No devices found yet — open FicBatch on '
                                  'another device on this Wi-Fi.',
                                  style: TextStyle(
                                      fontSize: 12, color: Colors.grey),
                                ),
                              ),
                            );
                          }
                          return Column(
                            children: [
                              for (final peer in peerList)
                                ListTile(
                                  dense: true,
                                  leading: const Icon(Icons.devices),
                                  title: Text(peer.name),
                                  subtitle: Text(
                                    'Seen ${_formatAgo(peer.lastSeen)}'
                                    '${peer.lastSynced != null ? ' · synced ${_formatAgo(peer.lastSynced!)}' : ' · not synced yet'}',
                                  ),
                                  trailing: const Icon(Icons.sync, size: 18),
                                  onTap: () => _syncWithLanPeer(peer),
                                ),
                            ],
                          );
                        },
                      ),
                    ],
                  ],
                );
              },
            ),

            const Divider(),

            // Reader Settings Section
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                'Reader Settings',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey,
                ),
              ),
            ),
            
            // Reader Mode Setting
            Builder(
              builder: (context) {
                final readerMode = ref.watch(readerModeProvider);
                final readerModeNotifier = ref.read(readerModeProvider.notifier);
                
                return ListTile(
                  leading: const Icon(Icons.chrome_reader_mode),
                  title: const Text('Default Reader Mode'),
                  subtitle: Text(readerMode.label),
                  trailing: PopupMenuButton<ReaderMode>(
                    onSelected: readerModeNotifier.setMode,
                    itemBuilder: (context) => ReaderMode.values
                        .map((m) => PopupMenuItem(
                          value: m, 
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(m.label),
                              Text(
                                m.description,
                                style: const TextStyle(fontSize: 11, color: Colors.grey),
                              ),
                            ],
                          ),
                        ))
                        .toList(),
                  ),
                );
              },
            ),
            
            // Font & Reader Settings
            ListTile(
              leading: const Icon(Icons.text_fields),
              title: const Text('Font & Reader Settings'),
              subtitle: const Text(
                'Default font size, line height, font family, reading theme',
              ),
              onTap: _showReaderSettingsDialog,
            ),

            const Divider(),

            // Help
            ListTile(
              leading: const Icon(Icons.replay),
              title: const Text('Replay Onboarding'),
              subtitle: const Text('Show the welcome guide again'),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (ctx) => OnboardingScreen(
                      onDone: () => Navigator.pop(ctx),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
  
  String _formatDateTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} minutes ago';
    if (diff.inHours < 24) return '${diff.inHours} hours ago';
    if (diff.inDays < 7) return '${diff.inDays} days ago';
    
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
           '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}
