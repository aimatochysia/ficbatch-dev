import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:workmanager/workmanager.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import '../models/work.dart';
import '../models/reading_progress.dart';
import 'ao3_service.dart';
import 'storage_service.dart';

/// Sync intervals in hours
enum SyncInterval {
  hours12(12, 'Every 12 hours'),
  daily(24, 'Daily'),
  days3(72, 'Every 3 days'),
  weekly(168, 'Weekly');

  final int hours;
  final String label;
  const SyncInterval(this.hours, this.label);
}

/// Network preference for sync
enum SyncNetworkPreference {
  wifiOnly('Wi-Fi only'),
  wifiAndMobile('Wi-Fi and Mobile data');

  final String label;
  const SyncNetworkPreference(this.label);
}

/// Model for work update entries shown in Updates tab
class WorkUpdate {
  final String workId;
  final String workTitle;
  final DateTime detectedAt;
  final DateTime? oldUpdatedAt;
  final DateTime? newUpdatedAt;
  final bool isRead;

  WorkUpdate({
    required this.workId,
    required this.workTitle,
    required this.detectedAt,
    this.oldUpdatedAt,
    this.newUpdatedAt,
    this.isRead = false,
  });

  Map<String, dynamic> toJson() => {
    'workId': workId,
    'workTitle': workTitle,
    'detectedAt': detectedAt.toIso8601String(),
    'oldUpdatedAt': oldUpdatedAt?.toIso8601String(),
    'newUpdatedAt': newUpdatedAt?.toIso8601String(),
    'isRead': isRead,
  };

  factory WorkUpdate.fromJson(Map<String, dynamic> json) => WorkUpdate(
    workId: json['workId'] ?? '',
    workTitle: json['workTitle'] ?? '',
    detectedAt: DateTime.tryParse(json['detectedAt'] ?? '') ?? DateTime.now(),
    oldUpdatedAt: json['oldUpdatedAt'] != null 
        ? DateTime.tryParse(json['oldUpdatedAt']) 
        : null,
    newUpdatedAt: json['newUpdatedAt'] != null 
        ? DateTime.tryParse(json['newUpdatedAt']) 
        : null,
    isRead: json['isRead'] ?? false,
  );

  WorkUpdate copyWith({bool? isRead}) => WorkUpdate(
    workId: workId,
    workTitle: workTitle,
    detectedAt: detectedAt,
    oldUpdatedAt: oldUpdatedAt,
    newUpdatedAt: newUpdatedAt,
    isRead: isRead ?? this.isRead,
  );
}

/// Background sync task name
const String syncTaskName = 'ao3_sync_task';
const String syncTaskTag = 'ao3_background_sync';

/// Callback dispatcher for background tasks (must be top-level function)
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      debugPrint('[SyncService] Background task started: $task');
      
      // Initialize Hive for background isolate
      await Hive.initFlutter();
      if (!Hive.isAdapterRegistered(0)) {
        Hive.registerAdapter(ReadingProgressAdapter());
      }
      if (!Hive.isAdapterRegistered(1)) {
        Hive.registerAdapter(WorkAdapter());
      }
      
      await Hive.openBox<Work>(StorageService.worksBoxName);
      await Hive.openBox(StorageService.settingsBoxName);
      
      final syncService = SyncService();
      await syncService.performSync();
      
      return true;
    } catch (e) {
      debugPrint('[SyncService] Background task error: $e');
      return false;
    }
  });
}

class SyncService {
  static final FlutterLocalNotificationsPlugin _notifications = 
      FlutterLocalNotificationsPlugin();
  static bool _notificationsInitialized = false;

  /// Initialize notifications
  static Future<void> initializeNotifications() async {
    if (_notificationsInitialized) return;
    
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    
    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );
    
