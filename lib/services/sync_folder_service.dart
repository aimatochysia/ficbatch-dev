import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'storage_service.dart';
import 'library_export_service.dart';

/// Cross-device sync via a shared folder (see docs/research/pears_p2p_sync.md).
///
/// When enabled, the library (works + progress), categories and reading
/// history are auto-exported — debounced — to `ficbatch_sync.json` inside a
/// user-chosen folder whenever they change, and merge-imported from that file
/// on startup. Point Syncthing / Dropbox / iCloud Drive at the folder and
/// every device converges. The file's `exportedAt` stamp is remembered so we
/// never re-import our own export (no echo loops).
class SyncFolderService {
  SyncFolderService(this._storage);

  final StorageService _storage;

  static const String syncFileName = 'ficbatch_sync.json';
  static const String _enabledKey = 'sync_folder_enabled';
  static const String _pathKey = 'sync_folder_path';
  static const String _stampKey = 'sync_folder_last_stamp';
  static const String _lastRunKey = 'sync_folder_last_run';
  static const Duration _debounceDelay = Duration(seconds: 5);

  Timer? _debounce;
  Timer? _periodic;
  StreamSubscription? _worksSub;
  StreamSubscription? _settingsSub;
  bool _suppressExport = false;

  /// Periodic full sync (import-if-changed + export) while the app runs.
  /// Hourly per user request — a temporary debugging cadence until the
  /// sync-folder mode has been validated across devices.
  static const Duration periodicInterval = Duration(hours: 1);

  bool get enabled =>
      _storage.settingsBox.get(_enabledKey, defaultValue: false) == true;

  String? get folderPath => _storage.settingsBox.get(_pathKey) as String?;

  DateTime? get lastRun {
    final raw = _storage.settingsBox.get(_lastRunKey);
    return raw == null ? null : DateTime.tryParse(raw.toString());
  }

  File? get _syncFile {
    final path = folderPath;
    if (path == null || path.trim().isEmpty) return null;
    return File('$path${Platform.pathSeparator}$syncFileName');
  }

  /// Persist configuration and (re)start watching. Pass enabled=false to stop.
  Future<void> configure({required bool enabled, String? path}) async {
    await _storage.settingsBox.put(_enabledKey, enabled);
    if (path != null) await _storage.settingsBox.put(_pathKey, path);
    if (enabled) {
      await start();
    } else {
      stop();
    }
  }

  /// Import (if the file changed since we last saw it), then begin watching
  /// local changes for debounced auto-export. Safe to call repeatedly.
  Future<void> start() async {
    stop();
    if (!enabled || _syncFile == null) return;

    try {
      await importIfChanged();
    } catch (e) {
      debugPrint('[SyncFolder] Startup import failed: $e');
    }

    _worksSub = _storage.worksBox.watch().listen((_) => _scheduleExport());
    const watchedKeys = {
      'categories_list',
      'categories_map',
      'history',
      'auto_download_categories',
      'default_category',
    };
    _settingsSub = _storage.settingsBox.watch().listen((event) {
      if (watchedKeys.contains(event.key)) _scheduleExport();
    });
    _periodic = Timer.periodic(periodicInterval, (_) {
      syncNow().catchError((e) {
        debugPrint('[SyncFolder] Periodic sync failed: $e');
        return null;
      });
    });
    debugPrint('[SyncFolder] Watching for changes → ${_syncFile!.path}');
  }

  void stop() {
    _debounce?.cancel();
    _debounce = null;
    _periodic?.cancel();
    _periodic = null;
    _worksSub?.cancel();
    _worksSub = null;
    _settingsSub?.cancel();
    _settingsSub = null;
  }

  void _scheduleExport() {
    if (_suppressExport) return;
    _debounce?.cancel();
    _debounce = Timer(_debounceDelay, () {
      exportNow().catchError((e) {
        debugPrint('[SyncFolder] Auto-export failed: $e');
      });
    });
  }

  /// Write the current library/history to the sync file and remember its
  /// stamp so we skip re-importing our own write.
  Future<void> exportNow() async {
    final file = _syncFile;
    if (file == null) return;
    final json = await LibraryExportService(_storage).exportToJson();
    final stamp = _readStamp(json);
    await file.parent.create(recursive: true);
    await file.writeAsString(json);
    await _storage.settingsBox.put(_stampKey, stamp);
    await _storage.settingsBox
        .put(_lastRunKey, DateTime.now().toIso8601String());
    debugPrint('[SyncFolder] Exported library ($stamp)');
  }

  /// Merge-import the sync file when its stamp differs from the last one we
  /// wrote or imported. Returns the import summary, or null when skipped.
  Future<ImportResult?> importIfChanged() async {
    final file = _syncFile;
    if (file == null || !await file.exists()) return null;

    final content = await file.readAsString();
    final stamp = _readStamp(content);
    final lastStamp = _storage.settingsBox.get(_stampKey)?.toString();
    if (stamp != null && stamp == lastStamp) {
      debugPrint('[SyncFolder] Sync file unchanged ($stamp), skipping import');
      return null;
    }

    _suppressExport = true;
    try {
      final result = await LibraryExportService(_storage)
          .importFromJson(content, mode: ImportMode.merge);
      await _storage.settingsBox.put(_stampKey, stamp);
      await _storage.settingsBox
          .put(_lastRunKey, DateTime.now().toIso8601String());
      debugPrint('[SyncFolder] Imported: ${result.toSummary()}');
      return result;
    } finally {
      _suppressExport = false;
      // Propagate local-only data back out (merged state may exceed the file).
      _scheduleExport();
    }
  }

  /// Manual "sync now": import remote changes, then export the merged state.
  Future<ImportResult?> syncNow() async {
    final result = await importIfChanged();
    _debounce?.cancel();
    await exportNow();
    return result;
  }

  /// Extract the `exportedAt` stamp from an export JSON string.
  String? _readStamp(String json) {
    try {
      final data = jsonDecode(json);
      if (data is Map) return data['exportedAt']?.toString();
    } catch (_) {}
    return null;
  }
}
