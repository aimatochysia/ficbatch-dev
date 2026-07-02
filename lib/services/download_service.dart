import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'storage_service.dart';

/// Outcome of a single work download: a file [path] on success, otherwise a
/// human-readable [error].
class DownloadResult {
  final String? path;
  final String? error;

  const DownloadResult.success(this.path) : error = null;
  const DownloadResult.failure(this.error) : path = null;

  bool get isSuccess => path != null;
}

/// Service for downloading works from AO3
class DownloadService {
  static const String _ao3DownloadBaseUrl = 'https://archiveofourown.org/downloads';

  /// User-picked download folder (desktop only). When null, downloads go to the
  /// app documents directory. Set once at startup from the stored setting and
  /// whenever the folder is re-picked.
  static String? _customDirPath;

  static bool get _isDesktop =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  /// Configure the desktop download folder. Pass null/empty to fall back to the
  /// app documents directory. Has no effect on mobile, where the sandboxed app
  /// documents directory is always used (keeps offline works portable).
  static void configureDirectory(String? path) {
    _customDirPath = (path != null && path.trim().isNotEmpty) ? path.trim() : null;
  }

  /// The currently configured custom folder, or null when using the default.
  static String? get customDirPath => _isDesktop ? _customDirPath : null;

  /// Get the downloads directory path
  static Future<Directory> getDownloadsDirectory() async {
    // Desktop honors a user-picked folder; works are stored as {dir}/{id}.html
    // so the folder is portable across devices/platforms.
    if (_isDesktop && _customDirPath != null) {
      final dir = Directory(_customDirPath!);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      return dir;
    }
    final appDir = await getApplicationDocumentsDirectory();
    final downloadsDir = Directory('${appDir.path}/FicBatch/downloads');
    if (!await downloadsDir.exists()) {
      await downloadsDir.create(recursive: true);
    }
    return downloadsDir;
  }

  /// Copy existing downloaded works (*.html) from [from] into the current
  /// downloads directory. Returns the number of files migrated.
  static Future<int> migrateDownloadsFrom(Directory from) async {
    if (!await from.exists()) return 0;
    final to = await getDownloadsDirectory();
    if (from.path == to.path) return 0;
    int migrated = 0;
    await for (final entity in from.list()) {
      if (entity is File && entity.path.endsWith('.html')) {
        final name = entity.uri.pathSegments.last;
        try {
          await entity.copy('${to.path}/$name');
          migrated++;
        } catch (e) {
          debugPrint('[DownloadService] Migrate failed for $name: $e');
        }
      }
    }
    return migrated;
  }
  
  /// Get the path for a specific work's downloaded file
  static Future<String> getWorkDownloadPath(String workId) async {
    final downloadsDir = await getDownloadsDirectory();
    return '${downloadsDir.path}/$workId.html';
  }
  
  /// Check if a work is downloaded
  static Future<bool> isWorkDownloaded(String workId) async {
    final path = await getWorkDownloadPath(workId);
    return File(path).exists();
  }
  
  /// Download a single work from AO3.
  ///
  /// Returns a [DownloadResult]: `path` on success, otherwise a
  /// human-readable `error` explaining exactly why (HTTP status, rate limit,
  /// restricted work, network error) so failures are diagnosable from the UI
  /// instead of a generic "failed".
  static Future<DownloadResult> downloadWork(String workId) async {
    try {
      // AO3 download URL format: /downloads/{workId}/{filename}.html — the
      // filename segment is arbitrary; AO3 serves by id (and may redirect to
      // download.archiveofourown.org, which http follows automatically).
      final url = '$_ao3DownloadBaseUrl/$workId/$workId.html';
      debugPrint('[DownloadService] Downloading work $workId from $url');

      final response = await http.get(
        Uri.parse(url),
        headers: const {
          'User-Agent':
              'Mozilla/5.0 (compatible; FicBatch/1.2; +https://github.com/aimatochysia/FicBatch)',
          'Accept':
              'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
          'Accept-Language': 'en-US,en;q=0.9',
        },
      ).timeout(const Duration(seconds: 60));

      if (response.statusCode == 429) {
        final retryAfter = response.headers['retry-after'];
        return DownloadResult.failure(
            'AO3 rate limit (HTTP 429) — wait ${retryAfter ?? 'a minute'}'
            '${retryAfter != null ? 's' : ''} and try again');
      }
      if (response.statusCode == 404) {
        return DownloadResult.failure(
            'Work not found (HTTP 404) — it may be deleted or hidden');
      }
      if (response.statusCode != 200) {
        debugPrint(
            '[DownloadService] Failed to download work $workId: HTTP ${response.statusCode}');
        return DownloadResult.failure('HTTP ${response.statusCode} from AO3');
      }

      final body = response.body;
      // A 200 can still be a "wrong" page: restricted works bounce to the
      // login form, and WAF challenges return small HTML pages.
      if (body.contains('id="new_user_session"') ||
          body.contains('only available to registered users')) {
        return DownloadResult.failure(
            'This work is restricted to logged-in users and cannot be downloaded');
      }
      if (body.length < 2048 && body.toLowerCase().contains('cloudflare')) {
        return DownloadResult.failure(
            'Blocked by AO3\'s protection layer — try again later');
      }

      final filePath = await getWorkDownloadPath(workId);
      final file = File(filePath);
      await file.writeAsBytes(response.bodyBytes);

      debugPrint('[DownloadService] Successfully downloaded work $workId to $filePath');
      return DownloadResult.success(filePath);
    } on SocketException catch (e) {
      return DownloadResult.failure('Network error: ${e.message}');
    } on TimeoutException {
      return DownloadResult.failure('Timed out after 60s');
    } on FileSystemException catch (e) {
      return DownloadResult.failure(
          'Could not write file: ${e.message} (${e.path ?? 'download folder'})');
    } catch (e) {
      debugPrint('[DownloadService] Error downloading work $workId: $e');
      return DownloadResult.failure(e.toString());
    }
  }
  