    await _notifications.initialize(initSettings);
    _notificationsInitialized = true;
  }

  /// Ensure the OS notification permission is granted. On Android 13+ this must
  /// be requested at runtime from a UI context (call when enabling auto-sync or
  /// on a manual sync); iOS is handled by the notifications plugin at init.
  /// Returns true if notifications are permitted (or not applicable).
  static Future<bool> ensureNotificationPermission() async {
    if (!Platform.isAndroid) return true;
    try {
      final status = await Permission.notification.status;
      if (status.isGranted) return true;
      final result = await Permission.notification.request();
      return result.isGranted;
    } catch (e) {
      debugPrint('[SyncService] Notification permission request failed: $e');
      return false;
    }
  }

  /// Initialize background sync
  static Future<void> initializeBackgroundSync() async {
    // Skip on Windows - use in-app sync instead
    if (Platform.isWindows) {
      debugPrint('[SyncService] Windows detected, skipping Workmanager init');
      return;
    }
    
    await Workmanager().initialize(callbackDispatcher);
  }

  /// Schedule periodic background sync
  static Future<void> scheduleSync({
    required SyncInterval interval,
    required SyncNetworkPreference networkPreference,
  }) async {
    // Skip on Windows
    if (Platform.isWindows) {
      debugPrint('[SyncService] Windows detected, skipping background sync scheduling');
      return;
    }
    
    // Cancel any existing tasks
    await Workmanager().cancelByTag(syncTaskTag);
    
    // Register new periodic task
    await Workmanager().registerPeriodicTask(
      syncTaskName,
      syncTaskName,
      frequency: Duration(hours: interval.hours),
      tag: syncTaskTag,
      constraints: Constraints(
        networkType: networkPreference == SyncNetworkPreference.wifiOnly
            ? NetworkType.unmetered
            : NetworkType.connected,
        requiresBatteryNotLow: true,
      ),
    );
    
    debugPrint('[SyncService] Scheduled sync every ${interval.hours} hours');
  }

  /// Cancel all scheduled syncs
  static Future<void> cancelSync() async {
    if (Platform.isWindows) return;
    await Workmanager().cancelByTag(syncTaskTag);
    debugPrint('[SyncService] Cancelled all scheduled syncs');
  }

  /// Check if sync is allowed based on network preference
  Future<bool> canSyncWithCurrentNetwork(SyncNetworkPreference preference) async {
    final connectivity = await Connectivity().checkConnectivity();
    
    if (preference == SyncNetworkPreference.wifiOnly) {
      return connectivity.contains(ConnectivityResult.wifi);
    }
    
    return connectivity.contains(ConnectivityResult.wifi) ||
           connectivity.contains(ConnectivityResult.mobile) ||
           connectivity.contains(ConnectivityResult.ethernet);
  }

  /// Perform the actual sync operation
  Future<List<WorkUpdate>> performSync() async {
    final updates = <WorkUpdate>[];
    
    try {
      final worksBox = Hive.box<Work>(StorageService.worksBoxName);
      final settingsBox = Hive.box(StorageService.settingsBoxName);
      final works = worksBox.values.toList();
      
      debugPrint('[SyncService] Starting sync for ${works.length} works');
      
      final ao3 = Ao3Service();
      for (final work in works) {
        try {
          // Single shared parser for both import and sync.
          final meta = await ao3.fetchWorkMetadata(work.id);
          final newUpdatedAt = (meta['updatedAt'] as DateTime?) ??
              (meta['publishedAt'] as DateTime?);
          final oldDate = work.updatedAt;
          final isUpdate = newUpdatedAt != null &&
              (oldDate == null ||
                  _dateOnly(newUpdatedAt).isAfter(_dateOnly(oldDate)));

          // Refresh the metadata baseline from the freshly parsed page so sync
          // fills in fields that may have been missing or have changed.
          final tags = meta['tags'] is List
              ? List<String>.from(meta['tags'] as List)
              : null;
          var refreshed = work.copyWith(
            updatedAt: newUpdatedAt,
            wordsCount: meta['wordsCount'] as int?,
            chaptersCount: meta['chaptersCount'] as int?,
            kudosCount: meta['kudosCount'] as int?,
            hitsCount: meta['hitsCount'] as int?,
            commentsCount: meta['commentsCount'] as int?,
            summary: meta['summary'] as String?,
            tags: (tags != null && tags.isNotEmpty) ? tags : null,
            lastSyncDate: DateTime.now(),
          );

          if (isUpdate) {
            refreshed = refreshed.copyWith(hasUpdate: true);
            updates.add(WorkUpdate(
              workId: work.id,
              workTitle: work.title,
              detectedAt: DateTime.now(),
              oldUpdatedAt: oldDate,
              newUpdatedAt: newUpdatedAt,
            ));
            debugPrint(
                '[SyncService] Update for "${work.title}": $oldDate -> $newUpdatedAt');
          }

          await worksBox.put(work.id, refreshed);
        } catch (e) {
          debugPrint('[SyncService] Error checking work ${work.id}: $e');
        }

        // Small delay to avoid rate limiting.
        await Future.delayed(const Duration(milliseconds: 500));
      }
      
      // Save updates to settings
      if (updates.isNotEmpty) {
        await _saveUpdates(settingsBox, updates);
        await _showUpdateNotification(updates);
      }
      
      // Update last sync time
      await settingsBox.put('last_sync_time', DateTime.now().toIso8601String());
      
      debugPrint('[SyncService] Sync complete. Found ${updates.length} updates');
      
    } catch (e) {
      debugPrint('[SyncService] Sync error: $e');
    }
    
    return updates;
  }


  DateTime _dateOnly(DateTime dt) => DateTime(dt.year, dt.month, dt.day);

  /// Save updates to storage
  Future<void> _saveUpdates(Box settingsBox, List<WorkUpdate> newUpdates) async {
    final existingRaw = settingsBox.get('work_updates') as List?;
    final existing = existingRaw
        ?.map((e) => WorkUpdate.fromJson(Map<String, dynamic>.from(e)))
        .toList() ?? <WorkUpdate>[];
    
    // Add new updates, avoiding duplicates
    for (final update in newUpdates) {
      existing.removeWhere((e) => e.workId == update.workId);
      existing.insert(0, update);
    }
    
    // Keep only last 100 updates
    if (existing.length > 100) {
      existing.removeRange(100, existing.length);
    }
    
    await settingsBox.put(
      'work_updates',
      existing.map((e) => e.toJson()).toList(),
    );
  }

  /// Show notification about updates
  Future<void> _showUpdateNotification(List<WorkUpdate> updates) async {
    if (updates.isEmpty) return;
    
    await initializeNotifications();
    
    const androidDetails = AndroidNotificationDetails(
      'ao3_updates',
      'Work Updates',
      channelDescription: 'Notifications for AO3 work updates',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
    );
    
    const iosDetails = DarwinNotificationDetails();
    
    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );
    
    final title = updates.length == 1
        ? 'Work Updated: ${updates.first.workTitle}'
        : '${updates.length} Works Updated';
    
    final body = updates.length == 1
        ? 'Tap to view updates'
        : updates.take(3).map((u) => u.workTitle).join(', ') +
          (updates.length > 3 ? '...' : '');
    
    await _notifications.show(0, title, body, details);
  }

  /// Get all saved updates
  static Future<List<WorkUpdate>> getUpdates() async {
    try {
      final settingsBox = Hive.box(StorageService.settingsBoxName);
      final raw = settingsBox.get('work_updates') as List?;
      if (raw == null) return [];
      
      return raw
          .map((e) => WorkUpdate.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (e) {
      debugPrint('[SyncService] Error getting updates: $e');
      return [];
    }
  }

  /// Mark an update as read
  static Future<void> markUpdateAsRead(String workId) async {
    try {
      final settingsBox = Hive.box(StorageService.settingsBoxName);
      final updates = await getUpdates();
      
      final updatedList = updates.map((u) {
        if (u.workId == workId) {
          return u.copyWith(isRead: true);
        }
        return u;
      }).toList();
      
      await settingsBox.put(
        'work_updates',
        updatedList.map((e) => e.toJson()).toList(),
      );
      
      // Also clear hasUpdate flag on the work
      final worksBox = Hive.box<Work>(StorageService.worksBoxName);
      final work = worksBox.get(workId);
      if (work != null) {
        await worksBox.put(workId, work.copyWith(hasUpdate: false));
      }
    } catch (e) {
      debugPrint('[SyncService] Error marking update as read: $e');
    }
  }

  /// Clear all updates
  static Future<void> clearAllUpdates() async {
    try {
      final settingsBox = Hive.box(StorageService.settingsBoxName);
      await settingsBox.delete('work_updates');
    } catch (e) {
      debugPrint('[SyncService] Error clearing updates: $e');
    }
  }

  /// Get unread update count
  static Future<int> getUnreadCount() async {
    final updates = await getUpdates();
    return updates.where((u) => !u.isRead).length;
  }
}
