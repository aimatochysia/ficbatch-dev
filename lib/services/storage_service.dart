import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/work.dart';
import '../models/reading_progress.dart';
import 'package:shared_preferences/shared_preferences.dart';

class StorageService {
  static SharedPreferences? _prefs;
  static const String worksBoxName = 'works_box';
  static const String settingsBoxName = 'settings_box';
  static bool _initialized = false;
  static const String _categoriesListKey = 'categories_list';
  static const String _categoryMapKey = 'categories_map';

  Future<void> init() async {
    if (_initialized) return;

    try {
      _prefs ??= await SharedPreferences.getInstance();

      await Hive.initFlutter();

      if (!Hive.isAdapterRegistered(0))
        Hive.registerAdapter(ReadingProgressAdapter());
      if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(WorkAdapter());

      await Hive.openBox<Work>(worksBoxName);
      await Hive.openBox(settingsBoxName);

      await migrateHive();

      _initialized = true;
    } catch (e, stackTrace) {
      debugPrint('StorageService.init error: $e');
      debugPrint('Stack trace: $stackTrace');
      // Mark as initialized even on error to prevent infinite retry loops
      _initialized = true;
      rethrow;
    }
  }

  Box<Work> get worksBox => Hive.box<Work>(worksBoxName);
  Box<dynamic> get settingsBox => Hive.box(settingsBoxName);

  List<Work> getAllWorks() => worksBox.values.toList();
  Future<void> saveWork(Work work) async {
    await worksBox.put(work.id, work);
    await assignDefaultCategoryIfNeeded(work.id);
  }
  Work? getWork(String id) => worksBox.get(id);
  Future<void> deleteWork(String id) async => await worksBox.delete(id);
  Future<void> clearAll() async => await worksBox.clear();

  // Library export/import lives in LibraryExportService (the versioned format
  // that also captures categories, mappings and auto-download flags). The older
  // StorageService JSON/OPDS exporters were removed to avoid two divergent
  // export paths.

  Future<void> saveAdvancedFilters(Map<String, dynamic> filters) async {
    await settingsBox.put('last_advanced_filters', filters);
  }

  Future<Map<String, dynamic>> getAdvancedFilters() async {
    final data = settingsBox.get('last_advanced_filters');
    return data != null ? Map<String, dynamic>.from(data) : {};
  }

  Future<void> saveSearch(
    String name,
    String url,
    Map<String, dynamic> filters,
  ) async {
    final searches = await getSavedSearches();
    searches.removeWhere((s) => s['name'] == name);
    searches.add({'name': name, 'url': url, 'filters': filters});
    await settingsBox.put('saved_searches', searches);
  }

  Future<List<Map<String, dynamic>>> getSavedSearches() async {
    final saved = settingsBox.get('saved_searches');
    if (saved == null) return [];
    return (saved as List).map((e) => Map<String, dynamic>.from(e)).toList();
  }

  Future<void> deleteSavedSearch(String name) async {
    final searches = await getSavedSearches();
    searches.removeWhere((s) => s['name'] == name);
    await settingsBox.put('saved_searches', searches);
  }

  Future<List<String>> getCategories() async {
    final raw = settingsBox.get(_categoriesListKey);
    if (raw == null) return <String>[];
    return List<String>.from(raw);
  }

  Future<void> addCategory(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    final cats = await getCategories();
    if (!cats.contains(trimmed)) {
      cats.add(trimmed);
      await settingsBox.put(_categoriesListKey, cats);
      final map = await _getCategoryMap();
      map.putIfAbsent(trimmed, () => <String>[]);
      await _saveCategoryMap(map);
    }
  }

  Future<void> renameCategory(String oldName, String newName) async {
    final oldTrim = oldName.trim();
    final newTrim = newName.trim();
    if (oldTrim.isEmpty || newTrim.isEmpty || oldTrim == newTrim) return;
    final cats = await getCategories();
    final idx = cats.indexOf(oldTrim);
    if (idx < 0) return;
    if (!cats.contains(newTrim)) {
      cats[idx] = newTrim;
    } else {
      cats.removeAt(idx);
    }
    await settingsBox.put(_categoriesListKey, cats);

    final map = await _getCategoryMap();
    final works = map.remove(oldTrim) ?? <String>[];
    final target = map.putIfAbsent(newTrim, () => <String>[]);
    for (final id in works) {
      if (!target.contains(id)) target.add(id);
    }
    await _saveCategoryMap(map);
  }

  Future<void> deleteCategory(String name) async {
    final cats = await getCategories();
    cats.remove(name);
    await settingsBox.put(_categoriesListKey, cats);
    final map = await _getCategoryMap();
    map.remove(name);
    await _saveCategoryMap(map);
  }

  Future<Set<String>> getCategoriesForWork(String workId) async {
    final map = await _getCategoryMap();
    final result = <String>{};
    map.forEach((cat, ids) {
      if (ids.contains(workId)) result.add(cat);
    });
    return result;
  }

