// Locked plugin test seams redirect actual file IO only in the opt-in entry.
// ignore_for_file: invalid_use_of_visible_for_testing_member
import 'dart:io';
import 'package:flutter/services.dart';
// ignore: depend_on_referenced_packages
import 'package:path/path.dart' as p;
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
// ignore: depend_on_referenced_packages
import 'package:path_provider_windows/path_provider_windows.dart';
import 'package:shared_preferences/shared_preferences.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_windows/shared_preferences_windows.dart';

const d3Channel = MethodChannel('matrixflow/wp15_d3');

class _D3Paths extends PathProviderWindows {
  _D3Paths(this.root);
  final String root;
  @override
  Future<String> getPath(String folderID) async => root;
}

Future<String> d3Isolate(Map<String, Object?> native) async {
  if (!Platform.isWindows ||
      native['nativeGate'] != true ||
      native['isolatedMutex'] != true ||
      native['privateDesktop'] != true ||
      Platform.environment['WP15_D3_RUN'] != '1') {
    throw StateError('Native and runtime D3 gates are required before file IO');
  }
  final namespace = Platform.environment['WP15_D3_NAMESPACE'];
  final supplied = Platform.environment['WP15_D3_ROOT'];
  if (namespace == null ||
      supplied == null ||
      !RegExp(
        r'^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$',
      ).hasMatch(namespace) ||
      native['namespace'] != namespace ||
      native['root'] != supplied ||
      native['pid'] != pid) {
    throw StateError('Mismatched native/Dart isolation identity');
  }
  final actual = await Directory(supplied).resolveSymbolicLinks();
  final temp = await Directory.systemTemp.resolveSymbolicLinks();
  if (!p.equals(actual, p.normalize(p.absolute(supplied))) ||
      !p.equals(p.dirname(actual), temp) ||
      p.basename(actual) != 'wp15-d3-device-$namespace') {
    throw StateError('Refusing a noncanonical immediate OS-temp test root');
  }
  final paths = _D3Paths(actual);
  final support = await paths.getApplicationSupportPath();
  if (support == null || !p.isWithin(actual, support)) {
    throw StateError('Plugin data path escaped isolation');
  }
  PathProviderPlatform.instance = paths;
  SharedPreferences.resetStatic();
  SharedPreferencesStorePlatform.instance = SharedPreferencesWindows()
    ..pathProvider = paths;
  return actual;
}

Future<Map<String, Object?>> d3Native() async =>
    (await d3Channel.invokeMapMethod<String, Object?>('status'))!;
Future<void> d3Control(String method, [Object? argument]) async {
  if (await d3Channel.invokeMethod<bool>(method, argument) != true) {
    throw StateError('Native D3 control failed: $method');
  }
}
