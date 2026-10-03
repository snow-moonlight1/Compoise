#!/usr/bin/env python3
"""Shared local/CI release candidate gate. No dependencies and no publishing."""
import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import re
import shutil
import subprocess
import sys
import zipfile

PLATFORMS = {"Windows": "windows-portable.zip", "Android": "android.apk"}
RECORDS = ("RELEASE_MANIFEST.txt", "RELEASE_METADATA.txt", "SHA256SUMS.txt")
FACTS = {
    "windowsCodeSigning": "unsigned (Authenticode is not configured)",
    "linuxDesktop": "preview only; no artifact published",
    "license": "GPL-3.0-only",
    "ocr": "disabled; no OCR runtime, models or licence bundle",
    "dataCompatibility": "backup v3; export before upgrade; local credential state is not in backups; old Windows credentials require reconfiguration",
}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def digest(data):
    return hashlib.sha256(data).hexdigest()


def snapshot(path):
    require(path.is_file() and not path.is_symlink(), f"Missing or linked file: {path.name}")
    return {"name": path.name, "bytes": path.stat().st_size, "sha256": digest(path.read_bytes())}


def context(root, tag, commit):
    match = re.search(r"^version:\s*(\d+\.\d+\.\d+)\+(\d+)\s*$", (root / "pubspec.yaml").read_text(encoding="utf-8"), re.M)
    require(match, "pubspec.yaml must declare X.Y.Z+N")
    version = f"{match[1]}+{match[2]}"
    require(tag in (f"v{match[1]}", f"v{version}"), "Tag and pubspec version disagree")
    require(re.fullmatch(r"[0-9a-f]{40}", commit), "Expected commit must be a full SHA")
    pin = json.loads((root / "toolchain.json").read_text(encoding="utf-8"))["verified"]
    return {"version": version, "tag": tag, "commit": commit, "toolchain": {k: pin[k] for k in ("flutterVersion", "revision", "engineRevision", "dartVersion")}}


def selected(platform):
    return list(PLATFORMS) if platform == "All" else [platform]


def artifact_name(ctx, platform):
    return f"compoise-v{ctx['version']}-{PLATFORMS[platform]}"


def proof_name(platform):
    return f"{platform.upper()}_PROOF.json"


def zip_inventory(path):
    files = []
    seen = set()
    with zipfile.ZipFile(path) as archive:
        for entry in archive.infolist():
            name = entry.filename.replace("\\", "/")
            parts = PurePosixPath(name).parts
            require(name and not name.startswith("/") and not re.match(r"^[A-Za-z]:", name) and ".." not in parts and ":" not in name, f"Unsafe ZIP path: {name}")
            require(name.rstrip("/") == PurePosixPath(name).as_posix(), f"Noncanonical ZIP path: {name}")
            require(name.casefold() not in seen, f"Duplicate ZIP path: {name}")
            seen.add(name.casefold())
            require((entry.external_attr >> 16) & 0o170000 != 0o120000, f"ZIP symlink: {name}")
            require(not re.search(r"(?i)(ocr|ncnn|ppocr|paddle|model_card)|\.(onnx|param|pdmodel|pdiparams)$|(^|/)models(/|$)", name), f"Default candidate contains OCR residue: {name}")
            if "licenses" in parts and not entry.is_dir():
                require(name in ("data/flutter_assets/assets/licenses/MaterialIcons_LICENSE.txt", "data/flutter_assets/assets/licenses/THIRD_PARTY_NOTICES.txt"), f"Default candidate contains an unexpected licence bundle: {name}")
            if entry.is_dir():
                continue
            data = archive.read(entry)  # also checks the ZIP CRC
            files.append({"path": name, "bytes": len(data), "sha256": digest(data)})
    names = {f["path"] for f in files}
    for name in ("compoise.exe", "flutter_windows.dll", "data/app.so", "data/icudtl.dat", "data/flutter_assets/AssetManifest.bin", "data/flutter_assets/assets/licenses/THIRD_PARTY_NOTICES.txt"):
        require(name in names, f"Incomplete portable ZIP: missing {name}")
    return sorted(files, key=lambda f: f["path"])


def normalize_cert(value):
    result = value.replace(":", "").lower()
    require(re.fullmatch(r"[0-9a-f]{64}", result), "Missing or malformed pinned Android certificate")
    return result


