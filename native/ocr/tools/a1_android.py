#!/usr/bin/env python3
"""Opt-in arm64 Android acceptance; all evidence/builds use an external root.

No argument starts a device or downloads models. Device enrollment must name an
already authorized dedicated device, its serial and current build fingerprint.
The diagnostic identity is refused if already installed. No production package,
global setting, log buffer, user image directory or existing app data is changed.
"""
from __future__ import annotations

import argparse
from contextlib import contextmanager
import ctypes
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import struct
import subprocess
import sys
import threading
import time
import uuid
import xml.etree.ElementTree as ET
import zipfile

sys.dont_write_bytecode = True
import stage_official_bundle as bundle

PACKAGE = "com.matrixflow.app.wp17i6"
BASELINE = "459f9a28cefdcac9196825b2d4ac70250dbf3b8d"
REPO = Path(__file__).resolve().parents[3]
SDK_HASHES = {
    "arm64-v8a": "ff736cecd9851452724f3cb1fc47c40d789f83a805ba5855cdcc91eb80c77870",
    "x86_64": "8507abea0095f6c61c6efd912fb24369bb1651ab31a2d4dce432c86a2c71c11a",
}
STB_SHA = "594c2fe35d49488b4382dbfaec8f98366defca819d916ac95becf3e75f4200b3"
FIXTURE_NAMES = [f"{i + 1:02d}-{language}.png" for i, language in
                 enumerate(["zh", "en", "ja"] * 3)] + ["10-corrupt.png"]
