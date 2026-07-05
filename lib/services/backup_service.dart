import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'storage_service.dart';
import 'library_export_service.dart';

/// Rolling library snapshots: the newest [maxBackups] full exports live in a
/// backups folder so a bad merge/import/reset is always one restore away.
///
/// Taken automatically before every replace-mode import and app reset, and
/// (throttled to one per 6h) before sync merges; restorable from Settings.
class BackupService {
  BackupService(this._storage);

  final StorageService _storage;

  static const int maxBackups = 5;
  static const Duration autoBackupThrottle = Duration(hours: 6);
  static const String _lastAutoKey = 'last_auto_backup';

  Future<Directory> backupsDir() async {
    final appDir = await getApplicationDocumentsDirectory();
    final dir = Directory('${appDir.path}/FicBatch/backups');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Write a snapshot named after the moment and reason, then prune to the
  /// newest [maxBackups]. Returns the file path, or null on failure (backups
  /// must never block the operation they protect).
  Future<String?> createBackup(String reason) async {
    try {
      final dir = await backupsDir();
      final stamp = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .split('.')
          .first;
      final file = File('${dir.path}/ficbatch_backup_${stamp}_$reason.json');
      await file.writeAsString(
          await LibraryExportService(_storage).exportToJson());
      await _prune(dir);
      debugPrint('[Backup] Wrote ${file.path}');
      return file.path;
    } catch (e) {
      debugPrint('[Backup] Failed ($reason): $e');
      return null;
    }
  }

  /// Auto-backup hook for imports. Replace-mode always backs up; merges are
  /// throttled so hourly syncs don't churn all five slots in an afternoon.
  Future<void> autoBackupBeforeImport(ImportMode mode) async {
    if (mode == ImportMode.merge) {
      final raw = _storage.settingsBox.get(_lastAutoKey);
      final last = raw == null ? null : DateTime.tryParse(raw.toString());
      if (last != null &&
          DateTime.now().difference(last) < autoBackupThrottle) {
        return;
      }
    }
    final path = await createBackup(
        mode == ImportMode.replace ? 'before-replace' : 'auto');
    if (path != null) {
      await _storage.settingsBox
          .put(_lastAutoKey, DateTime.now().toIso8601String());
    }
  }

  /// Newest first.
  Future<List<File>> listBackups() async {
    try {
      final dir = await backupsDir();
      final files = <File>[];
      await for (final entity in dir.list()) {
        if (entity is File && entity.path.endsWith('.json')) {
          files.add(entity);
        }
      }
      files.sort((a, b) => b.path.compareTo(a.path)); // stamped names sort
      return files;
    } catch (e) {
      debugPrint('[Backup] Listing failed: $e');
      return const [];
    }
  }

  /// Replace the library with a backup's contents. A fresh 'before-replace'
  /// backup of the current state is taken first (via the import hook), so a
  /// restore is itself undoable.
  Future<ImportResult> restore(File backup) async {
    final content = await backup.readAsString();
    return LibraryExportService(_storage)
        .importFromJson(content, mode: ImportMode.replace);
  }

  Future<void> _prune(Directory dir) async {
    final files = await listBackups();
    for (final f in files.skip(maxBackups)) {
      try {
        await f.delete();
      } catch (e) {
        debugPrint('[Backup] Prune failed for ${f.path}: $e');
      }
    }
  }
}