def validate_proof(directory, platform, ctx, cert):
    path = directory / proof_name(platform)
    require(path.is_file() and not path.is_symlink(), f"Missing {platform} build proof")
    proof = json.loads(path.read_text(encoding="utf-8-sig"))
    require(proof.get("schema") == 1 and proof.get("platform") == platform, "Wrong proof schema/platform")
    for key, value in ctx.items():
        require(proof.get(key) == value, f"Proof {key} disagrees with this candidate")
    source = proof.get("source", {})
    require(isinstance(source.get("dirty"), bool) and isinstance(source.get("paths"), list) and re.fullmatch(r"[0-9a-f]{64}", source.get("diffSha256", "")), "Missing source tree trace")
    actual = snapshot(directory / artifact_name(ctx, platform))
    require(actual["bytes"] > 0 and proof.get("artifact") == actual, "Proof is stale or artifact was changed")
    evidence = proof.get("evidence", {})
    if platform == "Windows":
        expected_numeric = ctx["version"].replace("+", ".")
        for key, value in {"productName": "Compoise", "companyName": "Compoise", "authenticode": "NotSigned", "fileVersionNumeric": expected_numeric, "appDataDir": r"%APPDATA%\Compoise\Compoise"}.items():
            require(evidence.get(key) == value, f"Windows identity/signature mismatch: {key}")
        require(evidence.get("fileVersionString") in (ctx["version"], expected_numeric), "Windows file version mismatch")
        require("Compoise contributors" in evidence.get("legalCopyright", ""), "Windows copyright mismatch")
        require(proof.get("zipFiles") == zip_inventory(directory / actual["name"]), "Windows ZIP inventory differs from build proof")
    else:
        expected_cert = normalize_cert(cert)
        require(evidence.get("apkSignatureVerified") == "true", "Android signature is unverified")
        require(evidence.get("apkSignatureCertSha256") == expected_cert, "Android certificate does not match pin")
        dn = evidence.get("apkSignatureDN", "")
        require(dn and "cn=android debug" not in dn.lower() and dn != "unknown", "Missing or debug Android certificate DN")
        require(evidence.get("apkPackage") == "com.matrixflow.app", "Android package mismatch")
        version, build = ctx["version"].split("+")
        require(evidence.get("apkVersionName") == version and evidence.get("apkVersionCode") == build, "Android version mismatch")
    return proof


def ensure_set(directory, names, directories=False):
    actual = {p.name for p in directory.iterdir()}
    require(actual == set(names), f"Candidate file set differs: missing={sorted(set(names) - actual)}, extra={sorted(actual - set(names))}")
    require(all((p.is_dir() if directories else p.is_file()) and not p.is_symlink() for p in directory.iterdir()), "Candidate contains a wrong entry type or link")


def manifest_for(directory, platform, ctx, cert, notes):
    proofs = [validate_proof(directory, p, ctx, cert) for p in selected(platform)]
    # Each platform carries its own source trace; CI generated files may differ.
    require(len({p["source"]["diffSha256"] for p in proofs}) == 1, "Platforms were built from different source changes")
    return {"schema": 1, **ctx, "platform": platform, **FACTS,
            "artifacts": [p["artifact"] for p in proofs],
            "proofs": [snapshot(directory / proof_name(p)) for p in selected(platform)],
            "androidSigning": "release certificate pinned and verified" if "Android" in selected(platform) else "not staged; formal release certificate required for APK",
            "buildEvidence": {p["platform"]: p["evidence"] for p in proofs},
            "sourceTrees": {p["platform"]: p["source"] for p in proofs},
            "notes": snapshot(directory / "RELEASE_NOTES.md") if notes else None}


def json_bytes(value):
    return (json.dumps(value, ensure_ascii=False, indent=2) + "\n").encode("utf-8")


