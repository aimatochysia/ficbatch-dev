import 'package:flutter_test/flutter_test.dart';
import 'package:ficbatch/services/library_export_service.dart';
import 'package:ficbatch/services/batch_import_service.dart';

void main() {
  group('ImportResult.toSummary', () {
    test('summarizes added / updated / skipped / categories', () {
      final r = ImportResult(
        worksAdded: 3,
        worksUpdated: 2,
        worksSkipped: 1,
        categoriesAdded: 1,
        totalWorks: 6,
        totalCategories: 2,
      );
      expect(r.toSummary(), '3 added, 2 updated, 1 skipped, 1 categories added');
    });

    test('reports no changes when everything is zero', () {
      final r = ImportResult(
        worksAdded: 0,
        worksUpdated: 0,
        worksSkipped: 0,
        categoriesAdded: 0,
        totalWorks: 0,
        totalCategories: 0,
      );
      expect(r.toSummary(), 'No changes');
    });
  });

  group('BatchImportResult.toSummary', () {
    test('summarizes added / already-in-library / failed', () {
      final r = BatchImportResult(
        totalParsed: 5,
        worksAdded: 3,
        worksFailed: 1,
        worksSkipped: 1,
        errors: ['boom'],
      );
      expect(r.toSummary(), '3 added, 1 already in library, 1 failed');
      expect(r.hasErrors, true);
      expect(r.isSuccess, false);
    });

    test('reports nothing processed when empty', () {
      final r = BatchImportResult(
        totalParsed: 0,
        worksAdded: 0,
        worksFailed: 0,
        worksSkipped: 0,
        errors: const [],
      );
      expect(r.toSummary(), 'No works processed');
      expect(r.isSuccess, true);
    });
  });
}
