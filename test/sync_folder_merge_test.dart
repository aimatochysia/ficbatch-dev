import 'package:flutter_test/flutter_test.dart';
import 'package:ficbatch/services/library_export_service.dart';

Map<String, dynamic> entry(String workId, String accessedAt,
        {String title = 't'}) =>
    {'workId': workId, 'title': title, 'author': 'a', 'accessedAt': accessedAt};

void main() {
  group('LibraryExportService.mergeHistories', () {
    test('unions and dedupes by (workId, accessedAt), newest first', () {
      final local = [
        entry('1', '2026-01-02T10:00:00.000'),
        entry('2', '2026-01-01T10:00:00.000'),
      ];
      final imported = [
        entry('1', '2026-01-02T10:00:00.000'), // duplicate
        entry('3', '2026-01-03T10:00:00.000'), // newer, from other device
      ];

      final merged = LibraryExportService.mergeHistories(local, imported);

      expect(merged.length, 3);
      expect(merged.first['workId'], '3'); // newest first
      expect(merged.last['workId'], '2');
    });

    test('same work on different days keeps both entries', () {
      final merged = LibraryExportService.mergeHistories(
        [entry('1', '2026-01-01T10:00:00.000')],
        [entry('1', '2026-01-02T10:00:00.000')],
      );
      expect(merged.length, 2);
    });

    test('caps the merged list', () {
      final local = List.generate(
          400, (i) => entry('$i', '2026-01-01T10:${i % 60}:00.000'));
      final imported = List.generate(
          400, (i) => entry('x$i', '2026-01-02T10:${i % 60}:00.000'));
      final merged = LibraryExportService.mergeHistories(local, imported);
      expect(merged.length, 500);
      // Imported (newer) entries survive the cap.
      expect(merged.first['workId'], startsWith('x'));
    });

    test('tolerates malformed dates', () {
      final merged = LibraryExportService.mergeHistories(
        [entry('1', 'garbage')],
        [entry('2', '2026-01-01T00:00:00.000')],
      );
      expect(merged.length, 2);
      expect(merged.first['workId'], '2'); // parseable date sorts first
    });
  });
}
