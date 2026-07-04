import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data' show BytesBuilder;
import 'package:flutter/foundation.dart';
import 'storage_service.dart';
import 'library_export_service.dart';
import 'download_service.dart';

/// A FicBatch instance seen on the local network.
class LanPeer {
  const LanPeer({
    required this.id,
    required this.name,
    required this.address,
    required this.port,
    required this.lastSeen,
    this.lastSynced,
  });

  final String id;
  final String name;
  final InternetAddress address;
  final int port;
  final DateTime lastSeen;
  final DateTime? lastSynced;

  LanPeer copyWith({DateTime? lastSeen, DateTime? lastSynced}) => LanPeer(
        id: id,
        name: name,
        address: address,
        port: port,
        lastSeen: lastSeen ?? this.lastSeen,
        lastSynced: lastSynced ?? this.lastSynced,
      );
}

/// Automatic sync between devices on the same local network — the "Pears"
/// idea from docs/research/pears_p2p_sync.md, implemented Dart-native
/// (Pears/Bare itself is JS-only). No internet, no server, LAN only:
///
///  - every device broadcasts a small UDP hello on port 47814 every ~15s;
///  - when a hello from a device with the same pairing code arrives, the
///    lexicographically-smaller instance connects to the peer's TCP port,
///    sends its library export and receives the peer's back — both sides
///    merge with the same export-v2 logic the sync folder uses;
///  - a per-peer cooldown keeps the pair from re-syncing in a tight loop.
class LanSyncService {
  LanSyncService(this._storage);

  final StorageService _storage;

  static const int announcePort = 47814;
  static const Duration announceInterval = Duration(seconds: 15);
  static const Duration peerCooldown = Duration(minutes: 5);

  /// Downloaded-file transfers are capped per handshake; anything left over
  /// moves on the next sync (cooldown tick or manual Sync Now).
  static const int maxFilesPerSync = 25;

  /// Devices currently visible on the network (drives the Settings list).
  final ValueNotifier<List<LanPeer>> peers = ValueNotifier(const []);

  static const String _enabledKey = 'lan_sync_enabled';
  static const String _codeKey = 'lan_sync_code';
  static const String _deviceNameKey = 'lan_sync_device_name';
  static const String _lastRunKey = 'lan_sync_last_run';
  static const String _lastPeerKey = 'lan_sync_last_peer';

  /// Random per-launch id: filters out our own broadcasts and tie-breaks
  /// which side of a discovered pair initiates the TCP handshake.
  final String _instanceId =
      List.generate(16, (_) => Random().nextInt(16).toRadixString(16)).join();

  RawDatagramSocket? _udp;
  ServerSocket? _server;
  Timer? _announceTimer;
  bool _handshakeBusy = false;
  final Map<String, DateTime> _peerLastSync = {};

  bool get enabled =>
      _storage.settingsBox.get(_enabledKey, defaultValue: false) == true;

  String get pairingCode =>
      (_storage.settingsBox.get(_codeKey) as String?)?.trim() ?? '';

  String get deviceName {
    final stored = (_storage.settingsBox.get(_deviceNameKey) as String?)?.trim();
    if (stored != null && stored.isNotEmpty) return stored;
    try {
      return Platform.localHostname;
    } catch (_) {
      return 'FicBatch device';
    }
  }

  DateTime? get lastRun {
    final raw = _storage.settingsBox.get(_lastRunKey);
    return raw == null ? null : DateTime.tryParse(raw.toString());
  }

  String? get lastPeer => _storage.settingsBox.get(_lastPeerKey) as String?;

  /// Persist configuration and (re)start. Pass enabled=false to stop.
  Future<void> configure(
      {required bool enabled, String? code, String? deviceName}) async {
    await _storage.settingsBox.put(_enabledKey, enabled);
    if (code != null) await _storage.settingsBox.put(_codeKey, code.trim());
    if (deviceName != null) {
      await _storage.settingsBox.put(_deviceNameKey, deviceName.trim());
    }
    if (enabled) {
      await start();
    } else {
      stop();
    }
  }

