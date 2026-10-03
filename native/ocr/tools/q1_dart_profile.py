#!/usr/bin/env python3
"""Instrument private source copies for decode/isolate/native/draft RSS phases.

No production trace hooks; numbers only, opt-in builds. Use uninstrumented
q1_benchmark results for latency. Source/output must be different directories.
"""
import argparse
from pathlib import Path
import re
import shutil

from q1_benchmark import REPO

HELPER = '''
void _q1Trace(String stage, [int payload = 0]) {
  final fields = <String, int>{};
  for (final line in File('/proc/self/status').readAsLinesSync()) {
    for (final key in ['VmRSS', 'VmHWM', 'RssAnon', 'Threads']) {
      if (line.startsWith('$key:')) {
        fields[key] = int.parse(line.trim().split(RegExp(r'\\s+'))[1]);
      }
    }
  }
  stderr.writeln('Q1_TRACE stage=$stage pid=$pid time_us=${DateTime.now().microsecondsSinceEpoch} payload=$payload $fields');
}

'''


def instrument(path, changes, anchor):
    source = path.read_text(encoding="utf-8")
    assert source.count(anchor) == 1
    source = source.replace(anchor, HELPER + anchor)
    for needle, replacement in changes.items():
        assert source.count(needle) == 1, (path.name, needle)
        source = source.replace(needle, replacement)
    path.write_text(source, encoding="utf-8")


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--repo", required=True, type=Path)
    p.add_argument("--out", required=True, type=Path)
    p.add_argument("--harness", type=Path, default=REPO / "tool/wp17_q1_benchmark.dart")
    a = p.parse_args()
    if a.out.resolve() == REPO or REPO in a.out.resolve().parents or a.out.resolve() == a.repo.resolve(): p.error("external copy required")
    shutil.copytree(a.repo, a.out, dirs_exist_ok=True, symlinks=True,
                    ignore=shutil.ignore_patterns(".git", ".dart_tool", "build", "ephemeral", ".gradle", ".cxx", "local.properties"))
    shutil.copyfile(a.harness, a.out / "tool/wp17_q1_benchmark.dart")
    runtime = a.out / "lib/ocr/ocr_runtime.dart"
    instrument(runtime, {
        "  final library = DynamicLibrary.open": "  _q1Trace('isolate-enter');\n  final library = DynamicLibrary.open",
        "  final assetPtr = assetsRoot.toNativeUtf8();": "  _q1Trace('library-loaded');\n  final assetPtr = assetsRoot.toNativeUtf8();",
        "    session = create(assetPtr, threads);": "    session = create(assetPtr, threads);\n    _q1Trace('session-created');",
        "    final output = run(session, pathPtr);": "    final output = run(session, pathPtr);\n    _q1Trace('native-return');",
        "    if (session != nullptr) destroy(session);": "    if (session != nullptr) destroy(session);\n    _q1Trace('session-destroyed');",
    }, "OcrImageResult _failure(")
    capture = a.out / "lib/screenshot_import/screenshot_capture.dart"
    content = capture.read_text(encoding="utf-8")
    transfer = "(width ~/ 4) * height" if "gutterLuminance(" in content else "width * height * 4"
    instrument(capture, {
        "            _validatePngChunks(png);": "            _validatePngChunks(png);\n            _q1Trace('png-read', png.length);",
        "          originalBytes[id] = png;": "          originalBytes[id] = png;\n          _q1Trace('draft-adapted', originalBytes.values.fold<int>(0, (n, bytes) => n + bytes.length));",
        "  final codec = await ui.instantiateImageCodec(png);": "  _q1Trace('before-codec', png.length);\n  final codec = await ui.instantiateImageCodec(png);\n  _q1Trace('codec-created');",
        "    final frame = await codec.getNextFrame();": "    final frame = await codec.getNextFrame();\n    _q1Trace('frame-decoded');",
        "      if (pixels == null)": "      _q1Trace('raw-rgba', width * height * 4);\n      if (pixels == null)",
        "      disposed = true;": "      disposed = true;\n      _q1Trace('transfer-image-disposed', " + transfer + ");",
        "      return await Isolate.run(": "      final marks = await Isolate.run(",
        "    codec.dispose();": "    codec.dispose();\n    _q1Trace('codec-disposed');",
    }, "typedef ScreenshotPicker")
    source = capture.read_text(encoding="utf-8")
    source, count = re.subn(r'(      final marks = await Isolate.run\([\s\S]*?\n      \);)',
                           r"\1\n      _q1Trace('scan-return');\n      return marks;", source)
    assert count == 1
    capture.write_text(source, encoding="utf-8")
    print(a.out)


if __name__ == "__main__":
    main()