def metadata(manifest):
    lines = ["Compoise release metadata", "schema=1"]
    for key in ("version", "tag", "commit", "platform"):
        lines.append(f"{key}={manifest[key]}")
    for key, value in manifest["toolchain"].items():
        lines.append(f"toolchain.{key}={value}")
    lines += [f"{k}={v}" for k, v in FACTS.items()]
    lines.append(f"androidSigning={manifest['androidSigning']}")
    for platform, evidence in manifest["buildEvidence"].items():
        lines += ["", f"[{platform.lower()}]"]
        lines += [f"{key}={value}" for key, value in evidence.items()]
    for platform, source in manifest["sourceTrees"].items():
        lines += ["", f"[source.{platform.lower()}]", f"dirty={source['dirty']}", f"diffSha256={source['diffSha256']}", f"paths={json.dumps(source['paths'], ensure_ascii=False)}"]
    lines += ["", "[artifacts]"]
    lines += [f"{a['name']}\t{a['bytes']} bytes\t{a['sha256']}" for a in manifest["artifacts"]]
    lines += ["", "[proofs]"]
    lines += [f"{p['name']}\t{p['sha256']}" for p in manifest["proofs"]]
    return ("\n".join(lines) + "\n").encode("utf-8")


def verify(directory, platform, ctx, cert):
    require(directory.is_dir() and not directory.is_symlink(), "Candidate directory missing or linked")
    notes = (directory / "RELEASE_NOTES.md").exists()
    names = [artifact_name(ctx, p) for p in selected(platform)] + [proof_name(p) for p in selected(platform)] + list(RECORDS)
    if notes:
        names.append("RELEASE_NOTES.md")
    ensure_set(directory, names)
    expected = manifest_for(directory, platform, ctx, cert, notes)
    require(json.loads((directory / RECORDS[0]).read_text(encoding="utf-8")) == expected, "Manifest identity, facts or hashes disagree")
    require((directory / RECORDS[1]).read_bytes() == metadata(expected), "Metadata differs from manifest")
    checksum_names = sorted(set(names) - {RECORDS[2]})
    expected_sums = "".join(f"{snapshot(directory / n)['sha256']}  {n}\n" for n in checksum_names).encode("ascii")
    require((directory / RECORDS[2]).read_bytes() == expected_sums, "SHA256SUMS has missing, extra, duplicate or changed entries")
    return expected


def seal(directory, platform, ctx, cert):
    require(directory.is_dir() and not directory.is_symlink(), "Candidate directory missing or linked")
    # Invalidate an old success record before any new validation can fail.
    for name in RECORDS:
        (directory / name).unlink(missing_ok=True)
    notes = (directory / "RELEASE_NOTES.md").exists()
    names = [artifact_name(ctx, p) for p in selected(platform)] + [proof_name(p) for p in selected(platform)]
    if notes:
        names.append("RELEASE_NOTES.md")
    ensure_set(directory, names)
    manifest = manifest_for(directory, platform, ctx, cert, notes)
    try:
        (directory / RECORDS[0]).write_bytes(json_bytes(manifest))
        (directory / RECORDS[1]).write_bytes(metadata(manifest))
        sums = sorted(names + list(RECORDS[:2]))
        (directory / RECORDS[2]).write_bytes("".join(f"{snapshot(directory / n)['sha256']}  {n}\n" for n in sums).encode("ascii"))
        verify(directory, platform, ctx, cert)
    except Exception:
        for name in RECORDS:
            (directory / name).unlink(missing_ok=True)
        raise


def make_proof(directory, platform, ctx, facts_path, bundle=None, cert=""):
    facts = json.loads(facts_path.read_text(encoding="utf-8-sig"))
    for key, value in ctx.items():
        require(facts.get(key) == value, f"Build facts {key} mismatch")
    proof = {"schema": 1, "platform": platform, **facts, "artifact": snapshot(directory / artifact_name(ctx, platform))}
    if platform == "Windows":
        proof["zipFiles"] = zip_inventory(directory / proof["artifact"]["name"])
        require(bundle and bundle.is_dir(), "Windows proof requires its complete build bundle")
        bundle_files = []
        for path in bundle.rglob("*"):
            require(not path.is_symlink(), "Build bundle contains a link")
            if path.is_file():
                item = snapshot(path)
                bundle_files.append({"path": path.relative_to(bundle).as_posix(), "bytes": item["bytes"], "sha256": item["sha256"]})
        require(sorted(bundle_files, key=lambda f: f["path"]) == proof["zipFiles"], "ZIP does not exactly cover the build bundle")
    proof_path = directory / proof_name(platform)
    try:
        proof_path.write_bytes(json_bytes(proof))
        validate_proof(directory, platform, ctx, cert)
    except Exception:
        proof_path.unlink(missing_ok=True)
        raise


