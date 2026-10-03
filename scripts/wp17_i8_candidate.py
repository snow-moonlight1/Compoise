#!/usr/bin/env python3
"""Build isolated opt-in OCR candidates or verify default absence. No signing."""
from __future__ import annotations
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import shlex
import struct
import subprocess
import sys
import tempfile
import uuid
import zipfile
sys.dont_write_bytecode = True
REPO = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO / "native/ocr/tools"))
from convert_models import PreparationError
from i8_assets import check_bundle, stage_bundle
from i8_prepare_native import check as check_native
import release_candidate as r1


def record(path: Path) -> dict:
    data = path.read_bytes()
    return {"bytes": len(data), "sha256": hashlib.sha256(data).hexdigest()}


def machine(data: bytes) -> str:
    if data[:4] == b"\x7fELF":
        if data[4:6] != b"\x02\x01":
            raise PreparationError("expected 64-bit little-endian ELF")
        return {62: "x86_64", 183: "arm64-v8a"}.get(struct.unpack_from("<H", data, 18)[0], "unknown")
    if data[:2] == b"MZ":
        offset = struct.unpack_from("<I", data, 60)[0]
        if data[offset:offset + 4] != b"PE\0\0":
            raise PreparationError("invalid PE library")
        return "x86_64" if struct.unpack_from("<H", data, offset + 4)[0] == 0x8664 else "unknown"
    raise PreparationError("not a PE/ELF native library")


