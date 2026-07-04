import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:ficbatch/models/work.dart';
import 'package:ficbatch/models/reading_progress.dart';
import 'package:ficbatch/services/storage_service.dart';
import 'package:ficbatch/services/lan_sync_service.dart';
import 'package:ficbatch/services/library_export_service.dart';
import 'package:ficbatch/services/download_service.dart';

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
    // Point downloads at the temp dir so the file phase works without
    // path_provider (desktop honors the custom dir).
    DownloadService.configureDirectory('${tempDir.path}/downloads');
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

  test('file phase trades downloaded works both ways', () async {
    // Server owns a download the client lacks…
    final serverFile =
        File(await DownloadService.getWorkDownloadPath('111'));
    await serverFile.writeAsString('<html>server copy</html>');

    final socket =
        await Socket.connect(InternetAddress.loopbackIPv4, service.serverPort!);
    final lines = socket
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .asBroadcastStream();

    // …and the client announces it owns work 222.
    final export = await LibraryExportService(storage).exportToJson();
    socket.add(utf8.encode('${jsonEncode({
          'code': '',
          'export': export,
          'have': ['222'],
        })}\n'));
    await socket.flush();

    final reply = jsonDecode(await lines.first) as Map<String, dynamic>;
    expect(List<String>.from(reply['have'] as List), contains('111'));
    expect(List<String>.from(reply['want'] as List), equals(['222']));

    // Client sends the file the server wants and asks for 111.
    socket.add(utf8.encode('${jsonEncode({
          'files': {'222': '<html>client copy</html>'},
          'want': ['111'],
        })}\n'));
    await socket.flush();

    final frame2 = jsonDecode(await lines.first) as Map<String, dynamic>;
    socket.destroy();
    expect(frame2['files']['111'], '<html>server copy</html>');

    // The server persisted the client's file to its downloads dir.
    final received =
        File(await DownloadService.getWorkDownloadPath('222'));
    expect(await received.readAsString(), '<html>client copy</html>');
  });
}
