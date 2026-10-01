import 'dart:io';

/// Files the native session loads from `<assetsRoot>/ncnn`.
///
/// The native side keeps these names fixed, so the deployment step and the
/// presence check must agree on exactly this list. WP17-I4 pins it in one place
/// so the Flutter check, the deployment script and the tests cannot drift.
const List<String> ocrModelFileNames = [
  'ppocrv5_dict.txt',
  'PP_OCRv5_mobile_det.ncnn.param',
  'PP_OCRv5_mobile_det.ncnn.bin',
  'PP_OCRv5_mobile_rec.ncnn.param',
  'PP_OCRv5_mobile_rec.ncnn.bin',
];

/// Absolute path of one model file for a given asset root.
String ocrModelPath(String assetsRoot, String name) => '$assetsRoot/ncnn/$name';

/// Returns the names that are missing, unreadable or empty. An empty list means
/// every file was opened and yielded at least one byte.
///
/// This is a readability check only: it does not validate model contents,
/// quality or licence, and it never downloads anything.
Future<List<String>> missingOcrModelFiles(String assetsRoot) async {
  final missing = <String>[];
  for (final name in ocrModelFileNames) {
    try {
      final handle = await File(ocrModelPath(assetsRoot, name)).open();
      try {
        if ((await handle.read(1)).isEmpty) missing.add(name);
      } finally {
        await handle.close();
      }
    } on FileSystemException {
      missing.add(name);
    }
  }
  return missing;
}
