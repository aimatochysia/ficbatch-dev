import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/storage_service.dart';
import '../services/sync_folder_service.dart';
import '../services/lan_sync_service.dart';
import '../models/work.dart';

final storageProvider = Provider<StorageService>((ref) {
  throw UnimplementedError('StorageService not initialized');
});

/// Overridden in main.dart with the app-lifetime SyncFolderService.
final syncFolderProvider = Provider<SyncFolderService>((ref) {
  throw UnimplementedError('SyncFolderService not initialized');
});

/// Overridden in main.dart with the app-lifetime LanSyncService.
final lanSyncProvider = Provider<LanSyncService>((ref) {
  throw UnimplementedError('LanSyncService not initialized');
});

final workListProvider = StreamProvider<List<Work>>((ref) async* {
  final storage = ref.watch(storageProvider);
  final box = storage.worksBox;

  yield box.values.toList();

  await for (final _ in box.watch()) {
    yield box.values.toList();
  }
});

final categoriesProvider = StreamProvider<List<String>>((ref) async* {
  final storage = ref.watch(storageProvider);
  yield await storage.getCategories();
  await for (final e in storage.settingsBox.watch()) {
    if (e.key == 'categories_list' || e.key == 'categories_map') {
      yield await storage.getCategories();
    }
  }
});

final categoryWorksProvider = StreamProvider.family<Set<String>, String>((ref, category) async* {
  final storage = ref.watch(storageProvider);
  yield await storage.getWorkIdsForCategory(category);
  await for (final e in storage.settingsBox.watch()) {
    if (e.key == 'categories_map' || e.key == 'categories_list') {
      yield await storage.getWorkIdsForCategory(category);
    }
  }
});
