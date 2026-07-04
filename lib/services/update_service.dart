import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

/// A newer release found on GitHub.
class UpdateInfo {
  const UpdateInfo({
    required this.tag,
    required this.latestVersion,
    required this.currentVersion,
    required this.releaseUrl,
    this.assetUrl,
    this.assetName,
    this.notes,
  });

  final String tag;
  final String latestVersion;
  final String currentVersion;

  /// The release page (fallback and iOS).
  final String releaseUrl;

  /// Direct download of this platform's installer, when the release has it.
  final String? assetUrl;
  final String? assetName;
  final String? notes;
}

/// Checks the repo's latest GitHub release against the running version and
/// points the user at the right installer for their platform. The download/
/// install step goes through the system browser — no extra permissions, and
/// on Android the installer offers an in-place update (data kept) as long as
/// the installed build came from the same signed release pipeline.
class UpdateService {
  static const String enabledKey = 'update_check_enabled';
  static const String _latestReleaseApi =
      'https://api.github.com/repos/aimatochysia/ficbatch-dev/releases/latest';

  /// Returns the newer release, or null when up to date (or on any error —
  /// update checking must never break app startup).
  static Future<UpdateInfo?> checkForUpdate() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final current = info.version;
      final resp = await http.get(Uri.parse(_latestReleaseApi), headers: {
        'Accept': 'application/vnd.github+json',
        'User-Agent': 'FicBatch/$current',
      }).timeout(const Duration(seconds: 15));
      if (resp.statusCode != 200) return null;

      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final tag = data['tag_name']?.toString() ?? '';
      final latest = tag.startsWith('v') ? tag.substring(1) : tag;
      if (latest.isEmpty || !isNewerVersion(latest, current)) return null;

      final wantedAsset = platformAssetName();
      String? assetUrl;
      for (final asset in (data['assets'] as List? ?? [])) {
        if (asset is Map && asset['name'] == wantedAsset) {
          assetUrl = asset['browser_download_url']?.toString();
        }
      }
      return UpdateInfo(
        tag: tag,
        latestVersion: latest,
        currentVersion: current,
        releaseUrl: data['html_url']?.toString() ??
            'https://github.com/aimatochysia/ficbatch-dev/releases',
        assetUrl: assetUrl,
        assetName: wantedAsset,
        notes: data['body']?.toString(),
      );
    } catch (e) {
      debugPrint('[UpdateService] Check failed: $e');
      return null;
    }
  }

  /// Dotted-numeric comparison ("0.7.10" > "0.7.9"); non-numeric parts
  /// compare as 0.
  @visibleForTesting
  static bool isNewerVersion(String candidate, String current) {
    final a = candidate.split('.');
    final b = current.split('.');
    for (var i = 0; i < a.length || i < b.length; i++) {
      final x = i < a.length ? int.tryParse(a[i]) ?? 0 : 0;
      final y = i < b.length ? int.tryParse(b[i]) ?? 0 : 0;
      if (x != y) return x > y;
    }
    return false;
  }

  /// This platform's release asset, or null when only the release page makes
  /// sense (iOS sideloading).
  static String? platformAssetName() {
    if (Platform.isAndroid) return 'ficbatch.apk';
    if (Platform.isWindows) return 'ficbatch-windows.exe';
    if (Platform.isLinux) return 'ficbatch-linux.deb';
    if (Platform.isMacOS) return 'ficbatch-macos.zip';
    return null;
  }
}