  /// Open the TCP handshake server and the UDP announce/listen socket.
  /// Safe to call repeatedly (restarts cleanly).
  Future<void> start() async {
    stop();
    if (!enabled) return;

    try {
      _server = await ServerSocket.bind(InternetAddress.anyIPv4, 0);
      _server!.listen(_handleIncoming, onError: (e) {
        debugPrint('[LanSync] Server error: $e');
      });

      _udp = await RawDatagramSocket.bind(
          InternetAddress.anyIPv4, announcePort,
          reuseAddress: true);
      _udp!.broadcastEnabled = true;
      _udp!.listen(_handleDatagram, onError: (e) {
        debugPrint('[LanSync] UDP error: $e');
      });

      _announceTimer =
          Timer.periodic(announceInterval, (_) => _sendAnnounce());
      _sendAnnounce();
      debugPrint(
          '[LanSync] Announcing as "$deviceName" (tcp ${_server!.port})');
    } catch (e) {
      debugPrint('[LanSync] Start failed: $e');
      stop();
    }
  }

  void stop() {
    _announceTimer?.cancel();
    _announceTimer = null;
    _udp?.close();
    _udp = null;
    _server?.close();
    _server = null;
    peers.value = const [];
  }

  /// TCP handshake port while running (tests and diagnostics).
  @visibleForTesting
  int? get serverPort => _server?.port;

  /// Handshake directly with a known peer address (tests; also the hook for
  /// a future "add device by IP" option).
  Future<void> syncWithPeer(InternetAddress address, int port,
          {String name = 'manual'}) =>
      _dialPeer(address, port, name);

  /// Manual "sync now": clear cooldowns and announce immediately so any
  /// listening peer handshakes right away.
  Future<void> syncNow() async {
    if (!enabled || _udp == null) {
      await start();
    }
    _peerLastSync.clear();
    _sendAnnounce();
  }

  void _sendAnnounce() {
    final udp = _udp;
    final server = _server;
    if (udp == null || server == null) return;
    final packet = utf8.encode(jsonEncode({
      'app': 'ficbatch',
      'v': 1,
      'id': _instanceId,
      'device': deviceName,
      'port': server.port,
    }));
    // Global broadcast plus per-interface subnet broadcast (some routers
    // drop 255.255.255.255) — best effort on both.
    try {
      udp.send(packet, InternetAddress('255.255.255.255'), announcePort);
    } catch (e) {
      debugPrint('[LanSync] Broadcast send failed: $e');
    }
    NetworkInterface.list(type: InternetAddressType.IPv4).then((ifaces) {
      for (final iface in ifaces) {
        for (final addr in iface.addresses) {
          final parts = addr.address.split('.');
          if (parts.length != 4 || parts[0] == '127') continue;
          try {
            udp.send(
                packet,
                InternetAddress(
                    '${parts[0]}.${parts[1]}.${parts[2]}.255'),
                announcePort);
          } catch (_) {}
        }
      }
    }).catchError((e) {
      debugPrint('[LanSync] Interface listing failed: $e');
    });
  }

  void _handleDatagram(RawSocketEvent event) {
    if (event != RawSocketEvent.read) return;
    final datagram = _udp?.receive();
    if (datagram == null) return;
    try {
      final data = jsonDecode(utf8.decode(datagram.data));
      if (data is! Map || data['app'] != 'ficbatch') return;
      final peerId = data['id']?.toString() ?? '';
      if (peerId.isEmpty || peerId == _instanceId) return;
      final port = data['port'];
      if (port is! int) return;
      final name = data['device']?.toString() ?? '?';

      _upsertPeer(LanPeer(
        id: peerId,
        name: name,
        address: datagram.address,
        port: port,
        lastSeen: DateTime.now(),
      ));

      // Tie-break: only the smaller instance id dials out, so a discovered
      // pair produces exactly one (bidirectional) handshake.
      if (_instanceId.compareTo(peerId) >= 0) return;

      final last = _peerLastSync[peerId];
      if (last != null && DateTime.now().difference(last) < peerCooldown) {
        return;
      }
      _peerLastSync[peerId] = DateTime.now();
      _dialPeer(datagram.address, port, name);
    } catch (_) {
      // Not our packet — ignore.
    }
  }

  /// Insert/update a visible peer (keeps lastSynced) and drop entries that
  /// have stopped announcing.
  void _upsertPeer(LanPeer peer) {
    final now = DateTime.now();
    DateTime? knownLastSynced;
    for (final p in peers.value) {
      if (p.id == peer.id) knownLastSynced = p.lastSynced;
    }
    peers.value = [
      for (final p in peers.value)
        if (p.id != peer.id && now.difference(p.lastSeen).inSeconds < 60) p,
      peer.copyWith(lastSynced: knownLastSynced),
    ]..sort((a, b) => b.lastSeen.compareTo(a.lastSeen));
  }

