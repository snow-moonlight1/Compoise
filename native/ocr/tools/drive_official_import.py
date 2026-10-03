#!/usr/bin/env python3
"""Opt-in isolated I6 driver. Linux --file-entry selects real files; OCR is native."""
from __future__ import annotations
import argparse
import json
import os
import re
import shutil
import subprocess
import time
import xml.etree.ElementTree as ET
from pathlib import Path

MARKERS = ("WP17_I6_CANCEL_READY", "WP17_I6_REVIEW_CANCEL_READY", "WP17_I6_SAVE_READY")
PACKAGE = "com.matrixflow.app.wp17i6"
REMOTE = "/sdcard/Download/WP17-I6"


def run(arguments: list[str], **kwargs) -> str:
    return subprocess.check_output(arguments, text=True, encoding="utf-8", errors="replace", **kwargs)


class Android:
    def __init__(self, serial: str, apk: Path, sdk: Path, root: Path):
        self.adb = [str(sdk / "platform-tools/adb.exe"), "-s", serial]
        self.root = root
        if run(self.adb + ["emu", "avd", "name"]).splitlines()[0].strip() != "wp17i6api23":
            raise RuntimeError("Only the dedicated wp17i6api23 AVD is allowed")
        if run(self.adb + ["shell", "getprop", "ro.build.version.sdk"]).strip() != "23":
            raise RuntimeError("Expected API 23")
        aapt = sorted((sdk / "build-tools").glob("*/aapt.exe"), reverse=True)[0]
        facts = run([str(aapt), "dump", "badging", str(apk)])
        if not re.search(r"^package: name='" + re.escape(PACKAGE) + "'", facts, re.M):
            raise RuntimeError("Refusing an APK without the isolated identity")
        self.settings = {key: run(self.adb + ["shell", "settings", "get", "global", key]).strip()
                         for key in ("window_animation_scale", "transition_animation_scale", "animator_duration_scale")}
        for key in self.settings:
            run(self.adb + ["shell", "settings", "put", "global", key, "0"])
        # This package is test-only and has no normal application data.
        if PACKAGE in run(self.adb + ["shell", "pm", "list", "packages", PACKAGE]):
            run(self.adb + ["uninstall", PACKAGE])
        run(self.adb + ["install", "-t", str(apk)])
        run(self.adb + ["shell", "mkdir", "-p", REMOTE])

    def push(self, fixtures: Path):
        for path in sorted(fixtures.glob("*.png")):
            run(self.adb + ["push", str(path), REMOTE + "/" + path.name])

    def nodes(self):
        run(self.adb + ["shell", "uiautomator", "dump", "/sdcard/wp17-i6-ui.xml"])
        data = run(self.adb + ["shell", "cat", "/sdcard/wp17-i6-ui.xml"])
        (self.root / "logs/last-android-ui.xml").write_text(data)
        return list(ET.fromstring(data).iter("node"))

    def tap(self, node, long: bool = False):
        bounds = list(map(int, re.findall(r"\d+", node.attrib["bounds"])))
        x, y = (bounds[0] + bounds[2]) // 2, (bounds[1] + bounds[3]) // 2
        if long:
            run(self.adb + ["shell", "input", "swipe", str(x), str(y), str(x), str(y), "1000"])
        else:
            run(self.adb + ["shell", "input", "tap", str(x), str(y)])

    def choose(self, cancel: bool):
        limit = time.monotonic() + 60
        while time.monotonic() < limit:
            nodes = self.nodes()
            if any(n.attrib.get("package") == "com.android.documentsui" for n in nodes):
                break
            time.sleep(0.5)
        else:
            raise RuntimeError("Real DocumentsUI did not open")
        if cancel:
            run(self.adb + ["shell", "input", "keyevent", "4"])
            return
        # Navigate only the provider's dedicated synthetic directory. On a new
        # AVD, the primary-storage root may first need enabling in its menu.
        storage_ready = False
        for _ in range(24):
            nodes = self.nodes()
            if any(n.attrib.get("text") == "01-zh.png" for n in nodes):
                break
            texts = {n.attrib.get("text"): n for n in nodes if n.attrib.get("text")}
            descriptions = {n.attrib.get("content-desc"): n for n in nodes if n.attrib.get("content-desc")}
            with (self.root / "logs/picker-navigation.jsonl").open("a") as trace:
                trace.write(json.dumps({"texts": sorted(texts), "descriptions": sorted(descriptions)}) + "\n")
            if not storage_ready and "WP17-I6" not in texts and "Download" not in texts:
                if "Show SD card" in texts or "Show internal storage" in texts:
                    self.tap(texts.get("Show SD card", texts.get("Show internal storage")))
                    storage_ready = True
                elif "Hide SD card" in texts or "Hide internal storage" in texts:
                    run(self.adb + ["shell", "input", "keyevent", "4"])
                    storage_ready = True
                elif "Open from" in texts:
                    self.tap(texts["Recent"])
                elif "More options" in descriptions:
                    self.tap(descriptions["More options"])
                else:
                    raise RuntimeError("Cannot enable primary-storage picker root: " + repr(sorted(texts)))
                time.sleep(0.4)
                continue
            if "WP17-I6" in texts:
                self.tap(texts["WP17-I6"])
            elif "Download" in texts and any(n.attrib.get("resource-id", "").endswith("title") for n in nodes if n.attrib.get("text") == "Download"):
                self.tap(texts["Download"])
            elif "Show SD card" in texts:
                self.tap(texts["Show SD card"])
            elif "Internal storage" in texts:
                self.tap(texts["Internal storage"])
            elif any("Android SDK" in text for text in texts):
                self.tap(next(n for text, n in texts.items() if "Android SDK" in text))
            elif "Show roots" in descriptions:
                self.tap(descriptions["Show roots"])
            elif "More options" in descriptions:
                self.tap(descriptions["More options"])
            elif "Downloads" in texts:
                self.tap(texts["Downloads"])
            else:
                raise RuntimeError("Cannot navigate DocumentsUI: " + repr(sorted(texts)))
            time.sleep(0.4)
        else:
            raise RuntimeError("Synthetic directory was not visible")
        for index, name in enumerate(("01-zh.png", "02-en.png", "03-ja.png", "04-zh-duplicate.png", "05-corrupt.png")):
            matching = [n for n in self.nodes() if n.attrib.get("text") == name]
            if not matching:
                raise RuntimeError("Synthetic PNG missing from real picker: " + name)
            self.tap(matching[0], long=index == 0)
        nodes = self.nodes()
        actions = [n for n in nodes if n.attrib.get("text", "").upper() in ("OPEN", "SELECT")
                   or n.attrib.get("content-desc", "").upper() in ("OPEN", "SELECT")]
        if not actions:
            raise RuntimeError("DocumentsUI multi-select confirmation missing")
        self.tap(actions[-1])

    def memory(self) -> int:
        try:
            processes = run(self.adb + ["shell", "ps"]).splitlines()
            rows = [line.split() for line in processes if line.split() and line.split()[-1] == PACKAGE]
            if not rows: return 0
            pid = rows[0][1]
            status = run(self.adb + ["shell", "cat", "/proc/" + pid + "/status"])
            return int(re.search(r"VmHWM:\s+(\d+)", status).group(1))
        except (subprocess.SubprocessError, AttributeError):
            return 0

    def close(self):
        run(self.adb + ["shell", "am", "force-stop", PACKAGE])
        run(self.adb + ["shell", "rm", "-rf", REMOTE, "/sdcard/wp17-i6-ui.xml"])
        run(self.adb + ["uninstall", PACKAGE])
        for key, value in self.settings.items():
            if value == "null": run(self.adb + ["shell", "settings", "delete", "global", key])
            else: run(self.adb + ["shell", "settings", "put", "global", key, value])