def assemble(directory, inputs, ctx, cert):
    require(not directory.exists(), "Assembly output already exists; refusing stale output")
    ensure_set(inputs, ("android-release-apk", "windows-portable-zip"), directories=True)
    for platform, folder in (("Android", "android-release-apk"), ("Windows", "windows-portable-zip")):
        verify(inputs / folder, platform, ctx, cert)
        proof = validate_proof(inputs / folder, platform, ctx, cert)
        require(proof["source"]["diffSha256"] == digest(b""), "Formal assembly refuses source changes outside the recorded commit")
    directory.mkdir(parents=True)
    for platform, folder in (("Android", "android-release-apk"), ("Windows", "windows-portable-zip")):
        for name in (artifact_name(ctx, platform), proof_name(platform)):
            shutil.copyfile(inputs / folder / name, directory / name)
    seal(directory, "All", ctx, cert)


def source_trace(root):
    def git(*args):
        return subprocess.check_output(["git", "-C", str(root), *args])
    diff = git("diff", "--binary", "HEAD")
    paths = git("status", "--porcelain").decode("utf-8").splitlines()
    generated = {f"linux/flutter/{name}" for name in ("generated_plugin_registrant.cc", "generated_plugin_registrant.h", "generated_plugins.cmake")}
    for name in sorted(git("ls-files", "--others", "--exclude-standard", "-z").decode("utf-8").split("\0")):
        if name and name not in generated:
            path = root / name
            require(path.is_file() and not path.is_symlink(), "Untracked source contains a link")
            diff += name.encode() + b"\0" + path.read_bytes() + b"\0"
    return {"dirty": bool(paths), "paths": paths, "diffSha256": digest(diff)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("proof", "seal", "verify", "assemble", "extract", "source"))
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--directory", type=Path, required=True)
    parser.add_argument("--platform", choices=("All", "Windows", "Android"), required=True)
    parser.add_argument("--tag", required=True)
    parser.add_argument("--commit", required=True)
    parser.add_argument("--android-cert-sha256", default="")
    parser.add_argument("--facts", type=Path)
    parser.add_argument("--inputs", type=Path)
    parser.add_argument("--bundle", type=Path)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    try:
        if args.command in ("seal", "proof"):
            require(args.directory.is_dir() and not args.directory.is_symlink(), "Candidate directory missing or linked")
            for name in RECORDS:
                (args.directory / name).unlink(missing_ok=True)
            if args.command == "proof" and args.platform != "All":
                (args.directory / proof_name(args.platform)).unlink(missing_ok=True)
        ctx = context(args.root, args.tag, args.commit)
        if args.command == "source":
            print(json.dumps(source_trace(args.root)))
            return 0
        if args.command == "proof":
            require(args.platform != "All" and args.facts, "Proof requires one platform and facts")
            make_proof(args.directory, args.platform, ctx, args.facts, args.bundle, args.android_cert_sha256)
        elif args.command == "assemble":
            require(args.platform == "All" and args.inputs, "Assembly requires All and inputs")
            assemble(args.directory, args.inputs, ctx, args.android_cert_sha256)
        elif args.command == "seal":
            seal(args.directory, args.platform, ctx, args.android_cert_sha256)
        elif args.command == "extract":
            require(args.platform == "Windows" and args.output and not args.output.exists(), "Extraction requires Windows and a fresh output path")
            verify(args.directory, args.platform, ctx, args.android_cert_sha256)
            archive_path = args.directory / artifact_name(ctx, "Windows")
            inventory = zip_inventory(archive_path)
            args.output.mkdir(parents=True)
            with zipfile.ZipFile(archive_path) as archive:
                for entry in archive.infolist():
                    name = entry.filename.replace("\\", "/")
                    destination = args.output / name
                    if entry.is_dir():
                        destination.mkdir(parents=True, exist_ok=True)
                    else:
                        destination.parent.mkdir(parents=True, exist_ok=True)
                        destination.write_bytes(archive.read(entry))
            for item in inventory:
                actual = snapshot(args.output / item["path"])
                require(actual["bytes"] == item["bytes"] and actual["sha256"] == item["sha256"], "Extracted file differs from ZIP inventory")
        else:
            verify(args.directory, args.platform, ctx, args.android_cert_sha256)
        print(f"{args.command}: PASS ({args.platform}, {ctx['tag']}, {ctx['commit']})")
        return 0
    except (ValueError, OSError, KeyError, TypeError, subprocess.SubprocessError, zipfile.BadZipFile) as error:
        print(f"{args.command}: REJECTED: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