  void _markPeerSynced({String? id, InternetAddress? address}) {
    peers.value = [
      for (final p in peers.value)
        (id != null && p.id == id) ||
                (address != null && p.address.address == address.address)
            ? p.copyWith(lastSynced: DateTime.now())
            : p,
    ];
  }

  /// Client side of the handshake: send our export + downloaded-file list,
  /// merge the reply, then trade downloaded files both ways (capped).
  Future<void> _dialPeer(InternetAddress address, int port, String name) async {
    if (_handshakeBusy) return;
    _handshakeBusy = true;
    Socket? socket;
    _LineReader? reader;
    try {
      socket = await Socket.connect(address, port,
          timeout: const Duration(seconds: 10));
      reader = _LineReader(socket);
      final export = await LibraryExportService(_storage).exportToJson();
      final myHave = await _downloadedIds();
      socket.add(utf8.encode('${jsonEncode({
            'code': pairingCode,
            'id': _instanceId,
            'device': deviceName,
            'export': export,
            'have': myHave,
          })}\n'));
      await socket.flush();

      final reply = await reader.next();
      final data = jsonDecode(reply);
      if (data is! Map) return;
      if (data['error'] != null) {
        debugPrint('[LanSync] Peer "$name" refused: ${data['error']}');
        return;
      }
      if (data['export'] is String) {
        final result = await LibraryExportService(_storage)
            .importFromJson(data['export'] as String, mode: ImportMode.merge);
        debugPrint('[LanSync] Synced with "$name": ${result.toSummary()}');
      }

      // File phase — only when the peer understands it (v0.7.5+).
      if (data['have'] is List) {
        final peerHave =
            (data['have'] as List).map((e) => e.toString()).toSet();
        final want = (peerHave.difference(myHave.toSet()).toList()..sort())
            .take(maxFilesPerSync)
            .toList();
        final theirWant =
            (data['want'] as List? ?? []).map((e) => e.toString()).toList();
        socket.add(utf8.encode('${jsonEncode({
              'files': await _readFiles(theirWant),
              'want': want,
            })}\n'));
        await socket.flush();
        final frame2 = jsonDecode(await reader.next());
        if (frame2 is Map && frame2['files'] is Map) {
          final n = await _writeFiles(frame2['files'] as Map);
          if (n > 0) debugPrint('[LanSync] Received $n downloaded works');
        }
      }
      await _recordRun(name);
      _markPeerSynced(address: address);
    } catch (e) {
      debugPrint('[LanSync] Handshake with "$name" failed: $e');
    } finally {
      reader?.cancel();
      socket?.destroy();
      _handshakeBusy = false;
    }
  }

  /// Server side: merge the caller's export, reply with our own (plus our
  /// downloaded-file list), then trade files both ways.
  Future<void> _handleIncoming(Socket socket) async {
    final reader = _LineReader(socket);
    try {
      final line = await reader.next();
      final data = jsonDecode(line);
      if (data is! Map || data['export'] is! String) {
        socket.add(utf8.encode('${jsonEncode({'error': 'bad request'})}\n'));
        return;
      }
      if ((data['code']?.toString() ?? '') != pairingCode) {
        socket.add(
            utf8.encode('${jsonEncode({'error': 'pairing code mismatch'})}\n'));
        debugPrint('[LanSync] Rejected peer: pairing code mismatch');
        return;
      }
      final result = await LibraryExportService(_storage)
          .importFromJson(data['export'] as String, mode: ImportMode.merge);
      final export = await LibraryExportService(_storage).exportToJson();

      final clientHave = data['have'] is List
          ? (data['have'] as List).map((e) => e.toString()).toSet()
          : null;
      final reply = <String, dynamic>{'export': export};
      List<String> want = const [];
      if (clientHave != null) {
        final myHave = await _downloadedIds();
        want = (clientHave.difference(myHave.toSet()).toList()..sort())
            .take(maxFilesPerSync)
            .toList();
        reply['have'] = myHave;
        reply['want'] = want;
      }
      socket.add(utf8.encode('${jsonEncode(reply)}\n'));
      await socket.flush();

      if (clientHave != null) {
        final frame2 = jsonDecode(await reader.next());
        if (frame2 is Map) {
          if (frame2['files'] is Map) {
            final n = await _writeFiles(frame2['files'] as Map);
            if (n > 0) debugPrint('[LanSync] Received $n downloaded works');
          }
          final theirWant = (frame2['want'] as List? ?? [])
              .map((e) => e.toString())
              .toList();
          socket.add(utf8.encode(
              '${jsonEncode({'files': await _readFiles(theirWant)})}\n'));
          await socket.flush();
        }
      }
      await _recordRun(data['device']?.toString() ??
          socket.remoteAddress.address);
      _markPeerSynced(
          id: data['id']?.toString(), address: socket.remoteAddress);
      debugPrint('[LanSync] Peer synced in: ${result.toSummary()}');
    } catch (e) {
      debugPrint('[LanSync] Incoming handshake failed: $e');
    } finally {
      reader.cancel();
      socket.destroy();
    }
  }

  /// Ids of the works whose downloaded .html exists locally. Errors (e.g. an
  /// unavailable downloads dir) degrade to "no files" so metadata sync still
  /// runs.
  Future<List<String>> _downloadedIds() async {
    try {
      final dir = await DownloadService.getDownloadsDirectory();
      final ids = <String>[];
      await for (final entity in dir.list()) {
        if (entity is File && entity.path.endsWith('.html')) {
          final name = entity.uri.pathSegments.last;
          ids.add(name.substring(0, name.length - 5));
        }
      }
      ids.sort();
      return ids;
    } catch (e) {
      debugPrint('[LanSync] Listing downloads failed: $e');
      return const [];
    }
  }

  Future<Map<String, String>> _readFiles(List<String> ids) async {
    final out = <String, String>{};
    for (final id in ids.take(maxFilesPerSync)) {
      try {
        final content = await DownloadService.getDownloadedContent(id);
        if (content != null) out[id] = content;
      } catch (e) {
        debugPrint('[LanSync] Reading download $id failed: $e');
      }
    }
    return out;
  }

  Future<int> _writeFiles(Map files) async {
    var written = 0;
    for (final entry in files.entries) {
      final id = entry.key.toString();
      // Work ids are numeric — refuse anything that could escape the
      // downloads directory.
      if (!RegExp(r'^\d+$').hasMatch(id)) continue;
      try {
        final path = await DownloadService.getWorkDownloadPath(id);
        await File(path).writeAsString(entry.value.toString());
        written++;
        final work = _storage.getWork(id);
        if (work != null && !work.isDownloaded) {
          await _storage.saveWork(work.copyWith(
              isDownloaded: true, downloadedAt: DateTime.now()));
        }
      } catch (e) {
        debugPrint('[LanSync] Writing download $id failed: $e');
      }
    }
    return written;
  }

  Future<void> _recordRun(String peer) async {
    await _storage.settingsBox
        .put(_lastRunKey, DateTime.now().toIso8601String());
    await _storage.settingsBox.put(_lastPeerKey, peer);
  }

}

