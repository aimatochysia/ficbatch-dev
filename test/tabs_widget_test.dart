import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';
import 'package:ficbatch/models/work.dart';
import 'package:ficbatch/models/reading_progress.dart';
import 'package:ficbatch/providers/storage_provider.dart';
import 'package:ficbatch/services/storage_service.dart';
import 'package:ficbatch/services/sync_folder_service.dart';
import 'package:ficbatch/tabs/history_tab.dart';
import 'package:ficbatch/tabs/updates_tab.dart';
import 'package:ficbatch/tabs/library_tab.dart';

/// Widget tests for the storage-backed tabs, running against a real on-disk
/// Hive store (no mocks — the StorageService box getters work as long as the
/// boxes are open).
void main() {
  late Directory tempDir;
  late StorageService storage;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('ficbatch_tabs_test');
    Hive.init(tempDir.path);
    Hive.registerAdapter(ReadingProgressAdapter());
    Hive.registerAdapter(WorkAdapter());
    await Hive.openBox<Work>(StorageService.worksBoxName);
    await Hive.openBox(StorageService.settingsBoxName);
    storage = StorageService();
  });

  tearDownAll(() async {
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  Widget wrap(Widget child) => ProviderScope(
        overrides: [
          storageProvider.overrideWithValue(storage),
          syncFolderProvider.overrideWithValue(SyncFolderService(storage)),
        ],
        child: MaterialApp(home: Scaffold(body: child)),
      );

  // NOTE: Hive writes are real disk I/O and never complete inside the
  // FakeAsync zone of testWidgets — every storage mutation must run inside
  // tester.runAsync.

  testWidgets('HistoryTab shows the empty state and live-updates', (tester) async {
    await tester.runAsync(() => storage.clearHistory());
    await tester.pumpWidget(wrap(const HistoryTab()));
    await tester.pump();
    expect(find.text('No reading history yet'), findsOneWidget);

    // A history write should appear without a manual refresh (live watch).
    await tester.runAsync(() async {
      await storage.addToHistory(
          workId: '1', title: 'Watched Work', author: 'someone');
      // Give the box watcher a real-async beat to deliver the event.
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump();
    expect(find.text('Watched Work'), findsOneWidget);

    await tester.pumpWidget(const SizedBox()); // dispose the watcher
  });

  testWidgets('UpdatesTab shows the empty state', (tester) async {
    await tester.pumpWidget(wrap(const UpdatesTab()));
    await tester.pump();
    expect(find.text('No updates'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('LibraryTab lists a saved work', (tester) async {
    await tester.runAsync(() => storage.saveWork(Work(
          id: '42',
          title: 'A Library Work',
          author: 'lib author',
          tags: const [],
          userAddedDate: DateTime.now(),
        )));
    await tester.pumpWidget(wrap(const LibraryTab()));
    // Let the categories/works streams emit (real async under runAsync).
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
    await tester.pump();
    expect(find.text('A Library Work'), findsOneWidget);
    expect(find.text('Library'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
