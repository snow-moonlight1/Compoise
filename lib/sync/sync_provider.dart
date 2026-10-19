/// Which cloud this device syncs through, and where its secrets live.
library;

import 'dart:convert';
import 'dart:typed_data';

import '../credential_store.dart';
import 'sync_engine.dart';
import 'sync_remote.dart';
import 'webdav_remote.dart';

enum SyncProviderKind { webdav, onedrive, huawei }

/// The non-secret connection settings, kept in `sync-provider.json`.
class SyncProviderConfig {
  const SyncProviderConfig({
    required this.kind,
    required this.deviceName,
    this.webdav,
    this.account,
  });

  final SyncProviderKind kind;

  /// Shown to other devices in the device list.
  final String deviceName;
  final WebDavSettings? webdav;

  /// Account label for display, for example the OneDrive e-mail address.
  final String? account;

  SyncProviderConfig copyWith({String? deviceName, String? account}) =>
      SyncProviderConfig(
        kind: kind,
        deviceName: deviceName ?? this.deviceName,
        webdav: webdav,
        account: account ?? this.account,
      );

  Map<String, dynamic> toJson() => {
    'format': 1,
    'kind': kind.name,
    'deviceName': deviceName,
    if (webdav != null) 'webdav': webdav!.toJson(),
    if (account != null) 'account': account,
  };

  static SyncProviderConfig? fromJson(Object? raw) {
    if (raw is! Map || raw['format'] != 1) return null;
    final kind = SyncProviderKind.values
        .where((value) => value.name == raw['kind'])
        .firstOrNull;
    final deviceName = raw['deviceName'];
    if (kind == null || deviceName is! String) return null;
    final webdav = WebDavSettings.fromJson(raw['webdav']);
    if (kind == SyncProviderKind.webdav && webdav == null) return null;
    final account = raw['account'];
    return SyncProviderConfig(
      kind: kind,
      deviceName: deviceName,
      webdav: webdav,
      account: account is String ? account : null,
    );
  }

  static SyncProviderConfig? decode(String? text) {
    if (text == null) return null;
    try {
      return fromJson(jsonDecode(text));
    } on FormatException {
      return null;
    }
  }

  String encode() => jsonEncode(toJson());
}

/// Builds the transport for [config]. [secret] is the provider secret from
/// secure storage: the WebDAV password, or an OAuth token bundle.
typedef SyncRemoteFactory =
    SyncRemote Function(SyncProviderConfig config, String secret);

SyncRemote defaultSyncRemoteFactory(SyncProviderConfig config, String secret) {
  switch (config.kind) {
    case SyncProviderKind.webdav:
      final settings = config.webdav!;
      return WebDavRemote(
        baseUrl: normalizeWebDavUrl(settings.url)!,
        username: settings.username,
        password: secret,
      );
    case SyncProviderKind.onedrive:
    case SyncProviderKind.huawei:
      throw UnsupportedError('${config.kind.name} is not available yet');
  }
}

/// Secure-storage entries for sync. Neither is ever written to a file.
class SyncSecrets {
  const SyncSecrets({required this.vaultKey, required this.provider});

  factory SyncSecrets.system() => const SyncSecrets(
    vaultKey: SystemCredentialStore(key: 'compoise-sync-vault-key'),
    provider: SystemCredentialStore(key: 'compoise-sync-provider-secret'),
  );

  /// The derived vault key, never the password.
  final CredentialStore vaultKey;

  /// WebDAV password or OAuth tokens.
  final CredentialStore provider;
}

/// [SyncKeyStore] over a [CredentialStore] entry holding base64.
class CredentialSyncKeyStore implements SyncKeyStore {
  const CredentialSyncKeyStore(this.store);

  final CredentialStore store;

  @override
  Future<Uint8List?> read() async {
    final text = await store.read();
    if (text == null || text.isEmpty) return null;
    try {
      return base64Decode(text);
    } on FormatException {
      return null;
    }
  }

  @override
  Future<void> write(Uint8List key) => store.write(base64Encode(key));

  @override
  Future<void> delete() => store.delete();
}
