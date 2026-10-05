import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// Source Han Serif (Noto Serif SC), downloaded the first time someone
/// chooses the serif face. The file is SIL OFL 1.1; see
/// third_party/source-han-serif/OFL.txt. It is not packaged with the app.
class SongtiFonts {
  static const family = 'Noto Serif SC';
  static const fileName = 'NotoSerifSC-Regular.otf';
  static const approxMegabytes = 11;
  static const defaultMinBytes = 1024 * 1024;

  /// Same OFL file. The mainland mirror is tried first. unpkg and jsDelivr
  /// are the copies that answered from this network.
  static const urls = <String>[
    'https://unpkg.npmmirror.com/@electron-fonts/noto-serif-sc@1.2.0/fonts/NotoSerifSC-Regular.otf',
    'https://unpkg.com/@electron-fonts/noto-serif-sc@1.2.0/fonts/NotoSerifSC-Regular.otf',
    'https://cdn.jsdelivr.net/npm/@electron-fonts/noto-serif-sc@1.2.0/fonts/NotoSerifSC-Regular.otf',
  ];

  static bool loaded = false;

  /// Packaged copy of the SIL OFL. Written next to the downloaded font file.
  static const licenseAsset = 'assets/licenses/NotoSerifSC-OFL.txt';

  /// Test seam. Production leaves this null and uses the app support folder.
  static Future<Directory> Function()? directoryOverride;

  /// Test seam. Production leaves this null and registers the bytes.
  static Future<void> Function(Uint8List bytes)? loaderOverride;

  /// When set, [isInstalled] does not touch the disk. Widget tests need this:
  /// looking up the real app-support folder does not finish on the test clock.
  static bool? installedOverride;

  /// When set, the license file uses this text instead of [licenseAsset].
  static String? licenseTextOverride;

  static bool looksLikeFont(Uint8List bytes, {int minBytes = defaultMinBytes}) {
    if (bytes.length < 4 || bytes.length < minBytes) return false;
    final otto =
        bytes[0] == 0x4F &&
        bytes[1] == 0x54 &&
        bytes[2] == 0x54 &&
        bytes[3] == 0x4F;
    final ttf =
        bytes[0] == 0x00 &&
        bytes[1] == 0x01 &&
        bytes[2] == 0x00 &&
        bytes[3] == 0x00;
    final ttc =
        bytes[0] == 0x74 &&
        bytes[1] == 0x74 &&
        bytes[2] == 0x63 &&
        bytes[3] == 0x66;
    return otto || ttf || ttc;
  }

  static Future<bool> isInstalled() async {
    final forced = installedOverride;
    if (forced != null) return forced;
    try {
      final file = await _fontFile();
      // Sync checks: a widget test's fake clock does not flush real file
      // futures, so an awaited exists() there never finishes.
      if (!file.existsSync() || file.lengthSync() < defaultMinBytes) {
        return false;
      }
      final opened = file.openSync();
      try {
        final header = opened.readSync(4);
        return looksLikeFont(Uint8List.fromList(header), minBytes: 4);
      } finally {
        opened.closeSync();
      }
    } catch (_) {
      return false;
    }
  }

  static Future<void> ensureLoaded() async {
    if (loaded) return;
    try {
      final file = await _fontFile();
      if (!file.existsSync()) return;
      final bytes = file.readAsBytesSync();
      if (!looksLikeFont(bytes)) return;
      await _install(bytes);
      await _writeLicense(file.parent);
    } catch (_) {
      // A missing plugin or a bad file leaves the current face in place.
    }
  }

  static Future<void> download({
    http.Client? client,
    void Function(double? progress)? onProgress,
    int minBytes = defaultMinBytes,
  }) async {
    if (loaded && await isInstalled()) {
      await _writeLicense(await _fontsDir());
      return;
    }
    final ownClient = client == null;
    final httpClient = client ?? http.Client();
    Object? lastError;
    try {
      final fonts = await _fontsDir();
      final separator = Platform.pathSeparator;
      for (final url in urls) {
        final part = File('${fonts.path}$separator$fileName.part');
        try {
          if (await part.exists()) await part.delete();
          final request = http.Request('GET', Uri.parse(url));
          request.headers['User-Agent'] = 'Compoise';
          final response = await httpClient
              .send(request)
              .timeout(const Duration(seconds: 30));
          if (response.statusCode != 200) {
            lastError = SongtiDownloadException('HTTP ${response.statusCode}');
            continue;
          }
          final sink = part.openWrite();
          var received = 0;
          final total = response.contentLength;
          try {
            await for (final chunk in response.stream) {
              received += chunk.length;
              sink.add(chunk);
              onProgress?.call(
                total != null && total > 0 ? received / total : null,
              );
            }
          } finally {
            await sink.close();
          }
          final bytes = await part.readAsBytes();
          if (!looksLikeFont(bytes, minBytes: minBytes)) {
            await part.delete();
            lastError = SongtiDownloadException('not a font');
            continue;
          }
          await _install(bytes);
          final dest = File('${fonts.path}$separator$fileName');
          if (await dest.exists()) await dest.delete();
          await part.rename(dest.path);
          await _writeLicense(fonts);
          return;
        } catch (error) {
          lastError = error;
          if (await part.exists()) {
            try {
              await part.delete();
            } catch (_) {}
          }
        }
      }
      throw SongtiDownloadException(lastError?.toString() ?? 'download failed');
    } finally {
      if (ownClient) httpClient.close();
    }
  }

  static Future<Directory> _fontsDir() async {
    final root = directoryOverride != null
        ? await directoryOverride!()
        : await getApplicationSupportDirectory();
    final dir = Directory('${root.path}${Platform.pathSeparator}fonts');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  static Future<File> _fontFile() async {
    final dir = await _fontsDir();
    return File('${dir.path}${Platform.pathSeparator}$fileName');
  }

  static Future<void> _writeLicense(Directory fonts) async {
    try {
      final override = licenseTextOverride;
      final text = override ?? await rootBundle.loadString(licenseAsset);
      if (text.trim().isEmpty) return;
      final dest = File('${fonts.path}${Platform.pathSeparator}OFL.txt');
      dest.writeAsStringSync(text, flush: true);
    } catch (_) {
      // The same text also ships in the app license assets. A missing
      // asset must not throw away a font that already downloaded.
    }
  }

  static Future<void> _install(Uint8List bytes) async {
    if (loaderOverride != null) {
      await loaderOverride!(bytes);
      loaded = true;
      return;
    }
    if (loaded) return;
    final loader = FontLoader(family);
    loader.addFont(Future<ByteData>.value(ByteData.sublistView(bytes)));
    await loader.load();
    loaded = true;
  }
}

class SongtiDownloadException implements Exception {
  final String message;
  SongtiDownloadException(this.message);

  @override
  String toString() => message;
}

/// Loads a previously downloaded serif face before the themed app is built.
class SongtiWarmup extends StatefulWidget {
  final bool load;
  final WidgetBuilder builder;

  const SongtiWarmup({super.key, required this.load, required this.builder});

  @override
  State<SongtiWarmup> createState() => _SongtiWarmupState();
}

class _SongtiWarmupState extends State<SongtiWarmup> {
  @override
  void initState() {
    super.initState();
    _kick();
  }

  @override
  void didUpdateWidget(SongtiWarmup oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.load && !oldWidget.load) _kick();
  }

  Future<void> _kick() async {
    if (!widget.load || SongtiFonts.loaded) return;
    await SongtiFonts.ensureLoaded();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) => widget.builder(context);
}