def inspect(bundle: Path, platform: str, enabled: bool, assets: Path | None) -> dict:
    if platform.startswith("android"):
        with zipfile.ZipFile(bundle) as archive:
            names = archive.namelist()
            if len(names) != len(set(n.casefold() for n in names)):
                raise PreparationError("duplicate APK entries")
            files = {n: archive.read(n) for n in names if not n.endswith("/")}
        if (b"APK Sig Block 42" in bundle.read_bytes() or
                any(n.upper().endswith((".RSA", ".DSA", ".EC")) for n in files)):
            raise PreparationError("candidate APK must be unsigned")
    else:
        if any(p.is_symlink() for p in bundle.rglob("*")):
            raise PreparationError("linked candidate file")
        files = {p.relative_to(bundle).as_posix(): p.read_bytes() for p in bundle.rglob("*") if p.is_file()}
    hashes = {n: {"bytes": len(v), "sha256": hashlib.sha256(v).hexdigest()} for n, v in sorted(files.items())}
    ocr = [n for n in files if any(k in n.lower() for k in ("matrixflow_ocr", "wp17-ocr", "ncnn", "ppocr", "paddle"))]
    if not enabled:
        if ocr:
            raise PreparationError("default build contains OCR residue: " + str(ocr))
        return {"files": hashes, "ocrEnabled": False}
    expected = check_bundle(assets)
    prefix = "assets/wp17-ocr/" if platform.startswith("android") else "data/wp17-ocr/"
    asset_names = set(expected["files"]) | {"bundle-manifest.json"}
    if {n[len(prefix):] for n in files if n.startswith(prefix)} != asset_names:
        raise PreparationError("incomplete or extra candidate OCR resources")
    for name in asset_names:
        if files[prefix + name] != (assets / name).read_bytes():
            raise PreparationError("candidate resource differs: " + name)
    abi = platform.removeprefix("android-") if platform.startswith("android") else "x86_64"
    library = (f"lib/{abi}/libmatrixflow_ocr.so" if platform.startswith("android") else
               "matrixflow_ocr.dll" if platform == "windows" else "lib/libmatrixflow_ocr.so")
    if library not in files or machine(files[library]) != abi:
        raise PreparationError("missing or wrong ABI OCR library")
    if platform.startswith("android"):
        native_names = {n.split("/")[1] for n in files if n.startswith("lib/") and n.endswith(".so")}
        if native_names != {abi}:
            raise PreparationError("APK contains an unexpected ABI")
    return {"files": hashes, "ocrEnabled": True, "library": library,
            "abi": abi, "modelSource": "official", "resources": expected}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--platform", required=True, choices=("windows", "linux", "android-x86_64", "android-arm64-v8a"))
    parser.add_argument("--mode", required=True, choices=("official", "default"))
    parser.add_argument("--private-root", required=True, type=Path)
    parser.add_argument("--flutter", required=True, type=Path, help="pinned Flutter bin/flutter[.bat]")
    parser.add_argument("--pub-cache", required=True, type=Path, help="private dependency cache")
    parser.add_argument("--deploy", type=Path)
    parser.add_argument("--native-sdk", type=Path)
    parser.add_argument("--android-sdk", type=Path)
    parser.add_argument("--java-home", type=Path)
    parser.add_argument("--allow-pub-network", action="store_true")
    args = parser.parse_args()
    private = args.private_root.resolve()
    if private == REPO or private.is_relative_to(REPO) or REPO.is_relative_to(private):
        parser.error("private root must be outside and not contain the repository")
    if not args.pub_cache.resolve().is_relative_to(private):
        parser.error("pub cache must belong to the private root")
    enabled = args.mode == "official"
    if enabled != bool(args.deploy and args.native_sdk) or (not enabled and (args.deploy or args.native_sdk)):
        parser.error("official mode requires --deploy and --native-sdk; default mode takes neither")
    if args.platform.startswith("android") and not (args.android_sdk and args.java_home):
        parser.error("Android requires --android-sdk and --java-home")
    for key, value in os.environ.items():
        if (key.startswith(("WP15_", "WP17_")) and ("DEVICE" in key or "BUNDLE" in key or "VALIDATION" in key)
                and value.lower() not in ("", "false", "0")):
            parser.error("diagnostic identity/environment cannot be combined: " + key)
    private.mkdir(parents=True, exist_ok=True)
    run_root = private / "runs" / (args.platform + "-" + args.mode + "-" + uuid.uuid4().hex[:12])
    run_root.mkdir(parents=True)
    logs, tmp = run_root / "logs", run_root / "tmp"
    logs.mkdir()
    tmp.mkdir()
    tempfile.tempdir = str(tmp)
    env = dict(os.environ)
    for key in list(env):
        if key.startswith(("WP17_", "ORG_GRADLE_PROJECT_wp17", "ANDROID_KEY", "ANDROID_STORE")) or key == "REQUIRE_RELEASE_SIGNING":
            env.pop(key)
    env.update(PUB_CACHE=str(args.pub_cache.resolve()), GRADLE_USER_HOME=str(private / "gradle"),
               TMPDIR=str(tmp), TMP=str(tmp), TEMP=str(tmp), PYTHONDONTWRITEBYTECODE="1",
               CMAKE_BUILD_PARALLEL_LEVEL="2", CI="true")
    commands = []
    def run(command: list, cwd=REPO) -> bytes:
        command = [str(x) for x in command]
        # .bat files require cmd.exe; every argument is a tool/path controlled by
        # this entry point, and no user-supplied command fragments are accepted.
        process = subprocess.run(command, cwd=cwd, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        log = logs / f"{len(commands):02d}.log"
        log.write_bytes(process.stdout)
        commands.append({"argv": command, "exit": process.returncode, "log": log.name})
        (logs / "commands.json").write_text(json.dumps(commands, indent=2) + "\n")
        print(f"{command[0]}: exit {process.returncode}; {log}", flush=True)
        if process.returncode:
            raise PreparationError("command failed; see " + str(log))
        return process.stdout
    pin = json.loads((REPO / "toolchain.json").read_text())["verified"]
    info = json.loads(run([args.flutter, "--version", "--machine"]))
    if info["channel"] != pin["channel"]:
        raise PreparationError("Flutter channel differs from reviewed pin")
    for key, sdk_key in {"flutterVersion": "frameworkVersion", "revision": "frameworkRevision",
                         "engineRevision": "engineRevision", "dartVersion": "dartSdkVersion"}.items():
        if info[sdk_key] != pin[key]:
            raise PreparationError("Flutter toolchain differs: " + key)
    source = r1.source_trace(REPO)
    commit = subprocess.check_output(["git", "-C", str(REPO), "rev-parse", "HEAD"]).decode().strip()
    paths = subprocess.check_output(["git", "-C", str(REPO), "ls-files", "--cached", "--others", "--exclude-standard", "-z"]).decode().split("\0")
    mirror = run_root / "repo"
    mirror.mkdir()
    source_files = {}
    for name in sorted(set(paths) - {""}):
        if name.startswith("linux/flutter/generated_"):
            continue
        path = REPO / name
        if not path.is_file() or path.is_symlink():
            raise PreparationError("source is missing or linked: " + name)
        destination = mirror / name
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(path, destination)
        source_files[name] = record(path)
    # Build mirrors never retain repository pointers or inherited Git variables.
    env.pop("GIT_DIR", None)
    env.pop("GIT_WORK_TREE", None)
    assets, dependency = None, None
    if enabled:
        dependency = check_native(args.native_sdk.resolve(), args.platform.removeprefix("android-"))
        stage_bundle(args.deploy.resolve(), run_root / "assets")
        assets = run_root / "assets/wp17-ocr"
        check_bundle(assets)
        env["WP17_OCR_NCNN_DIR"] = str(args.native_sdk.resolve() / "install/lib/cmake/ncnn")
        env["WP17_OCR_STB_DIR"] = str(args.native_sdk.resolve() / "third_party")
        env["WP17_OCR_MODELS_DIR"] = str(assets)
        env["WP17_OCR_PYTHON"] = sys.executable
    lock_before = (mirror / "pubspec.lock").read_bytes()
    pub = [args.flutter, "pub", "get", "--enforce-lockfile"]
    if not args.allow_pub_network:
        pub.append("--offline")
    run(pub, mirror)
    if (mirror / "pubspec.lock").read_bytes() != lock_before:
        raise PreparationError("pub get changed the lockfile")
    if args.platform.startswith("android"):
        env["JAVA_HOME"] = str(args.java_home.resolve())
        abi = args.platform.removeprefix("android-")
        target = "android-x64" if abi == "x86_64" else "android-arm64"
        properties = [f"sdk.dir={args.android_sdk.resolve().as_posix()}",
                      f"flutter.sdk={args.flutter.resolve().parents[1].as_posix()}", "wp17I8Unsigned=true"]
        if enabled:
            android_native = run_root / "android-native" / f"ncnn-android-{abi}" / "install"
            shutil.copytree(args.native_sdk / "install", android_native)
            properties += [f"wp17OcrNcnnRoot={android_native.parents[1].as_posix()}",
                           f"wp17OcrStbDir={(args.native_sdk.resolve() / 'third_party').as_posix()}",
                           f"wp17OcrModels={assets.parent.as_posix()}", f"wp17I8Abi={abi}"]
        (mirror / "android/local.properties").write_text("\n".join(properties) + "\n", encoding="utf-8")
        # Flutter 3.32's Gradle launcher passes only JAVA_HOME/PATH. Set the
        # cache in this disposable mirror's launcher before Gradle starts.
        launcher = mirror / "android" / ("gradlew.bat" if os.name == "nt" else "gradlew")
        original = launcher.read_text()
        if os.name == "nt":
            cache_line = f'@set "GRADLE_USER_HOME={private / "gradle"}"\n'
            launcher.write_text(cache_line + original)
        else:
            lines = original.splitlines(keepends=True)
            lines.insert(1, "export GRADLE_USER_HOME=" + shlex.quote(str(private / "gradle")) + "\n")
            launcher.write_text("".join(lines))
            launcher.chmod(0o755)
        with (mirror / "android/gradle.properties").open("a") as stream:
            stream.write("\norg.gradle.workers.max=2\norg.gradle.daemon=false\n")
        run([args.flutter, "build", "apk", "--release", "--no-pub", "--no-tree-shake-icons", "--target-platform", target, "-t", "lib/main.dart"], mirror)
        built = mirror / "build/app/outputs/flutter-apk/app-release.apk"
    else:
        run([args.flutter, "build", args.platform, "--release", "--no-pub", "-t", "lib/main.dart"], mirror)
        built = mirror / ("build/windows/x64/runner/Release" if args.platform == "windows" else "build/linux/x64/release/bundle")
    facts = inspect(built, args.platform, enabled, assets)
    version_match = re.search(r"^version:\s*(\d+\.\d+\.\d+)\+(\d+)\s*$", (REPO / "pubspec.yaml").read_text(), re.M)
    if not version_match:
        raise PreparationError("invalid application version")
    version, build_number = version_match.groups()
    identity = {}
    if args.platform == "windows":
        env["WP17_I8_EXE"] = str(built / "compoise.exe")
        ps = "$f=Get-Item -LiteralPath $env:WP17_I8_EXE; $v=$f.VersionInfo; "
        ps += "@{product=$v.ProductName;company=$v.CompanyName;version=$v.FileVersion;numeric=('{0}.{1}.{2}.{3}' -f $v.FileMajorPart,$v.FileMinorPart,$v.FileBuildPart,$v.FilePrivatePart);copyright=$v.LegalCopyright;signature=(Get-AuthenticodeSignature -LiteralPath $f.FullName).Status.ToString()} | ConvertTo-Json -Compress"
        identity = json.loads(run(["powershell", "-NoProfile", "-Command", ps]))
        if (identity["product"] != "Compoise" or identity["company"] != "Compoise" or
                identity["numeric"] != version + "." + build_number or identity["signature"] != "NotSigned" or
                identity["version"] not in (version + "+" + build_number, version + "." + build_number) or
                "Compoise contributors" not in identity["copyright"]):
            raise PreparationError("Windows normal identity/version/signature differs")
        identity["appDataDir"] = r"%APPDATA%\Compoise\Compoise"
    elif args.platform.startswith("android"):
        tools = sorted(args.android_sdk.glob("build-tools/*/aapt2*"))
        if not tools:
            raise PreparationError("aapt2 required for APK identity")
        badging = run([tools[-1], "dump", "badging", built]).decode("utf-8")
        match = re.search(r"package: name='([^']+)' versionCode='([^']+)' versionName='([^']+)'", badging)
        if not match or match.groups() != ("com.matrixflow.app", build_number, version):
            raise PreparationError("APK normal identity/version differs")
        identity = dict(zip(("package", "versionCode", "versionName"), match.groups()))
    runtime = None
    if enabled and not args.platform.startswith("android"):
        report = run_root / "native12.json"
        run([sys.executable, REPO / "native/ocr/tools/validate_official_runtime.py", "--library", built / facts["library"], "--assets", built / "data/wp17-ocr", "--report", report])
        runtime = json.loads(report.read_text())
    # Ordinary R1 checks retain their exact implementation. The OCR artifact is
    # an addendum; R1's intentional residue rejection is recorded, never bypassed.
    r1_fact = {"source": "recorded", "ordinaryCandidate": False, "reason": "OCR addendum / Linux preview / unsigned APK"}
    if args.platform == "windows":
        archive = shutil.make_archive(str(run_root / "windows-portable"), "zip", built)
        try:
            r1.zip_inventory(Path(archive))
            r1_fact = {"zipInventory": "passed", "ordinaryCandidate": False, "reason": "full release proof/seal not requested"}
        except ValueError as error:
            if not enabled or "OCR residue" not in str(error):
                raise
            r1_fact = {"zipInventory": "refused", "ordinaryCandidate": False, "reason": str(error)}
    if r1.source_trace(REPO) != source or any(record(REPO / n) != v for n, v in source_files.items()):
        raise PreparationError("reviewed source changed during candidate build")
    if enabled:
        check_native(args.native_sdk.resolve(), args.platform.removeprefix("android-"))
    proof = {"schema": 1, "kind": "wp17-i8-ocr-addendum" if enabled else "wp17-i8-default-build-check",
             "platform": args.platform, "buildMode": "Release", "entry": "lib/main.dart",
             "commit": commit, "source": source, "sourceFiles": source_files, "toolchain": pin,
             "modelLock": record(REPO / "native/ocr/tools/models.lock.json") if enabled else None,
             "nativeDependency": dependency, "artifact": facts, "native12": runtime, "r1": r1_fact,
             "identity": identity,
             "signing": "unsigned", "deviceQualityGate": "unverified", "publication": "not authorized by this build"}
    if enabled:
        model_lock = json.loads((REPO / "native/ocr/tools/models.lock.json").read_text())
        proof["officialInputs"] = {k: v for k, v in model_lock["files"].items() if v.get("kind") == "paddle-inference-model"}
        proof["licenceSources"] = model_lock["attachments"]
        proof["dictionarySource"] = model_lock["dependencies"]["ncnn/ppocrv5_dict.txt"]
        conversion = model_lock["conversion"]
        proof["conversion"] = {"byte_identical": conversion["byte_identical"], "replays": conversion["replays"],
                               "versions": conversion["environment"]["versions"], "pnnx_sha256": conversion["environment"]["pnnx_sha256"],
                               "export_flags": conversion["export_flags"], "pnnx_flags": conversion["pnnx_flags"]}
    (run_root / "OCR_CANDIDATE.json").write_text(json.dumps(proof, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print("candidate proof: " + str(run_root / "OCR_CANDIDATE.json"))
    print("artifact: " + str(built))
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (PreparationError, OSError, ValueError, KeyError) as error:
        print("ERROR: " + str(error), file=sys.stderr)
        sys.exit(getattr(error, "exit_code", 3))