MARKERS = ["CANCEL_READY", "REVIEW_CANCEL_READY", "ACTIVE_CANCEL_READY", "SAVE_READY"]


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def save(path: Path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def private_root(path: Path) -> Path:
    root = path.resolve()
    if root == REPO or root.is_relative_to(REPO) or REPO.is_relative_to(root):
        raise ValueError("Use a separate external private root")
    if root.name != "martix-wp17-a1-private":
        raise ValueError("Private root must be named martix-wp17-a1-private")
    for directory in ("tmp", "logs", "artifacts", "runs"):
        (root / directory).mkdir(parents=True, exist_ok=True)
    return root


class Commands:
    def __init__(self, root: Path):
        self.root = root
        self.env = dict(os.environ, TEMP=str(root / "tmp"), TMP=str(root / "tmp"),
                        PUB_CACHE=str(root / "pub-cache"), GRADLE_USER_HOME=str(root / "gradle"),
                        PYTHONDONTWRITEBYTECODE="1", FLUTTER_SUPPRESS_ANALYTICS="true", CI="true")

    def run(self, args, *, cwd=None, timeout=60, check=True, log=None, input=None):
        arguments = list(map(str, args))
        started = time.monotonic()
        if log:
            logfile = self.root / "logs" / (log + ".log")
            with logfile.open("w", encoding="utf-8") as stream:
                process = subprocess.run(arguments, cwd=cwd, env=self.env, input=input,
                                         stdout=stream, stderr=subprocess.STDOUT, text=True,
                                         encoding="utf-8", errors="replace", timeout=timeout)
            output = logfile.read_text(encoding="utf-8", errors="replace")
        else:
            process = subprocess.run(arguments, cwd=cwd, env=self.env, input=input,
                                     capture_output=True, text=True, encoding="utf-8",
                                     errors="replace", timeout=timeout)
            output = process.stdout
        with (self.root / "logs/commands.jsonl").open("a", encoding="utf-8") as record:
            record.write(json.dumps({"argv": arguments, "cwd": str(cwd) if cwd else None,
                                     "exit": process.returncode,
                                     "elapsed_ms": round((time.monotonic() - started) * 1000)}) + "\n")
        if check and process.returncode:
            details = output if log else process.stderr
            raise RuntimeError(f"Command exited {process.returncode}: {arguments[:4]}\n{details[-1000:]}")
        return output


def inventory(command: Commands, adb: Path):
    raw = command.run([adb, "devices", "-l"])
    devices = []
    for row in raw.splitlines()[1:]:
        fields = row.split()
        if len(fields) < 2:
            continue
        data = {"serial": fields[0], "state": fields[1], "raw": row,
                "abi": None, "sdk": None, "fingerprint": None, "packages": None}
        if fields[1] == "device":
            prefix = [adb, "-s", fields[0], "shell"]
            for key, prop in (("abi", "ro.product.cpu.abilist"),
                              ("sdk", "ro.build.version.sdk"), ("fingerprint", "ro.build.fingerprint")):
                data[key] = command.run(prefix + ["getprop", prop]).strip()
            data["packages"] = command.run(prefix + ["pm", "list", "packages", "com.matrixflow.app"]).splitlines()
        devices.append(data)
    save(command.root / "logs/device-inventory.json", {"devices": devices})
    return devices


def authorize(device: dict, enrollment: dict):
    if device["state"] != "device":
        raise ValueError("Device is offline or unavailable")
    if "arm64-v8a" not in (device.get("abi") or "").split(","):
        raise ValueError("arm64-v8a execution required; x86_64 cannot substitute")
    if int(device.get("sdk") or 0) < 23:
        raise ValueError("Device API below the application minimum 23")
    if (enrollment.get("schema") != 1 or enrollment.get("scope") != "WP17-A1"
            or enrollment.get("kind") not in ("dedicated-test-device", "owned-avd")
            or enrollment.get("serial") != device["serial"]
            or not device.get("fingerprint")
            or enrollment.get("fingerprint") != device["fingerprint"]):
        raise ValueError("Explicit dedicated-device enrollment must match actual identity")
    if any(line.strip() == "package:" + PACKAGE for line in device.get("packages") or []):
        raise ValueError("Diagnostic package already exists; ownership cannot be inferred")


@contextmanager
def device_lease(serial: str):
    """Cross-process Windows lease. Integration must share this exact mutex."""
    if os.name != "nt":
        raise RuntimeError("This host driver requires Windows device ownership locking")
    name = "Local\\MatrixFlow-WP17-device-" + re.sub(r"[^a-zA-Z0-9_-]", "_", serial)
    kernel = ctypes.WinDLL("kernel32", use_last_error=True)
    kernel.CreateMutexW.argtypes = [ctypes.c_void_p, ctypes.c_bool, ctypes.c_wchar_p]
    kernel.CreateMutexW.restype = ctypes.c_void_p
    kernel.WaitForSingleObject.argtypes = [ctypes.c_void_p, ctypes.c_uint32]
    kernel.ReleaseMutex.argtypes = [ctypes.c_void_p]
    kernel.CloseHandle.argtypes = [ctypes.c_void_p]
    handle = kernel.CreateMutexW(None, False, name)
    if not handle:
        raise ctypes.WinError(ctypes.get_last_error())
    acquired = False
    try:
        state = kernel.WaitForSingleObject(handle, 0)
        if state != 0:  # Abandoned mutex also requires an ownership audit.
            raise RuntimeError("Device lease busy/abandoned; do not take over another run")
        acquired = True
        yield name
    finally:
        if acquired:
            kernel.ReleaseMutex(handle)
        kernel.CloseHandle(handle)


def parse_memory(meminfo: str, status: str) -> dict:
    def number(pattern, text):
        match = re.search(pattern, text, re.M)
        return int(match.group(1)) if match else None
    # SUMMARY values are PSS, never Java/native RSS. Android 23 has no
    # App Summary: use the first Pss Total column of its named heap rows.
    java = number(r"^\s*Java Heap:\s*(\d+)", meminfo)
    native = number(r"^\s*Native Heap:\s*(\d+)", meminfo)
    if java is None:
        dalvik = number(r"^\s*Dalvik Heap\s+(\d+)", meminfo)
        other = number(r"^\s*Dalvik Other\s+(\d+)", meminfo)
        java = None if dalvik is None else dalvik + (other or 0)
    if native is None:
        native = number(r"^\s*Native Heap\s+(\d+)", meminfo)
    total = number(r"TOTAL PSS:\s*(\d+)", meminfo)
    summary = meminfo.split("App Summary", 1)[-1] if "App Summary" in meminfo else ""
    def heap_rss(name):
        if not re.search(r"Rss\s*\(\s*KB\s*\)", summary, re.I):
            return None
        return number(r"^\s*" + name + r" Heap:\s*\d+\s+(\d+)\s*$", summary)
    return {"java_heap_pss_kib": java, "native_heap_pss_kib": native,
            "java_heap_rss_kib": heap_rss("Java"), "native_heap_rss_kib": heap_rss("Native"),
            "process_pss_kib": total if total is not None else number(r"^\s*TOTAL\s+(\d+)", meminfo),
            "process_rss_kib": number(r"^VmRSS:\s*(\d+)", status),
            "process_hwm_kib": number(r"^VmHWM:\s*(\d+)", status)}


def validate_flow(first: dict, second: dict):
    for phase, doc in (("import", first), ("reopen", second)):
        if (doc.get("phase") != phase or doc.get("passed") is not True
                or doc.get("exit_intent") != 0 or doc.get("failures")
                or doc.get("identity") != PACKAGE or not isinstance(doc.get("pid"), int)):
            raise ValueError(f"Incomplete/failed {phase} application report")
    if first["pid"] == second["pid"] or not second.get("independent_disk_reopen"):
        raise ValueError("Reopen must be a second independent process")
    if first.get("snapshot") is None or first["snapshot"] != second.get("snapshot"):
        raise ValueError("Full persisted snapshot differs")
    if not first.get("real_picker") or not first.get("real_ocr") or first.get("temporary_pngs") != 0:
        raise ValueError("Real SAF/native/cleanup evidence required")
    cases = {case["case"]: case for case in first.get("cases", [])}
    for name in ("picker-cancel", "review-cancel", "active-cancel-recovery", "failed-save-retry"):
        if name not in cases:
            raise ValueError("Missing flow evidence: " + name)
    for name in ("picker-cancel", "review-cancel", "active-cancel-recovery"):
        if cases[name].get("store_writer_calls") != 0:
            raise ValueError("Cancellation must perform zero Store writes")
    if (cases["review-cancel"].get("images") != 10
            or cases["failed-save-retry"].get("images") != 10
            or cases["failed-save-retry"].get("successful_pointers") != 1):
        raise ValueError("Ten-image repeat and exactly one successful retry required")
    retry = cases["failed-save-retry"]
    if (retry.get("items") != 24 or retry.get("roots") != 18 or retry.get("completed") != 6
            or retry.get("retry_stable_ids") is not True
            or retry.get("failed_save_preserved_review") is not True
            or retry.get("date_text_only_in_notes") is not True
            or cases["review-cancel"].get("unconfirmed_submit_disabled") is not True
            or cases["review-cancel"].get("failed_images") != 1
            or cases["active-cancel-recovery"].get("cancelled") is not True):
        raise ValueError("Incomplete review/transaction/date/cancellation assertions")
    measurements = {m["case"]: m for m in first.get("measurements", [])}
    if ("native-cold-first-call" not in measurements or "native-hot-recovery" not in measurements
            or measurements.get("missing-dictionary-bad-png-recovery", {}).get("passed") is not True):
        raise ValueError("Missing real native boundary/cold/hot evidence")


def memory_peaks(samples: list[dict]) -> dict:
    keys = ("java_heap_pss_kib", "native_heap_pss_kib", "java_heap_rss_kib", "native_heap_rss_kib",
            "process_pss_kib", "process_rss_kib", "process_hwm_kib")
    return {key: max(values) if (values := [s[key] for s in samples if s.get(key) is not None]) else None
            for key in keys}


def assert_unforced_completion(raw_log: str, process: int):
    for line in raw_log.splitlines():
        own_pid = re.search(r"\s" + str(process) + r"\s+\d+\s", line)
        killed_pid = re.search(r"\bKilling\s+" + str(process) + r"[:\s]", line)
        if ((own_pid and re.search(r"Fatal signal|FATAL EXCEPTION|WP17_A1_REPORT_FAILED", line))
                or killed_pid or ("Force stopping " + PACKAGE in line)):
            raise ValueError("Forced/crashed application completion cannot pass: " + line)


def parse_smoke(raw: str, names: list[str], expected_exit: int, expected_errors: list[str | None]):
    # API 23 shell exit propagation is unreliable: require the exit sentinel
    # written by the same remote shell after waiting for the real executable.
    code = re.findall(r"^A1_RC=(\d+)\s*$", raw, re.M)
    if code != [str(expected_exit)]:
        raise ValueError("Native executable failed/terminated or exit sentinel missing")
    values = []
    for line in raw.splitlines():
        try:
            value = json.loads(line)
        except ValueError:
            continue
        if isinstance(value, dict):
            values.append(value)
    if len(values) != len(names) + 1 or "summary" not in values[-1]:
        raise ValueError("Incomplete native results")
    summary = values[-1]["summary"]
    if summary.get("images") != len(names) or summary.get("succeeded") != expected_errors.count(None):
        raise ValueError("Native success/error count differs")
    reference = json.loads((REPO / "docs/evidence/wp17r2/results/win/raw/ncnn-cpu-t4/all.json").read_text(encoding="utf-8"))["images"]
    golden = {Path(image["path"].replace("\\", "/")).stem: image for image in reference}
    for name, actual, error in zip(names, values, expected_errors):
        if error is not None:
            if error not in actual.get("error", "") or actual.get("lines") != []:
                raise ValueError("Native rejection differs: " + name)
            continue
        expected = golden[name]
        if (actual.get("error") != "" or actual.get("width") != expected["width"]
                or actual.get("height") != expected["height"]
                or len(actual.get("lines", [])) != len(expected["lines"])):
            raise ValueError("Native R2 dimensions/lines/error differ: " + name)
        for line, target in zip(actual["lines"], expected["lines"]):
            if line["text"] != target["text"] or len(line["box"]) != 4 or any(
                    abs(a - b) > 1 for a, b in zip(line["box"], target["box"])):
                raise ValueError("Native R2 text/geometry differs: " + name)
    return {"exit": expected_exit, "summary": summary, "r2_text_geometry_matched": True}


def fixtures(root: Path) -> dict:
    output = root / "fixtures"
    output.mkdir(exist_ok=True)
    images = REPO / "docs/evidence/wp17r2/samples/images"
    for i, language in enumerate(["zh", "en", "ja"] * 3):
        shutil.copyfile(images / (language + "_light_base.png"), output / FIXTURE_NAMES[i])
    (output / FIXTURE_NAMES[-1]).write_bytes(b"not a png")
    records = {}
    total_bytes = total_pixels = 0
    for path in sorted(output.glob("*.png")):
        data = path.read_bytes()
        width, height = struct.unpack(">II", data[16:24]) if data[:8] == b"\x89PNG\r\n\x1a\n" else (0, 0)
        if len(data) > 16 * 1024 * 1024 or width > 4096 or height > 8192 or width * height > 12 * 1024 * 1024:
            raise ValueError("Fixture exceeds existing per-image budget")
        records[path.name] = {"sha256": sha(path), "bytes": len(data), "width": width, "height": height}
        total_bytes += len(data)
        total_pixels += width * height
    if sorted(records) != FIXTURE_NAMES or total_bytes > 48 * 1024 * 1024 or total_pixels > 24 * 1024 * 1024:
        raise ValueError("Ten fixtures must fit existing batch budgets")
    result = {"files": records, "total_bytes": total_bytes, "total_pixels": total_pixels,
              "source": "unchanged R2 synthetic PNGs; each language repeated three times; one bad PNG"}
    save(root / "logs/fixtures.json", result)
    return result


def elf_facts(path: Path):
    data = path.read_bytes()
    if data[:6] != b"\x7fELF\x02\x01" or struct.unpack("<H", data[18:20])[0] != 183:
        raise ValueError("Expected little-endian ELF64 AArch64: " + str(path))
    return {"bytes": len(data), "sha256": sha(path), "machine": "AArch64", "class": "ELF64"}


def private_flutter(root: Path, source: Path) -> Path:
    expected = json.loads((REPO / "toolchain.json").read_text())["verified"]
    copied = root / "flutter"
    for sdk in (source.resolve(), copied):
        actual = json.loads((sdk / "bin/cache/flutter.version.json").read_text())
        for key, field in (("flutterVersion", "flutterVersion"), ("dartVersion", "dartSdkVersion"),
                           ("revision", "frameworkRevision"), ("engineRevision", "engineRevision")):
            if expected[key] != actual[field]:
                raise ValueError("Pinned input/private Flutter SDK mismatch: " + key)
    return copied


def normal_build(args, command: Commands):
    root, mirror = command.root, command.root / "repo"
    flutter = private_flutter(root, args.flutter)
    properties = mirror / "android/local.properties"
    old = properties.read_bytes() if properties.exists() else None
    try:
        properties.write_text("sdk.dir=" + args.sdk.resolve().as_posix() + "\nflutter.sdk=" +
                              flutter.as_posix() + "\n", encoding="utf-8")
        command.run([flutter / "bin/flutter.bat", "build", "apk", "--debug", "--no-pub",
                     "--target-platform=android-arm64"], cwd=mirror, timeout=1800, log="build-normal")
        apk = mirror / "build/app/outputs/flutter-apk/app-debug.apk"
        aapt = sorted((args.sdk / "build-tools").glob("*/aapt.exe"))[-1]
        facts = command.run([aapt, "dump", "badging", apk], log="normal-apk-facts")
        if not re.search(r"^package: name='com\.matrixflow\.app'", facts, re.M):
            raise ValueError("Default identity changed")
        with zipfile.ZipFile(apk) as archive:
            if any("matrixflow_ocr" in name or name.startswith("assets/wp17-ocr/") for name in archive.namelist()):
                raise ValueError("Default application unexpectedly includes OCR assets/library")
        target = root / "artifacts/wp17-a1-normal-build-only.apk"
        shutil.copyfile(apk, target)
        save(root / "logs/normal-apk.json", {"package": "com.matrixflow.app", "installed": False,
                                            "default_main": True, "ocr_absent": True,
                                            "sha256": sha(target), "bytes": target.stat().st_size})
    finally:
        if old is None:
            properties.unlink(missing_ok=True)
        else:
            properties.write_bytes(old)


def build(args, command: Commands):
    root = command.root
    sdk, flutter, ndk = args.sdk.resolve(), private_flutter(root, args.flutter), args.ndk.resolve()
    assets = root / "assets"
    for abi, digest in SDK_HASHES.items():
        bundle.verify(assets / f"ncnn-android-{abi}/install/lib/libncnn.a", digest, abi)
    bundle.verify(assets / "third_party/stb_image.h", STB_SHA, "stb")
    manifest = bundle.stage(root / "official-deploy", root / "packaged-assets",
                            json.loads(bundle.LOCK_PATH.read_text()))
    native = {}
    readelf = ndk / "toolchains/llvm/prebuilt/windows-x86_64/bin/llvm-readelf.exe"
    for mode in ("Debug", "Release"):
        out = root / "native" / mode
        command.run(["cmake", "-S", REPO / "native/ocr", "-B", out, "-G", "Ninja",
                     "-DCMAKE_TOOLCHAIN_FILE=" + str(ndk / "build/cmake/android.toolchain.cmake"),
                     "-DANDROID_ABI=arm64-v8a", "-DANDROID_PLATFORM=android-23",
                     "-DANDROID_STL=c++_static", "-DCMAKE_BUILD_TYPE=" + mode,
                     "-DWP17_NCNN_ROOT=" + assets.as_posix(),
                     "-DWP17_STB_DIR=" + (assets / "third_party").as_posix(),
                     "-DWP17_OCR_BUILD_SMOKE=ON"], timeout=120, log="native-" + mode + "-configure")
        command.run(["cmake", "--build", out, "--parallel", "2"], timeout=600, log="native-" + mode + "-build")
        library = out / "libmatrixflow_ocr.so"
        facts = elf_facts(library)
        details = command.run([readelf, "-h", "-n", "-d", "--dyn-syms", library], log="elf-" + mode)
        for symbol in ("mf_ocr_create", "mf_ocr_run_file", "mf_ocr_destroy", "mf_ocr_free"):
            if not re.search(r"GLOBAL\s+DEFAULT\s+\d+\s+" + symbol + r"\b", details):
                raise ValueError("Missing C ABI export: " + symbol)
        facts.update({"configured_api": 23, "runtime_api23_verified": False,
                      "needed": re.findall(r"Shared library: \[([^\]]+)\]", details),
                      "smoke": elf_facts(out / "matrixflow_ocr_smoke")})
        native[mode] = facts
    save(root / "logs/native-builds.json", native)
    # The caller prepares a private source mirror/pub/Gradle caches. Copy only
    # this package's new entry into it; all ordinary product sources stay fixed.
    mirror = root / "repo"
    if sha(mirror / "pubspec.lock") != sha(REPO / "pubspec.lock"):
        raise ValueError("Private mirror lock differs")
    shutil.copyfile(REPO / "test/wp17_a1_device_test.dart", mirror / "test/wp17_a1_device_test.dart")
    properties = mirror / "android/local.properties"
    old = properties.read_bytes() if properties.exists() else None
    try:
        properties.write_text("\n".join([
            "sdk.dir=" + sdk.as_posix(), "flutter.sdk=" + flutter.as_posix(),
            "wp17OcrValidation=true", "wp17OcrModels=" + (root / "packaged-assets").as_posix(),
            "wp17OcrNcnnRoot=" + assets.as_posix(), "wp17OcrStbDir=" + (assets / "third_party").as_posix()
        ]) + "\n", encoding="utf-8")
        command.run([flutter / "bin/flutter.bat", "build", "apk", "--debug", "--no-pub",
                     "--target-platform=android-arm64", "--target=test/wp17_a1_device_test.dart",
                     "--dart-define=WP17_A1_DEVICE=true"], cwd=mirror, timeout=1800, log="build-probe")
        apk = mirror / "build/app/outputs/flutter-apk/app-debug.apk"
        aapt = sorted((sdk / "build-tools").glob("*/aapt.exe"))[-1]
        facts = command.run([aapt, "dump", "badging", apk], log="apk-facts")
        if not re.search(r"^package: name='" + re.escape(PACKAGE) + "'", facts, re.M) or "sdkVersion:'23'" not in facts:
            raise ValueError("Private APK identity/minimum API mismatch")
        with zipfile.ZipFile(apk) as archive:
            for name, record in manifest["files"].items():
                data = archive.read("assets/wp17-ocr/" + name)
                if len(data) != record["bytes"] or hashlib.sha256(data).hexdigest() != record["sha256"]:
                    raise ValueError("APK model/licence mismatch: " + name)
            if json.loads(archive.read("assets/wp17-ocr/bundle-manifest.json")) != manifest:
                raise ValueError("APK bundle manifest differs")
            data = archive.read("lib/arm64-v8a/libmatrixflow_ocr.so")
            if data[:6] != b"\x7fELF\x02\x01" or struct.unpack("<H", data[18:20])[0] != 183:
                raise ValueError("APK OCR library is not AArch64")
            packaged_native = {"bytes": len(data), "sha256": hashlib.sha256(data).hexdigest()}
        destination = root / "artifacts/wp17-a1-arm64-probe.apk"
        shutil.copyfile(apk, destination)
        save(root / "logs/apk.json", {"package": PACKAGE, "min_sdk": 23,
                                      "sha256": sha(destination), "bytes": destination.stat().st_size,
                                      "native": packaged_native, "official_manifest": manifest})
    finally:
        if old is None:
            properties.unlink(missing_ok=True)
        else:
            properties.write_bytes(old)
    fixtures(root)


class Android:
    def __init__(self, command: Commands, adb: Path, serial: str, run: Path):
        self.command, self.run = command, run
        self.prefix = [adb, "-s", serial]
        self.token = "WP17-A1-" + run.name
        self.remote = "/sdcard/Download/" + self.token
        self.remote_ui = "/data/local/tmp/" + self.token + ".xml"
        self.remote_native = "/data/local/tmp/" + self.token
        self.support = "files"  # Android path_provider application support = filesDir.

    def adb(self, *args, check=True):
        return self.command.run(self.prefix + list(args), timeout=30, check=check)

    def pid(self):
        rows = self.adb("shell", "ps").splitlines()
        matching = [r.split() for r in rows if r.split() and r.split()[-1] == PACKAGE]
        if len(matching) > 1:
            raise RuntimeError("Ambiguous app process")
        return int(matching[0][1]) if matching else None

    def report(self, phase):
        raw = self.adb("shell", "run-as", PACKAGE, "cat", f"{self.support}/a1-flow-{phase}.json", check=False)
        try:
            return json.loads(raw)
        except ValueError:
            return None

    def nodes(self):
        self.adb("shell", "uiautomator", "dump", self.remote_ui)
        raw = self.adb("shell", "cat", self.remote_ui)
        (self.run / "picker-last.xml").write_text(raw, encoding="utf-8")
        return list(ET.fromstring(raw).iter("node"))

    def tap(self, node, long=False):
        bounds = list(map(int, re.findall(r"\d+", node.attrib["bounds"])))
        x, y = str((bounds[0] + bounds[2]) // 2), str((bounds[1] + bounds[3]) // 2)
        self.adb("shell", "input", *( ["swipe", x, y, x, y, "1000"] if long else ["tap", x, y]))

    def choose(self, cancel, sequence):
        deadline = time.monotonic() + 60
        while time.monotonic() < deadline:
            nodes = self.nodes()
            if any("documentsui" in n.attrib.get("package", "") for n in nodes):
                break
            time.sleep(.3)
        else:
            raise RuntimeError("Production DocumentsUI did not open")
        if cancel:
            self.adb("shell", "input", "keyevent", "4")
            save(self.run / f"picker-{sequence}.json", {"cancelled_real_dialog": True})
            return
        # Navigate actual DocumentsUI. Never provide synthetic result intents.
        # Fail on an unknown UI rather than scan a user gallery or select extra files.
        for _ in range(30):
            nodes = self.nodes()
            texts = {n.attrib.get("text"): n for n in nodes if n.attrib.get("text")}
            desc = {n.attrib.get("content-desc"): n for n in nodes if n.attrib.get("content-desc")}
            if self.token in texts and any(name in texts for name in FIXTURE_NAMES):
                break
            candidates = [self.token, "Download", "Downloads", "Show internal storage", "Show SD card", "Internal storage"]
            found = next((texts[name] for name in candidates if name in texts), None)
            if found is not None:
                self.tap(found)
            elif "Show roots" in desc:
                self.tap(desc["Show roots"])
            elif "More options" in desc:
                self.tap(desc["More options"])
            else:
                raise RuntimeError("Dedicated synthetic directory not visible in this DocumentsUI")
            time.sleep(.3)
        else:
            raise RuntimeError("Picker directory navigation timed out")
        for index, name in enumerate(FIXTURE_NAMES):
            # A ten-row list can scroll. Search the actual rows, bounded to the
            # already entered dedicated folder; reset to top for each search.
            found = None
            for _ in range(10):
                rows = self.nodes()
                found = next((n for n in rows if n.attrib.get("text") == name), None)
                if found is not None:
                    break
                lists = [n for n in rows if n.attrib.get("scrollable") == "true"]
                if not lists:
                    break
                bounds = list(map(int, re.findall(r"\d+", lists[-1].attrib["bounds"])))
                x = str((bounds[0] + bounds[2]) // 2)
                self.adb("shell", "input", "swipe", x, str(bounds[3] - 40), x, str(bounds[1] + 40), "350")
            if found is None:
                raise RuntimeError("Missing real PNG row: " + name)
            self.tap(found, long=index == 0)
        nodes = self.nodes()
        actions = [n for n in nodes if n.attrib.get("text", "").upper() in ("OPEN", "SELECT")
                   or n.attrib.get("content-desc", "").upper() in ("OPEN", "SELECT")]
        if not actions:
            raise RuntimeError("Missing real multi-select confirmation")
        shutil.copyfile(self.run / "picker-last.xml", self.run / f"picker-{sequence}-selected.xml")
        self.tap(actions[-1])
        save(self.run / f"picker-{sequence}.json", {"selected_real_rows": FIXTURE_NAMES,
                                                   "directory": self.remote, "real_saf": True})

    def native_probes(self):
        root = self.command.root
        self.adb("shell", "mkdir", "-p", self.remote_native)
        self.adb("push", root / "official-deploy", self.remote_native + "/assets")
        results = {}
        good_paths = [self.remote + "/" + name for name in FIXTURE_NAMES[:-1]]
        good_names = [language + "_light_base" for language in ["zh", "en", "ja"] * 3]
        reference = [good_paths[0], *good_paths]  # Ten valid images, existing budgets.
        reference_names = [good_names[0], *good_names]
        for mode in ("Debug", "Release"):
            directory = self.remote_native + "/" + mode
            self.adb("shell", "mkdir", "-p", directory)
            for filename in ("libmatrixflow_ocr.so", "matrixflow_ocr_smoke"):
                self.adb("push", root / "native" / mode / filename, directory + "/" + filename)
            self.adb("shell", "chmod", "700", directory + "/matrixflow_ocr_smoke")
            stages = [
                ("cold1", good_paths[:1], good_names[:1], [None], 0, self.remote_native + "/assets"),
                ("repeated10", reference * 3, reference_names * 3, [None] * 30, 0, self.remote_native + "/assets"),
                ("bad-png-recovery", [self.remote + "/10-corrupt.png", good_paths[0]],
                 ["bad", good_names[0]], ["PNG header decode failed", None], 4, self.remote_native + "/assets"),
                ("missing-dictionary", good_paths[:1], good_names[:1], ["cannot read dict"], 4,
                 self.remote_native + "/missing-dictionary"),
            ]
            results[mode] = {}
            for label, paths, names, errors, expected_exit, assets in stages:
                invocation = (f"LD_LIBRARY_PATH={directory} {directory}/matrixflow_ocr_smoke {assets} "
                              + " ".join(paths) + "; a1_rc=$?; printf '\\nA1_RC=%s\\n' \"$a1_rc\"")
                started = time.monotonic()
                raw = self.command.run(self.prefix + ["shell", invocation], timeout=300)
                (self.run / f"native-{mode}-{label}.log").write_text(raw, encoding="utf-8")
                result = parse_smoke(raw, names, expected_exit, errors)
                result["host_wall_ms"] = round((time.monotonic() - started) * 1000)
                result["timing"] = "summary excludes model load; host wall includes fresh process/model/ADB; repeated10 reuses one native session"
                results[mode][label] = result
        save(self.run / "native-probes.json", results)

    def wait_phase(self, phase):
        markers_seen, observed_pid = set(), None
        stage = "launch"
        started = time.monotonic()
        deadline = started + 900
        # No logcat -c: another package's evidence buffer is never cleared.
        stamp = self.adb("shell", "date '+%m-%d %H:%M:%S.000'").strip()
        self.adb("shell", "am", "start", "-n", PACKAGE + "/com.matrixflow.matrixflow_native.MainActivity")
        samples, stop = [], threading.Event()
        def sample():
            while not stop.is_set():
                try:
                    process = self.pid()
                    if process:
                        memory = self.adb("shell", "dumpsys", "meminfo", str(process))
                        status = self.adb("shell", "run-as", PACKAGE, "cat", f"/proc/{process}/status", check=False)
                        samples.append({"pid": process, "elapsed_ms": round((time.monotonic() - started) * 1000),
                                        "stage": stage,
                                        **parse_memory(memory, status), "raw_meminfo": memory, "raw_status": status})
                except (RuntimeError, subprocess.SubprocessError) as error:
                    samples.append({"sampling_error": str(error)})
                stop.wait(.25)
        sampler = threading.Thread(target=sample, daemon=True)
        sampler.start()
        report = None
        try:
            while time.monotonic() < deadline:
                process = self.pid()
                if process:
                    if observed_pid is not None and observed_pid != process:
                        raise RuntimeError("Application restarted unexpectedly during phase")
                    observed_pid = process
                    logs = self.adb("logcat", "-d", "-v", "threadtime", "-T", stamp)
                    # Match the actual application PID, excluding stale runs/other apps.
                    own = "\n".join(line for line in logs.splitlines()
                                    if re.search(r"\s" + str(process) + r"\s+\d+\s", line))
                    (self.run / f"application-{phase}.log").write_text(own, encoding="utf-8")
                    if phase == "import":
                        for index, marker in enumerate(MARKERS):
                            if "WP17_A1_" + marker in own and marker not in markers_seen:
                                stage = marker.lower()
                                self.choose(index == 0, index + 1)
                                markers_seen.add(marker)
                candidate = self.report(phase)
                if candidate:
                    report = candidate
                    if report.get("passed") is not True:
                        raise RuntimeError("Application suite failed")
                if observed_pid is not None and process is None:
                    if report is None:
                        raise RuntimeError("App exited without a completed suite report")
                    if report.get("pid") != observed_pid:
                        raise RuntimeError("Report PID differs from observed app")
                    if phase == "import" and len(markers_seen) != 4:
                        raise RuntimeError("Missing real picker phases")
                    final_log = self.adb("logcat", "-d", "-v", "threadtime", "-T", stamp)
                    assert_unforced_completion(final_log, observed_pid)
                    save(self.run / f"flow-{phase}.json", report)
                    save(self.run / f"process-{phase}.json", {
                        "pid": observed_pid, "suite_passed": report["passed"],
                        "exit_intent": report.get("exit_intent"), "host_terminated": False,
                        "natural_process_disappearance": True,
                        "os_exit_code": None,  # Android am is not waitpid.
                        "elapsed_ms": round((time.monotonic() - started) * 1000)})
                    return report
                time.sleep(.25)
            raise TimeoutError("Application phase timed out; cannot count as passed")
        finally:
            stop.set()
            sampler.join(timeout=35)
            if sampler.is_alive():
                raise RuntimeError("Memory sampler did not stop")
            save(self.run / f"memory-{phase}.json", {"samples": samples,
                "sampled_peaks": memory_peaks(samples),
                "stage_peaks": {name: memory_peaks([s for s in samples if s.get("stage") == name])
                                for name in sorted({s["stage"] for s in samples if "stage" in s})},
                "unit": "KiB", "sampling_interval_ms": 250,
                "notes": "stages include picker/review waits; sampled Java/native PSS; whole-process RSS/PSS; HWM is cumulative, not a reset per-batch peak; short peaks may be missed"})


def accept(args, command: Commands):
    devices = inventory(command, args.adb)
    selected = [d for d in devices if d["serial"] == args.serial]
    if len(selected) != 1:
        raise ValueError("Requested device absent")
    enrollment = json.loads(args.enrollment.read_text(encoding="utf-8"))
    authorize(selected[0], enrollment)
    apk = command.root / "artifacts/wp17-a1-arm64-probe.apk"
    artifact = json.loads((command.root / "logs/apk.json").read_text())
    if artifact["package"] != PACKAGE or artifact["sha256"] != sha(apk):
        raise ValueError("Built diagnostic APK facts/hash mismatch")
    manifest = bundle.validate(command.root / "official-deploy", json.loads(bundle.LOCK_PATH.read_text()))
    if manifest != artifact["official_manifest"]:
        raise ValueError("Runtime deployment differs from verified APK")
    native = json.loads((command.root / "logs/native-builds.json").read_text())
    for mode, facts in native.items():
        if facts["sha256"] != sha(command.root / "native" / mode / "libmatrixflow_ocr.so") or facts["smoke"]["sha256"] != sha(
                command.root / "native" / mode / "matrixflow_ocr_smoke"):
            raise ValueError("Native probe changed since build")
    source = fixtures(command.root)
    run = command.root / "runs" / ("run-" + uuid.uuid4().hex)
    run.mkdir()
    host = {"passed": False, "device": selected[0], "baseline": BASELINE,
            "apk_sha256": sha(apk), "arm64_execution": False}
    installed = False
    android = Android(command, args.adb, args.serial, run)
    with device_lease(args.serial) as lease:
        host["device_lease"] = lease
        try:
            # Repeat ownership check under the device lease before mutation.
            fresh = [d for d in inventory(command, args.adb) if d["serial"] == args.serial]
            if len(fresh) != 1:
                raise ValueError("Device disappeared before ownership check")
            authorize(fresh[0], enrollment)
            android.adb("install", "-t", apk)
            installed = True
            android.adb("shell", "mkdir", "-p", android.remote)
            for name in FIXTURE_NAMES:
                android.adb("push", command.root / "fixtures" / name, android.remote + "/" + name)
            android.native_probes()
            android.adb("shell", "run-as", PACKAGE, "mkdir", "-p", android.support)
            # Stream the unchanged synthetic PNG through stdin directly into
            # this package's sandbox; no broad storage permission is requested.
            subprocess.run(android.prefix + ["shell", "run-as", PACKAGE, "sh", "-c",
                           "'cat > files/a1-probe.png'"],
                           input=(command.root / "fixtures/01-zh.png").read_bytes(), check=True)
            first = android.wait_phase("import")
            # First process disappeared naturally. No force-stop/clear/reinstall
            # occurs between phases; the same real SharedPreferences survive.
            expected = android.adb("shell", "run-as", PACKAGE, "cat", "files/a1-expected.json")
            (run / "expected.json").write_text(expected, encoding="utf-8")
            second = android.wait_phase("reopen")
            validate_flow(first, second)
            before = source["files"]
            if {p.name: sha(p) for p in (command.root / "fixtures").glob("*.png")} != {
                    name: record["sha256"] for name, record in before.items()}:
                raise ValueError("Local fixture changed")
            for name, record in before.items():
                raw = subprocess.check_output(android.prefix + ["exec-out", "cat", android.remote + "/" + name])
                if hashlib.sha256(raw).hexdigest() != record["sha256"]:
                    raise ValueError("SAF source PNG changed: " + name)
            host.update(passed=True, arm64_execution=True, independent_process_reopen=True,
                        source_pngs_unchanged=True, os_exit_code_verified=False,
                        api23_runtime_verified=selected[0]["sdk"] == "23")
        except BaseException as error:
            host["error"] = str(error)
            raise
        finally:
            try:
                if installed:
                    # On failure this is cleanup, explicitly never success evidence.
                    android.adb("shell", "am", "force-stop", PACKAGE)
                    android.adb("uninstall", PACKAGE)
                    android.adb("shell", "rm", "-rf", android.remote)
                    android.adb("shell", "rm", "-f", android.remote_ui)
                    android.adb("shell", "rm", "-rf", android.remote_native)
                    remaining = android.adb("shell", "pm", "list", "packages", PACKAGE)
                    checks = {}
                    for path in (android.remote, android.remote_ui, android.remote_native):
                        checks[path] = android.adb("shell",
                            f"if [ -e {path} ]; then echo PRESENT; else echo ABSENT; fi").strip()
                    cleanup = {"only_owned_package": PACKAGE, "remaining_packages": remaining,
                               "owned_paths": checks}
                    save(run / "cleanup.json", cleanup)
                    if "package:" + PACKAGE in remaining or any(value != "ABSENT" for value in checks.values()):
                        raise RuntimeError("Owned package/path cleanup incomplete")
                    host["cleanup_passed"] = True
            except BaseException as error:
                host.update(passed=False, cleanup_error=str(error))
                raise
            finally:
                save(run / "host.json", host)
    print(run)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", nargs="?", choices=("inventory", "build", "normal-build", "accept"))
    parser.add_argument("--enable", action="store_true")
    parser.add_argument("--root", type=Path, default=Path("D:/Dev_project/martix-wp17-a1-private"))
    parser.add_argument("--adb", type=Path, default=Path("D:/Dev_SDKs/platform-tools/adb.exe"))
    parser.add_argument("--sdk", type=Path, default=Path("D:/Dev_SDKs/Android_studio_SDK"))
    parser.add_argument("--flutter", type=Path, default=Path("D:/Dev_SDKs/Flutter_3.32.8"))
    parser.add_argument("--ndk", type=Path, default=Path("D:/Dev_SDKs/Android_studio_SDK/ndk/28.0.12433566"))
    parser.add_argument("--serial")
    parser.add_argument("--enrollment", type=Path)
    args = parser.parse_args()
    if args.action is None or (args.action != "inventory" and not args.enable):
        print("DISABLED: explicitly enable WP17-A1; no device/build/model action")
        return 0
    if args.action == "accept" and (not args.serial or args.enrollment is None):
        parser.error("accept requires --serial and --enrollment")
    command = Commands(private_root(args.root))
    try:
        if args.action == "inventory":
            print(json.dumps(inventory(command, args.adb), indent=2))
        elif args.action == "build":
            build(args, command)
        elif args.action == "normal-build":
            normal_build(args, command)
        else:
            accept(args, command)
        return 0
    except (ValueError, RuntimeError, OSError, subprocess.SubprocessError) as error:
        save(command.root / "logs/" / (args.action + "-failure-" + uuid.uuid4().hex + ".json"),
             {"passed": False, "error": str(error)})
        print("FAILED: " + str(error), file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
