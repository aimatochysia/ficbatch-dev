import 'package:flutter_test/flutter_test.dart';
import 'package:ficbatch/models/work.dart';
import 'package:ficbatch/models/reading_progress.dart';

void main() {
  group('Work JSON round-trip', () {
    test('preserves core fields', () {
      final work = Work(
        id: '42',
        title: 'A Test Work',
        author: 'Author Name',
        tags: ['Fluff', 'Angst'],
        userAddedDate: DateTime.parse('2024-01-02T03:04:05.000'),
        wordsCount: 12345,
        chaptersCount: 7,
        updatedAt: DateTime.parse('2024-05-06T00:00:00.000'),
        isFavorite: true,
        summary: 'A short summary.',
      );

      final restored = Work.fromJson(work.toJson());

      expect(restored.id, '42');
      expect(restored.title, 'A Test Work');
      expect(restored.author, 'Author Name');
      expect(restored.tags, ['Fluff', 'Angst']);
      expect(restored.wordsCount, 12345);
      expect(restored.chaptersCount, 7);
      expect(restored.updatedAt, DateTime.parse('2024-05-06T00:00:00.000'));
      expect(restored.isFavorite, true);
      expect(restored.summary, 'A short summary.');
    });

    test('fromJson tolerates missing/null fields', () {
      final restored = Work.fromJson({'id': '1'});
      expect(restored.id, '1');
      expect(restored.title, 'Untitled');
      expect(restored.author, 'Unknown');
      expect(restored.tags, isEmpty);
      expect(restored.isFavorite, false);
    });

    test('copyWith toggles favorite without losing other data', () {
      final work = Work(
        id: '7',
        title: 'Keep Me',
        author: 'Someone',
        tags: const [],
        userAddedDate: DateTime.now(),
      );
      final favorited = work.copyWith(isFavorite: true);
      expect(favorited.isFavorite, true);
      expect(favorited.title, 'Keep Me');
      expect(favorited.id, '7');
    });
  });

  group('ReadingProgress', () {
    test('round-trips through JSON', () {
      final p = ReadingProgress(
        chapterIndex: 3,
        scrollPosition: 0.42,
        chapterName: 'Chapter 4',
        paragraphAnchor: 'It was a dark and stormy night',
      );

      final restored = ReadingProgress.fromJson(p.toJson());

      expect(restored.chapterIndex, 3);
      expect(restored.scrollPosition, 0.42);
      expect(restored.chapterName, 'Chapter 4');
      expect(restored.paragraphAnchor, 'It was a dark and stormy night');
    });

    test('empty() reports no progress', () {
      expect(ReadingProgress.empty().hasProgress, false);
    });

    test('non-zero chapter index counts as progress', () {
      expect(
        ReadingProgress(chapterIndex: 2, scrollPosition: 0.0).hasProgress,
        true,
      );
    });
  });
}
