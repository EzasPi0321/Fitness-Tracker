import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// The GitHub repository that publishes FitTrack releases.
const releasesRepo = 'EzasPi0321/Fitness-Tracker';

/// The build number this copy of the app was made from. CI passes it with
/// `--dart-define=FITTRACK_BUILD=<run number>`; local builds report 0.
const appBuild = int.fromEnvironment('FITTRACK_BUILD');

/// A published release newer than this build.
class AppUpdate {
  const AppUpdate({
    required this.version,
    required this.build,
    required this.notes,
    required this.downloadUrl,
    required this.pageUrl,
  });

  final String version; // "2.0.0"
  final int build;
  final String notes; // first line of the release notes
  /// The file for this platform (APK, Windows zip), or null to open the release page.
  final String? downloadUrl;
  final String pageUrl;

  String get label => '$version (build $build)';
}

/// Which release file this platform installs from.
String? assetNameFor(TargetPlatform platform, {required bool web}) {
  if (web) return null;
  return switch (platform) {
    TargetPlatform.android => 'FitTrack.apk',
    TargetPlatform.windows => 'FitTrack-Windows.zip',
    _ => null, // iPhone installs through SideStore; open the release page.
  };
}

class UpdateService {
  UpdateService({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;

  /// Returns the latest release if it's newer than [currentBuild], otherwise null.
  /// Throws [UpdateCheckException] when GitHub can't be reached.
  Future<AppUpdate?> check({int currentBuild = appBuild}) async {
    final http.Response res;
    try {
      res = await _client
          .get(
            Uri.parse('https://api.github.com/repos/$releasesRepo/releases/latest'),
            headers: const {'Accept': 'application/vnd.github+json'},
          )
          .timeout(const Duration(seconds: 12));
    } catch (_) {
      throw const UpdateCheckException("Couldn’t reach GitHub. Check your connection and try again.");
    }
    if (res.statusCode == 404) return null; // nothing published yet
    if (res.statusCode != 200) throw UpdateCheckException('GitHub returned an error (${res.statusCode}).');
    final Object? json;
    try {
      json = jsonDecode(utf8.decode(res.bodyBytes));
    } catch (_) {
      throw const UpdateCheckException("The release information couldn’t be read.");
    }
    return parseRelease(json, currentBuild: currentBuild, platform: defaultTargetPlatform, web: kIsWeb);
  }

  /// Reads a GitHub "latest release" response. Tags look like `v2.0.0-build12`.
  static AppUpdate? parseRelease(
    Object? json, {
    required int currentBuild,
    required TargetPlatform platform,
    required bool web,
  }) {
    if (json is! Map) return null;
    final tag = json['tag_name'] is String ? json['tag_name'] as String : '';
    final m = RegExp(r'^v?([\d.]+)-build(\d+)$').firstMatch(tag);
    if (m == null) return null;
    final build = int.parse(m.group(2)!);
    if (build <= currentBuild) return null;

    final wanted = assetNameFor(platform, web: web);
    String? url;
    for (final a in (json['assets'] is List ? json['assets'] as List : const [])) {
      if (a is Map && a['name'] == wanted) url = a['browser_download_url'] as String?;
    }
    final body = json['body'] is String ? (json['body'] as String).trim() : '';
    return AppUpdate(
      version: m.group(1)!,
      build: build,
      notes: body.split('\n').first.trim(),
      downloadUrl: url,
      pageUrl: json['html_url'] is String
          ? json['html_url'] as String
          : 'https://github.com/$releasesRepo/releases/latest',
    );
  }
}

class UpdateCheckException implements Exception {
  const UpdateCheckException(this.message);
  final String message;
  @override
  String toString() => message;
}
