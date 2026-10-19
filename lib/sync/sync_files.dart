/// Names and shapes of the files in a sync folder (docs/sync.md).
///
/// ```
/// vault.json          plain JSON: vault id, lineage, encryption parameters
/// dev-<deviceId>.cps  one envelope per device: its full merged state
/// ```
library;

import 'dart:convert';
import 'dart:typed_data';

import 'sync_crypto.dart';
import 'sync_state.dart';

const String syncAppId = 'compoise';
const int syncFormat = 1;
const String vaultFileName = 'vault.json';
const String _devicePrefix = 'dev-';
const String _deviceSuffix = '.cps';

/// The longest lineage a vault keeps. Older ids fall off; a device that has
/// been away for that many password changes has to join again.
const int maxLineage = 8;

final RegExp _idPattern = RegExp(r'^[a-z0-9]{8,64}$');

bool isValidSyncId(String id) => _idPattern.hasMatch(id);

String deviceFileName(String deviceId) {
  if (!isValidSyncId(deviceId)) throw ArgumentError('deviceId');
  return '$_devicePrefix$deviceId$_deviceSuffix';
}

/// Device id of a device file name, or null for any other file.
String? deviceIdOfFile(String name) {
  if (!name.startsWith(_devicePrefix) || !name.endsWith(_deviceSuffix)) {
    return null;
  }
  final id = name.substring(
    _devicePrefix.length,
    name.length - _deviceSuffix.length,
  );
  return isValidSyncId(id) ? id : null;
}

class SyncFileException implements Exception {
  const SyncFileException(this.message, {this.newerFormat = false});

  final String message;

  /// Written by a newer app version; updating this one may help.
  final bool newerFormat;

  @override
  String toString() => 'SyncFileException: $message';
}

Map<String, dynamic> _decodeObject(List<int> bytes) {
  final Object? json;
  try {
    json = jsonDecode(utf8.decode(bytes));
  } on FormatException {
    throw const SyncFileException('Not JSON');
  }
  if (json is! Map<String, dynamic>) {
    throw const SyncFileException('Not an object');
  }
  return json;
}

void _checkHeader(Map<String, dynamic> json, String kind) {
  if (json['app'] != syncAppId || json['kind'] != kind) {
    throw SyncFileException('Not a Compoise $kind file');
  }
  final format = json['format'];
  if (format is! int || format < 1) {
    throw const SyncFileException('Invalid format');
  }
  if (format > syncFormat) {
    throw SyncFileException('Format $format', newerFormat: true);
  }
}

/// The plain file that names a vault and says how to unlock it.
class SyncVault {
  const SyncVault({
    required this.vaultId,
    required this.createdAt,
    this.lineage = const [],
    this.kdf,
    this.check,
  });

  final String vaultId;
  final int createdAt;

  /// Earlier vault ids this vault continues, newest first. A device joined to
  /// one of them still holds a valid history and may carry on.
  final List<String> lineage;

  /// Present when the vault is encrypted.
  final KdfParams? kdf;
  final String? check;

  bool get encrypted => kdf != null;

  Map<String, dynamic> toJson() => {
    'app': syncAppId,
    'kind': 'vault',
    'format': syncFormat,
    'vaultId': vaultId,
    'createdAt': createdAt,
    'lineage': lineage,
    'encryption': kdf == null ? null : {'kdf': kdf!.toJson(), 'check': check},
  };

  Uint8List encode() => Uint8List.fromList(
    utf8.encode(const JsonEncoder.withIndent('  ').convert(toJson())),
  );

  static SyncVault decode(List<int> bytes) {
    final json = _decodeObject(bytes);
    _checkHeader(json, 'vault');
    final vaultId = json['vaultId'];
    final createdAt = json['createdAt'];
    final lineage = json['lineage'] ?? const [];
    if (vaultId is! String || !isValidSyncId(vaultId)) {
      throw const SyncFileException('Invalid vault id');
    }
    if (createdAt is! int) throw const SyncFileException('Invalid createdAt');
    if (lineage is! List ||
        lineage.any((id) => id is! String || !isValidSyncId(id))) {
      throw const SyncFileException('Invalid lineage');
    }
    final encryption = json['encryption'];
    KdfParams? kdf;
    String? check;
    if (encryption != null) {
      if (encryption is! Map || encryption['check'] is! String) {
        throw const SyncFileException('Invalid encryption');
      }
      try {
        kdf = KdfParams.fromJson(encryption['kdf']);
      } on SyncCryptoException catch (error) {
        throw SyncFileException(
          'Invalid key derivation',
          newerFormat: error.kind == SyncCryptoError.unsupported,
        );
      }
      check = encryption['check'] as String;
    }
    return SyncVault(
      vaultId: vaultId,
      createdAt: createdAt,
      lineage: [for (final id in lineage.take(maxLineage)) id as String],
      kdf: kdf,
      check: check,
    );
  }
}

class SyncDeviceInfo {
  const SyncDeviceInfo({
    required this.id,
    required this.name,
    required this.platform,
    required this.appVersion,
  });

  final String id;
  final String name;
  final String platform;
  final String appVersion;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'platform': platform,
    'appVersion': appVersion,
  };

  static String _text(Object? value, int max) {
    final text = value is String ? value.trim() : '';
    return text.length > max ? text.substring(0, max) : text;
  }

  static SyncDeviceInfo fromJson(Object? json) {
    if (json is! Map || json['id'] is! String) {
      throw const SyncFileException('Invalid device');
    }
    return SyncDeviceInfo(
      id: json['id'] as String,
      name: _text(json['name'], 80),
      platform: _text(json['platform'], 32),
      appVersion: _text(json['appVersion'], 32),
    );
  }
}

/// Content of one device file before it is sealed into an envelope.
class DevicePayload {
  const DevicePayload({
    required this.vaultId,
    required this.device,
    required this.writtenAt,
    required this.state,
  });

  final String vaultId;
  final SyncDeviceInfo device;
  final int writtenAt;
  final SyncState state;

  List<int> encodeJson({String? encodedState}) {
    final header = jsonEncode({
      'app': syncAppId,
      'kind': 'device',
      'format': syncFormat,
      'vaultId': vaultId,
      'device': device.toJson(),
      'writtenAt': writtenAt,
    });
    // Splice the state text in instead of encoding a multi-megabyte map twice.
    final stateJson = encodedState ?? state.encode();
    return utf8.encode(
      '${header.substring(0, header.length - 1)},"state":$stateJson}',
    );
  }

  static DevicePayload decodeJson(List<int> bytes) {
    final json = _decodeObject(bytes);
    _checkHeader(json, 'device');
    final vaultId = json['vaultId'];
    final writtenAt = json['writtenAt'];
    if (vaultId is! String || writtenAt is! int) {
      throw const SyncFileException('Invalid device file');
    }
    final SyncState state;
    try {
      state = SyncState.fromJson(json['state']);
    } on SyncFormatException catch (error) {
      throw SyncFileException(error.message);
    }
    return DevicePayload(
      vaultId: vaultId,
      device: SyncDeviceInfo.fromJson(json['device']),
      writtenAt: writtenAt,
      state: state,
    );
  }
}