class Linux:
    def __init__(self, fixtures: Path, file_entry: bool = False, evidence: Path | None = None):
        self.fixtures = fixtures
        self.file_entry = file_entry
        self.evidence = evidence
        self.selections = 0

    @staticmethod
    def nodes(pid: int):
        # Lazy import: Android and ordinary Python regressions need no GTK.
        import gi
        gi.require_version("Atspi", "2.0")
        from gi.repository import Atspi, GLib
        desktop = Atspi.get_desktop(0)
        result = []

        def walk(node, depth=0):
            if node is None:
                return  # GTK4 can remove a child during directory navigation.
            if depth > 40 or len(result) > 4000:
                raise RuntimeError("Unexpectedly large dedicated picker tree")
            try:
                node.get_role_name()  # Reject defunct nodes before retaining them.
                result.append(node)
                for index in range(node.get_child_count()):
                    walk(node.get_child_at_index(index), depth + 1)
            except GLib.GError:
                return  # Re-read the tree on the caller's next bounded attempt.

        for index in range(desktop.get_child_count()):
            app = desktop.get_child_at_index(index)
            if app is not None and app.get_process_id() == pid:
                walk(app)
        return result

    @staticmethod
    def matches(node, role: str, names):
        from gi.repository import GLib
        try:
            return node.get_role_name() == role and node.get_name() in names
        except GLib.GError:
            return False

    def cell(self, pid: int, name: str):
        deadline = time.monotonic() + 20
        while time.monotonic() < deadline:
            for node in self.nodes(pid):
                if self.matches(node, "table cell", (name,)):
                    return node
            time.sleep(0.2)
        raise RuntimeError("File row missing in real GTK picker: " + name)

    def select_files(self, pid: int, names: list[str]):
        for name in names:
            self.cell(pid, name)
        # GTK4 does not report usable screen coordinates under this Xvfb
        # environment. Its real file-list Selection interface is available.
        cell = self.cell(pid, names[0])
        selection = cell.get_parent().get_parent().get_selection_iface()
        if selection is None or not selection.select_all():
            raise RuntimeError("GTK file-list selection failed")
        selected = [selection.get_selected_child(index).get_child_at_index(0).get_name()
                    for index in range(selection.get_n_selected_children())]
        if sorted(selected) != names:
            raise RuntimeError("GTK selected rows differ from dedicated PNGs: " + repr(selected))
        return selected

    def confirm(self, pid: int):
        # Re-read after selecting: GTK4 destroys/recreates accessible nodes.
        buttons = [node for node in self.nodes(pid) if self.matches(node, "push button",
                   ("确定(O)", "OK", "Open", "打开(O)", "_Open", "_OK"))]
        if len(buttons) != 1:
            raise RuntimeError("Cannot identify GTK confirmation button")
        button = buttons[0]
        name = button.get_name()
        if not button.get_action_iface().do_action(0):
            raise RuntimeError("GTK confirmation action failed")
        return name

    def snapshot(self, window: str, label: str):
        if self.evidence is not None:
            run(["xwd", "-silent", "-id", window, "-out",
                 str(self.evidence / f"picker-{self.selections}-{label}.xwd")])

    def choose(self, cancel: bool):
        if self.file_entry:
            return  # Explicit selection seam in Dart; disk bytes and OCR stay real.
        if not os.environ.get("WP17_LINUX_PRIVATE_DISPLAY") or os.environ["WP17_LINUX_PRIVATE_DISPLAY"] != os.environ.get("DISPLAY"):
            raise RuntimeError("Real picker requires the script's private Xvfb display")
        limit = time.monotonic() + 60
        window = None
        while time.monotonic() < limit:
            search = subprocess.run(["xdotool", "search", "--onlyvisible", "--class", "zenity"], capture_output=True, text=True)
            if search.returncode == 0:
                window = search.stdout.splitlines()[-1]
                break
            time.sleep(0.3)
        if window is None: raise RuntimeError("Real zenity picker did not open")
        pid = int(run(["xdotool", "getwindowpid", window]).strip())
        self.selections += 1
        self.snapshot(window, "opened")
        run(["xdotool", "windowfocus", "--sync", window])
        if cancel:
            run(["xdotool", "key", "Escape"])
        else:
            # GTK4 --filename can select a folder in its parent. Use the
            # actual Location UI to enter only a directory, never a file list.
            run(["xdotool", "key", "--clearmodifiers", "ctrl+l", "ctrl+a"])
            run(["xdotool", "type", "--clearmodifiers", "--", str(self.fixtures.resolve()) + "/"])
            run(["xdotool", "key", "--clearmodifiers", "Return"])
            names = [path.name for path in sorted(self.fixtures.glob("*.png"))]
            if len(names) != 5:
                raise RuntimeError("Expected exactly five dedicated PNG fixtures")
            selected = self.select_files(pid, names)
            self.snapshot(window, "selected")
            confirmation = self.confirm(pid)
            if self.evidence is not None:
                (self.evidence / f"picker-{self.selections}.json").write_text(json.dumps({
                    "dialog_pid": pid, "directory_navigation": str(self.fixtures.resolve()),
                    "selected_real_rows": selected, "confirmation_action": confirmation,
                    "selection": "GTK AT-SPI file-list Selection; no fabricated return value",
                }, indent=2) + "\n")
        deadline = time.monotonic() + 10
        while time.monotonic() < deadline:
            visible = subprocess.run(["xdotool", "search", "--onlyvisible", "--class", "zenity"], capture_output=True, text=True)
            if window not in visible.stdout.splitlines(): return
            time.sleep(0.2)
        self.snapshot(window, "failed")
        raise RuntimeError("GTK picker did not close after its real confirmation")

    def memory(self) -> int:
        peak = 0
        for process in Path("/proc").glob("[0-9]*"):
            try:
                executable = (process / "exe").resolve()
                if "wp17i6-private" in str(executable) and executable.name == "matrixflow_native":
                    status = (process / "status").read_text()
                    peak = max(peak, int(re.search(r"VmHWM:\s+(\d+)", status).group(1)))
            except (OSError, AttributeError): pass
        return peak

    def close(self): pass


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--platform", choices=("android", "linux"), required=True)
    parser.add_argument("--repo", type=Path, required=True)
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--flutter", required=True)
    parser.add_argument("--application", type=Path, required=True)
    parser.add_argument("--serial", default="emulator-5580")
    parser.add_argument("--sdk", type=Path)
    parser.add_argument("--file-entry", action="store_true", help="Linux only: driver-selected real PNG files, no GTK claim")
    args = parser.parse_args()
    if args.file_entry and args.platform != "linux": parser.error("--file-entry is Linux only")
    root = args.root.resolve()
    if root.name != "wp17i6-private": raise RuntimeError("Use the dedicated external wp17i6-private root")
    fixtures = root / "fixtures"
    fixtures.mkdir(exist_ok=True)
    samples = args.repo / "docs/evidence/wp17r2/samples/images"
    for target, source in (("01-zh.png", "zh_light_base.png"), ("02-en.png", "en_light_base.png"),
                           ("03-ja.png", "ja_light_base.png"), ("04-zh-duplicate.png", "zh_light_base.png")):
        shutil.copyfile(samples / source, fixtures / target)
    (fixtures / "05-corrupt.png").write_bytes(b"not a png")
    device = Android(args.serial, args.application, args.sdk, root) if args.platform == "android" else Linux(fixtures, args.file_entry, root / "logs")
    label = args.platform + ("-file-entry" if args.file_entry else "")
    log = root / "logs" / ("drive-" + label + ".log")
    report = root / "logs" / ("flow-" + label + ".json")
    env = dict(os.environ, WP17_I6_REPORT=str(report), WP17_I6_FIXTURES=str(fixtures))
    env["WP17_I6_FILE_ENTRY"] = str(args.file_entry).lower()
    command = [args.flutter, "drive", "--no-pub", "--no-build", "--driver=test/wp17_i6_device_driver.dart",
               "--target=test/wp17_i6_device_test.dart", "--dart-define=WP17_I6_DEVICE=true", "-d",
               args.serial if args.platform == "android" else "linux", "--use-application-binary=" + str(args.application)]
    if os.name == "nt" and args.flutter.endswith(".bat"):
        command = ["cmd.exe", "/d", "/c"] + command
    started = time.monotonic()
    peak = 0
    process = None
    seen = set()
    code = 1
    error = None
    try:
        if isinstance(device, Android): device.push(fixtures)
        with log.open("w", encoding="utf-8") as output:
            process = subprocess.Popen(command, cwd=args.repo, env=env, stdout=output, stderr=subprocess.STDOUT)
            while process.poll() is None:
                data = log.read_text(encoding="utf-8", errors="replace")
                for marker in MARKERS:
                    if marker in data and marker not in seen:
                        seen.add(marker)
                        device.choose(marker == MARKERS[0])
                peak = max(peak, device.memory())
                if time.monotonic() - started > 900:
                    process.terminate()
                    raise RuntimeError("Dedicated drive timed out")
                time.sleep(0.3)
            code = process.returncode
        return code
    except Exception as exception:
        error = str(exception)
        raise
    finally:
        if process is not None and process.poll() is None:
            process.terminate()
            try: process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()
        device.close()
        result = {"exit": code, "elapsed_ms": round((time.monotonic() - started) * 1000),
                  "peak_rss_kib": peak, "markers": sorted(seen), "real_picker": not args.file_entry,
                  "error": error}
        (root / "logs" / ("host-" + label + ".json")).write_text(json.dumps(result, indent=2) + "\n")
        print(json.dumps(result))


if __name__ == "__main__":
    raise SystemExit(main())
