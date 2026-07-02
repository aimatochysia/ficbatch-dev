import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:ficbatch/models/work.dart';
import 'package:ficbatch/models/reading_progress.dart';

/// Round-trips the Hive adapters through a real on-disk box — guards the
/// hive_ce migration (same typeIds 0/1 as the original hive adapters).
void main() {
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('ficbatch_hive_test');
    Hive.init(tempDir.path);
    Hive.registerAdapter(ReadingProgressAdapter());
    Hive.registerAdapter(WorkAdapter());
  });

  tearDownAll(() async {
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  test('Work persists and reloads through a Hive box', () async {
    final box = await Hive.openBox<Work>('works_test');
    final work = Work(
      id: '77',
      title: 'Boxed Work',
      author: 'writer',
      tags: const ['tag1', 'tag2'],
      userAddedDate: DateTime.parse('2026-01-01T00:00:00.000'),
      wordsCount: 5000,
      isFavorite: true,
      readingProgress: ReadingProgress(
        chapterIndex: 2,
        scrollPosition: 0.5,
        chapterName: 'Chapter 3',
      ),
    );

    await box.put(work.id, work);
    await box.close();

    final reopened = await Hive.openBox<Work>('works_test');
    final loaded = reopened.get('77');

    expect(loaded, isNotNull);
    expect(loaded!.title, 'Boxed Work');
    expect(loaded.tags, ['tag1', 'tag2']);
    expect(loaded.wordsCount, 5000);
    expect(loaded.isFavorite, true);
    expect(loaded.readingProgress.chapterIndex, 2);
    expect(loaded.readingProgress.chapterName, 'Chapter 3');
    await reopened.close();
  });
}
