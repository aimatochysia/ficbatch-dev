import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:ficbatch/models/work.dart';
import 'package:ficbatch/models/reading_progress.dart';
import 'package:ficbatch/services/storage_service.dart';
import 'package:ficbatch/services/lan_sync_service.dart';
import 'package:ficbatch/services/library_export_service.dart';

/// Smoke tests for the LAN sync TCP handshake against a real on-disk Hive
/// store: a fake peer connects to the service's server socket, pushes an
/// export containing an extra work, and must get our export back.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late StorageService storage;
  late LanSyncService service;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('ficbatch_lan_test');
    Hive.init(tempDir.path);
    Hive.registerAdapter(ReadingProgressAdapter());
    Hive.registerAdapter(WorkAdapter());
    await Hive.openBox<Work>(StorageService.worksBoxName);
    await Hive.openBox(StorageService.settingsBoxName);
    storage = StorageService();
    await storage.settingsBox.put('lan_sync_enabled', true);
    service = LanSyncService(storage);
    await service.start();
  });

  tearDownAll(() async {
    service.stop();
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  Future<String> handshake(String code, Map<String, dynamic> export) async {
    final socket =
        await Socket.connect(InternetAddress.loopbackIPv4, service.serverPort!);
    socket.add(utf8
        .encode('${jsonEncode({'code': code, 'export': jsonEncode(export)})}\n'));
    await socket.flush();
    final reply = await socket
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .first;
    socket.destroy();
    return reply;
  }

  Future<Map<String, dynamic>> exportWithExtraWork(String id) async {
    final data = jsonDecode(await LibraryExportService(storage).exportToJson())
        as Map<String, dynamic>;
    (data['works'] as List).add(Work(
      id: id,
      title: 'LAN Synced Work $id',
      author: 'peer device',
      tags: const [],
      userAddedDate: DateTime.now(),
    ).toJson());
    data['exportedAt'] = DateTime.now().toIso8601String();
    return data;
  }

  test('server merges a matching peer export and replies with ours', () async {
    expect(service.serverPort, isNotNull);

    final reply = await handshake('', await exportWithExtraWork('lan-1'));
    final decoded = jsonDecode(reply) as Map<String, dynamic>;

    expect(decoded['export'], isA<String>());
    // The peer's extra work was merged into our store...
    expect(storage.getWork('lan-1'), isNotNull);
    // ...and the export we sent back includes it too.
    final ourExport = jsonDecode(decoded['export'] as String);
    final ids = (ourExport['works'] as List).map((w) => w['id']).toList();
    expect(ids, contains('lan-1'));
  });

  test('pairing code mismatch is refused without merging', () async {
    await storage.settingsBox.put('lan_sync_code', 'secret');

    final reply = await handshake('wrong', await exportWithExtraWork('lan-2'));
    final decoded = jsonDecode(reply) as Map<String, dynamic>;

    expect(decoded['error'], isNotNull);
    expect(storage.getWork('lan-2'), isNull);

    await storage.settingsBox.put('lan_sync_code', '');
  });
}