/// Hands out newline-terminated UTF-8 frames from a socket. A [Socket] is a
/// single-subscription stream, so multi-frame handshakes need one persistent
/// listener per connection (export JSON escapes its own newlines, so line
/// framing is safe even for multi-MB payloads).
class _LineReader {
  _LineReader(Socket socket) {
    _sub = socket.listen(_onData, onDone: _onClose, onError: (_) => _onClose());
  }

  late final StreamSubscription _sub;
  final BytesBuilder _buffer = BytesBuilder(copy: false);
  final List<String> _ready = [];
  final List<Completer<String>> _pending = [];
  bool _closed = false;

  void _onData(List<int> chunk) {
    var start = 0;
    for (var i = 0; i < chunk.length; i++) {
      if (chunk[i] == 10) {
        _buffer.add(chunk.sublist(start, i));
        _emit(utf8.decode(_buffer.takeBytes()));
        start = i + 1;
      }
    }
    if (start < chunk.length) _buffer.add(chunk.sublist(start));
  }

  void _emit(String line) {
    if (_pending.isNotEmpty) {
      _pending.removeAt(0).complete(line);
    } else {
      _ready.add(line);
    }
  }

  void _onClose() {
    if (_closed) return;
    _closed = true;
    final rest = _buffer.takeBytes();
    if (rest.isNotEmpty) _emit(utf8.decode(rest));
    for (final c in _pending) {
      c.completeError(StateError('LAN sync connection closed'));
    }
    _pending.clear();
  }

  Future<String> next({Duration timeout = const Duration(seconds: 60)}) {
    if (_ready.isNotEmpty) return Future.value(_ready.removeAt(0));
    if (_closed) return Future.error(StateError('LAN sync connection closed'));
    final c = Completer<String>();
    _pending.add(c);
    return c.future.timeout(timeout);
  }

  void cancel() {
    _sub.cancel();
  }
}
