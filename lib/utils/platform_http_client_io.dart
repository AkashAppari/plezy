import 'dart:io' show HttpClient, Platform;

import 'package:cronet_http/cronet_http.dart';
import 'package:cupertino_http/cupertino_http.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:win_http/win_http.dart';

import 'app_logger.dart';
import 'managed_http_client.dart';

/// Shared Cronet engine so all clients reuse the same connection pool.
CronetEngine? _sharedEngine;

bool _loggedPlatformClient = false;

void _logPlatformClient(String platform, String client) {
  if (_loggedPlatformClient) return;
  _loggedPlatformClient = true;
  appLogger.i('Platform HTTP client', error: {'platform': platform, 'client': client});
}

http.Client createPlatformClient() {
  if (Platform.isAndroid) {
    _sharedEngine ??= CronetEngine.build(
      cacheMode: CacheMode.memory,
      cacheMaxSize: 2 * 1024 * 1024,
      enableBrotli: true,
      enableHttp2: true,
    );
    _logPlatformClient('android', 'CronetClient');
    return ManagedHttpClient(CronetClient.fromCronetEngine(_sharedEngine!), debugLabel: 'CronetClient');
  }
  if (Platform.isIOS || Platform.isMacOS) {
    // cupertino_http relies on the objective_c FFI dylib, which isn't
    // available on tvOS. Fall back to IOClient if the init fails.
    try {
      final client = CupertinoClient.defaultSessionConfiguration();
      _logPlatformClient(Platform.isIOS ? 'ios' : 'macos', 'CupertinoClient');
      return ManagedHttpClient(client, debugLabel: 'CupertinoClient');
    } catch (e, st) {
      appLogger.w('CupertinoClient init failed, falling back to IOClient', error: e, stackTrace: st);
      _logPlatformClient(Platform.isIOS ? 'ios' : 'macos', 'IOClient (fallback)');
      return ManagedHttpClient(IOClient(), debugLabel: 'IOClient (fallback)');
    }
  }
  if (Platform.isWindows) {
    try {
      final client = WinHttpClient.defaultConfiguration();
      _logPlatformClient('windows', 'WinHttpClient');
      return ManagedHttpClient(client, debugLabel: 'WinHttpClient');
    } catch (e, st) {
      appLogger.w('WinHttpClient init failed, falling back to IOClient', error: e, stackTrace: st);
      _logPlatformClient('windows', 'IOClient (fallback)');
      return ManagedHttpClient(IOClient(), debugLabel: 'IOClient (fallback)');
    }
  }
  _logPlatformClient(Platform.operatingSystem, 'IOClient');
  return ManagedHttpClient(IOClient(), debugLabel: 'IOClient');
}

http.Client createPlexApiClient() {
  if (Platform.isLinux) {
    _logPlatformClient('linux', 'IOClient (Plex API tuned)');
    return ManagedHttpClient(
      IOClient(
        HttpClient()
          ..maxConnectionsPerHost = 12
          ..idleTimeout = const Duration(seconds: 90),
      ),
      debugLabel: 'IOClient (Plex API tuned)',
    );
  }
  return createPlatformClient();
}