  Future<void> setCategoriesForWork(String workId, Set<String> categories) async {
    final cats = await getCategories();
    final map = await _getCategoryMap();

    for (final c in categories) {
      if (!cats.contains(c)) cats.add(c);
      map.putIfAbsent(c, () => <String>[]);
    }
    await settingsBox.put(_categoriesListKey, cats);

    for (final entry in map.entries) {
      entry.value.removeWhere((id) => id == workId);
    }

    // Removing a work from its last category leaves it in the library as an
    // uncategorized work (it shows under "All"); it is no longer silently
    // deleted. Use deleteWork() explicitly to remove a work entirely.
    if (categories.isEmpty) {
      await _saveCategoryMap(map);
      return;
    }

    for (final c in categories) {
      final list = map[c]!;
      if (!list.contains(workId)) list.add(workId);
    }

    await _saveCategoryMap(map);
  }

  Future<void> assignDefaultCategoryIfNeeded(String workId) async {
    final cats = await getCategories();
    if (cats.isEmpty) {
      cats.add('default');
      await settingsBox.put(_categoriesListKey, cats);
      final map = await _getCategoryMap();
      final list = map.putIfAbsent('default', () => <String>[]);
      if (!list.contains(workId)) list.add(workId);
      await _saveCategoryMap(map);
    }
  }

  Future<Map<String, List<String>>> _getCategoryMap() async {
    final raw = settingsBox.get(_categoryMapKey);
    if (raw == null) return <String, List<String>>{};
    final casted = Map<String, dynamic>.from(raw);
    return casted.map((k, v) => MapEntry(k, List<String>.from(v)));
  }

  Future<void> _saveCategoryMap(Map<String, List<String>> map) async {
    await settingsBox.put(_categoryMapKey, map);
  }

  Future<Set<String>> getWorkIdsForCategory(String category) async {
    final map = await _getCategoryMap();
    final list = map[category] ?? const <String>[];
    return Set<String>.from(list);
  }

  // History management methods
  
  /// Maximum number of history entries to retain.
  static const int historyCap = 500;

  /// Add or update a single history entry for a work. This is the one and only
  /// history writer — both the library/browse open paths and the reader funnel
  /// through here so the schema and cap stay consistent.
  ///
  /// If the same work was accessed earlier the same day, the prior entry is
  /// replaced and moved to the top. Optional reading-position fields
  /// (chapter index/name, scroll position) are recorded when available so the
  /// History tab can show where the reader left off.
  Future<void> addToHistory({
    required String workId,
    required String title,
    required String author,
    int? chapterIndex,
    String? chapterName,
    double? scrollPosition,
  }) async {
    final historyList = await getHistory();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    // Remove any earlier entry for this work from today; we re-add at the top.
    historyList.removeWhere((entry) {
      if (entry['workId'] != workId) return false;
      final accessedAt = entry['accessedAt'];
      if (accessedAt == null) return false;
      final parsed = DateTime.tryParse(accessedAt.toString());
      if (parsed == null) return false;
      final entryDay = DateTime(parsed.year, parsed.month, parsed.day);
      return entryDay == today;
    });

    historyList.insert(0, {
      'workId': workId,
      'title': title,
      'author': author,
      'accessedAt': now.toIso8601String(),
      if (chapterIndex != null) 'chapterIndex': chapterIndex,
      if (chapterName != null) 'chapterName': chapterName,
      if (scrollPosition != null) 'scrollPosition': scrollPosition,
    });

    if (historyList.length > historyCap) {
      historyList.removeRange(historyCap, historyList.length);
    }

    await settingsBox.put('history', historyList);
  }
  
  /// Get all history entries
  Future<List<Map<String, dynamic>>> getHistory() async {
    final raw = settingsBox.get('history') as List?;
    if (raw == null) return [];
    return raw.map((e) => Map<String, dynamic>.from(e)).toList();
  }
  
  /// Clear all history
  Future<void> clearHistory() async {
    await settingsBox.delete('history');
  }
}

Future<void> migrateHive() async {
  try {
    // Check if box is open before accessing
    if (!Hive.isBoxOpen(StorageService.worksBoxName)) {
      debugPrint('[migrateHive] Box is not open, skipping migration');
      return;
    }
    
    // Access without type parameter to get Box<dynamic> from the already-opened Box<Work>
    final Box<dynamic> box = Hive.box(StorageService.worksBoxName);
    final keys = box.keys.toList();

  for (final key in keys) {
    final raw = box.get(key);
    if (raw == null) continue;

    if (raw is Map) {
      final map = Map<String, dynamic>.from(raw);
      map.putIfAbsent(
        'readingProgress',
        () => {
          'chapterIndex': 0,
          'chapterAnchor': '',
          'scrollPosition': 0.0,
          'lastReadAt': DateTime.now().toIso8601String(),
        },
      );

      try {
        final normalized = Work.fromJson(map);
        await box.put(key, normalized);
      } catch (e) {
        debugPrint('Migration failed for $key: $e');
      }
    } else if (raw is Work) {
      continue;
    } else {
      debugPrint('Unexpected data type for key $key: ${raw.runtimeType}');
    }
  }
  } catch (e, stackTrace) {
    debugPrint('[migrateHive] Error during migration: $e');
    debugPrint('Stack trace: $stackTrace');
    // Don't rethrow - migration failures shouldn't prevent app startup
  }
}
