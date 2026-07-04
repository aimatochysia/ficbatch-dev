import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data' show BytesBuilder;
import 'package:flutter/foundation.dart';
import 'storage_service.dart';
import 'library_export_service.dart';

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

      // Tie-break: only the smaller instance id dials out, so a discovered
      // pair produces exactly one (bidirectional) handshake.
      if (_instanceId.compareTo(peerId) >= 0) return;

      final last = _peerLastSync[peerId];
      if (last != null && DateTime.now().difference(last) < peerCooldown) {
        return;
      }
      final port = data['port'];
      if (port is! int) return;
      _peerLastSync[peerId] = DateTime.now();
      _dialPeer(datagram.address, port, data['device']?.toString() ?? '?');
    } catch (_) {
      // Not our packet — ignore.
    }
  }

  /// Client side of the handshake: send our export, merge the reply.
  Future<void> _dialPeer(InternetAddress address, int port, String name) async {
    if (_handshakeBusy) return;
    _handshakeBusy = true;
    Socket? socket;
    try {
      socket = await Socket.connect(address, port,
          timeout: const Duration(seconds: 10));
      final export = await LibraryExportService(_storage).exportToJson();
      socket.add(utf8.encode(
          '${jsonEncode({'code': pairingCode, 'export': export})}\n'));
      await socket.flush();

      final reply = await _readLine(socket);
      final data = jsonDecode(reply);
      if (data is Map && data['export'] is String) {
        final result = await LibraryExportService(_storage)
            .importFromJson(data['export'] as String, mode: ImportMode.merge);
        await _recordRun(name);
        debugPrint('[LanSync] Synced with "$name": ${result.toSummary()}');
      } else if (data is Map && data['error'] != null) {
        debugPrint('[LanSync] Peer "$name" refused: ${data['error']}');
      }
    } catch (e) {
      debugPrint('[LanSync] Handshake with "$name" failed: $e');
    } finally {
      socket?.destroy();
      _handshakeBusy = false;
    }
  }

  /// Server side: merge the caller's export, reply with our own.
  Future<void> _handleIncoming(Socket socket) async {
    try {
      final line = await _readLine(socket);
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
      socket.add(utf8.encode('${jsonEncode({'export': export})}\n'));
      await socket.flush();
      await _recordRun(socket.remoteAddress.address);
      debugPrint('[LanSync] Peer synced in: ${result.toSummary()}');
    } catch (e) {
      debugPrint('[LanSync] Incoming handshake failed: $e');
    } finally {
      socket.destroy();
    }
  }

  Future<void> _recordRun(String peer) async {
    await _storage.settingsBox
        .put(_lastRunKey, DateTime.now().toIso8601String());
    await _storage.settingsBox.put(_lastPeerKey, peer);
  }

  /// Reads one newline-terminated UTF-8 frame (export JSON escapes its own
  /// newlines, so line framing is safe even for multi-MB payloads).
  Future<String> _readLine(Socket socket) {
    final completer = Completer<String>();
    final buffer = BytesBuilder(copy: false);
    late StreamSubscription sub;
    final timeout = Timer(const Duration(seconds: 60), () {
      sub.cancel();
      if (!completer.isCompleted) {
        completer.completeError(TimeoutException('LAN sync frame timeout'));
      }
    });
    sub = socket.listen((chunk) {
      final newline = chunk.indexOf(10);
      if (newline >= 0) {
        buffer.add(chunk.sublist(0, newline));
        timeout.cancel();
        sub.cancel();
        if (!completer.isCompleted) {
          completer.complete(utf8.decode(buffer.takeBytes()));
        }
      } else {
        buffer.add(chunk);
      }
    }, onDone: () {
      timeout.cancel();
      if (!completer.isCompleted) {
        completer.complete(utf8.decode(buffer.takeBytes()));
      }
    }, onError: (e) {
      timeout.cancel();
      if (!completer.isCompleted) completer.completeError(e);
    });
    return completer.future;
  }
}
