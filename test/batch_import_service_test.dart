import 'package:flutter_test/flutter_test.dart';
import 'package:ficbatch/services/batch_import_service.dart';
import 'package:ficbatch/services/storage_service.dart';
import 'package:ficbatch/services/ao3_service.dart';
import 'package:ficbatch/services/library_export_service.dart';

void main() {
  // parseWorkIds is pure string logic and does not touch storage/network, so
  // the dependencies can be constructed without initialization.
  final storage = StorageService();
  final service =
      BatchImportService(storage, Ao3Service(), LibraryExportService(storage));

  group('BatchImportService.parseWorkIds', () {
    test('extracts a bare numeric work id', () {
      expect(service.parseWorkIds('123456'), ['123456']);
    });

    test('extracts the id from a full work URL', () {
      expect(
        service.parseWorkIds('https://archiveofourown.org/works/987654'),
        ['987654'],
      );
    });

    test('extracts the id from a chapter URL', () {
      expect(
        service.parseWorkIds('https://archiveofourown.org/works/111/chapters/222'),
        ['111'],
      );
    });

    test('extracts the id from a short /works/ path', () {
      expect(service.parseWorkIds('/works/555'), ['555']);
    });

    test('parses several mixed inputs separated by commas/spaces/newlines', () {
      final ids = service.parseWorkIds(
        '123, 456\n/works/789 https://archiveofourown.org/works/100',
      );
      expect(ids, containsAll(['123', '456', '789', '100']));
      expect(ids.length, 4);
    });

    test('de-duplicates repeated ids', () {
      expect(service.parseWorkIds('123 123 /works/123'), ['123']);
    });

    test('ignores non-work garbage', () {
      expect(service.parseWorkIds('hello world'), isEmpty);
    });

    test('validateInput returns the parsed count', () {
      expect(service.validateInput('1 2 3'), 3);
    });
  });
}