  /// Download multiple works with throttling
  /// Returns a map of workId -> success/failure
  static Future<Map<String, bool>> downloadWorks(
    List<String> workIds, {
    Duration throttleDelay = const Duration(milliseconds: 1000),
    void Function(int completed, int total)? onProgress,
  }) async {
    final results = <String, bool>{};

    for (int i = 0; i < workIds.length; i++) {
      final workId = workIds[i];
      final result = await downloadWork(workId);
      results[workId] = result.isSuccess;

      onProgress?.call(i + 1, workIds.length);

      // Throttle to avoid overwhelming AO3
      if (i < workIds.length - 1) {
        await Future.delayed(throttleDelay);
      }
    }

    return results;
  }
  
  /// Delete a downloaded work
  static Future<bool> deleteDownload(String workId) async {
    try {
      final path = await getWorkDownloadPath(workId);
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
        debugPrint('[DownloadService] Deleted download for work $workId');
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('[DownloadService] Error deleting download for work $workId: $e');
      return false;
    }
  }
  
  /// Get the content of a downloaded work
  static Future<String?> getDownloadedContent(String workId) async {
    try {
      final path = await getWorkDownloadPath(workId);
      final file = File(path);
      if (await file.exists()) {
        return await file.readAsString();
      }
      return null;
    } catch (e) {
      debugPrint('[DownloadService] Error reading download for work $workId: $e');
      return null;
    }
  }
  
  /// Get download file info (size, date)
  static Future<Map<String, dynamic>?> getDownloadInfo(String workId) async {
    try {
      final path = await getWorkDownloadPath(workId);
      final file = File(path);
      if (await file.exists()) {
        final stat = await file.stat();
        return {
          'path': path,
          'size': stat.size,
          'modified': stat.modified,
        };
      }
      return null;
    } catch (e) {
      debugPrint('[DownloadService] Error getting download info for work $workId: $e');
      return null;
    }
  }
  
  /// Clear all downloads
  static Future<int> clearAllDownloads() async {
    try {
      final dir = await getDownloadsDirectory();
      if (!await dir.exists()) return 0;
      
      int count = 0;
      await for (final entity in dir.list()) {
        if (entity is File && entity.path.endsWith('.html')) {
          await entity.delete();
          count++;
        }
      }
      
      debugPrint('[DownloadService] Cleared $count downloads');
      return count;
    } catch (e) {
      debugPrint('[DownloadService] Error clearing downloads: $e');
      return 0;
    }
  }
  
  /// Get total download storage usage
  static Future<int> getStorageUsage() async {
    try {
      final dir = await getDownloadsDirectory();
      if (!await dir.exists()) return 0;
      
      int totalSize = 0;
      await for (final entity in dir.list()) {
        if (entity is File) {
          final stat = await entity.stat();
          totalSize += stat.size;
        }
      }
      
      return totalSize;
    } catch (e) {
      debugPrint('[DownloadService] Error calculating storage usage: $e');
      return 0;
    }
  }
  
  /// Update work's download status in storage
  static Future<void> updateWorkDownloadStatus(
    StorageService storage,
    String workId,
    bool isDownloaded,
  ) async {
    final work = storage.getWork(workId);
    if (work != null) {
      final updatedWork = work.copyWith(
        isDownloaded: isDownloaded,
      );
      await storage.saveWork(updatedWork);
    }
  }
}

/// Model for tracking download progress
class DownloadProgress {
  final String workId;
  final String workTitle;
  final DownloadStatus status;
  final String? errorMessage;
  final DateTime startedAt;
  final DateTime? completedAt;
  
  DownloadProgress({
    required this.workId,
    required this.workTitle,
    required this.status,
    this.errorMessage,
    required this.startedAt,
    this.completedAt,
  });
  
  DownloadProgress copyWith({
    DownloadStatus? status,
    String? errorMessage,
    DateTime? completedAt,
  }) => DownloadProgress(
    workId: workId,
    workTitle: workTitle,
    status: status ?? this.status,
    errorMessage: errorMessage ?? this.errorMessage,
    startedAt: startedAt,
    completedAt: completedAt ?? this.completedAt,
  );
}

enum DownloadStatus {
  pending,
  downloading,
  completed,
  failed,
}
