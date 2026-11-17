#!/usr/bin/env python3
"""Export lossless simulator watchdog logs and symbolicate Yubai frames offline."""
import argparse
import re
import shutil
import subprocess
import tempfile
from pathlib import Path


def command(*args):
    result = subprocess.run(args, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if result.returncode:
        raise RuntimeError(" ".join(args[:3]) + ": " + result.stderr.strip())
    return result.stdout.strip()


def symbolicate(record, symbols, resolve):
    """Keep raw frames and append atos names using their actual ASLR load base."""
    frames = list(re.finditer(r"image=(Yubai[^\s]*) load=(0x[0-9a-fA-F]+) pc=(0x[0-9a-fA-F]+)", record))
    groups = {}
    for frame in frames:
        image, base, pc = frame.groups()
        groups.setdefault((image, base), []).append(pc)
    names = {}
    for (image, base), pcs in groups.items():
        binary = symbols.get(image)
        if binary is None:
            raise RuntimeError("Missing symbols for " + image)
        unique = list(dict.fromkeys(pcs))
        values = resolve(binary, base, unique).splitlines()
        if len(values) != len(unique) or any(re.fullmatch(r"0x[0-9a-fA-F]+(?: .*)?", v.strip()) for v in values):
            raise RuntimeError("atos did not resolve all frames in " + image)
        names.update({(image, base, pc): value for pc, value in zip(unique, values)})
    return re.sub(r"image=(Yubai[^\s]*) load=(0x[0-9a-fA-F]+) pc=(0x[0-9a-fA-F]+)",
                  lambda m: m.group(0) + "\n     symbol=" + names[m.groups()], record)


def records_from_log(text):
    """Deduplicate printed AX summaries/history; retain every full stderr stack."""
    lines = text.splitlines()
    records = {}
    for index, line in enumerate(lines):
        match = re.search(r"YUBAI-STALL (\d{4}-\S+) pid=(\d+) stall=[\d.]+s (.*)", line)
        if not match:
            continue
        header = match[0]
        status = re.sub(r"source=\S+\s*", "", match[3])
        key = (match[1], match[2], status)
        body = []
        for following in lines[index + 1:]:
            if not re.match(r"(?:  \d+ \d+\s|     (?:image|symbol)=|  MAIN thread SIGUSR2|  STACK capped)", following):
                break
            body.append(following)
        record = header + "\n" + "\n".join(body) + "\n"
        if key not in records or len(record) > len(records[key]):
            records[key] = record
    return "\n".join(records[key] for key in sorted(records))


def simulator_stall_files(device_set, since=None):
    """Host-side discovery also works for Xcode's shutdown/cloned devices."""
    return sorted(file for file in device_set.glob("*/data/Containers/Data/Application/*/Documents/tmp/yubai-stalls-*.log")
                  if since is None or file.stat().st_mtime >= since)


def export(simulator, output, derived_data, log=None, since=None):
    output.mkdir(parents=True, exist_ok=True)
    diagnostics = []
    files = []
    sources = set()
    def copy_log(source, name=None):
        if source.resolve() in sources or since is not None and source.stat().st_mtime < since:
            return
        sources.add(source.resolve())
        raw = output / (name or source.name)
        shutil.copy2(source, raw)
        files.append(raw)
    if log is not None and log.exists():
        # Keep any stacks forwarded by Xcode, and the runner's bounded summaries.
        # Full app stderr forwarding is not guaranteed; host files are primary.
        records = records_from_log(log.read_text(errors="replace"))
        if records:
            raw = output / "xcodebuild-stalls.log"
            raw.write_text(records)
            files.append(raw)
    try:
        data = Path(command("xcrun", "simctl", "get_app_container", simulator, "app.yubai.personal", "data"))
        app = Path(command("xcrun", "simctl", "get_app_container", simulator, "app.yubai.personal", "app"))
    except RuntimeError as error:
        diagnostics.append(str(error))
        app = derived_data / "Build/Products/Debug-iphonesimulator/Yubai.app"
    else:
        for file in sorted((data / "Documents" / "tmp").glob("yubai-stalls-*.log")):
            copy_log(file)
    # The requested UDID can be shutdown while XCTest actually ran its clone.
    # Read the fixture watchdog files on the host; no boot or in-app AX export.
    developer = Path.home() / "Library/Developer"
    for device_set in [developer / "CoreSimulator/Devices", developer / "XCTestDevices"]:
        for file in simulator_stall_files(device_set, since):
            device = file.relative_to(device_set).parts[0]
            copy_log(file, device + "-" + file.name)
    if log is not None and log.exists():
        observed = records_from_log(log.read_text(errors="replace"))
        full_pids = {match[1] for file in files for match in re.finditer(
            r"YUBAI-STALL [^\n]+ pid=(\d+)[^\n]*\n(?:  \d+ \d+|  MAIN thread SIGUSR2)", file.read_text())}
        observed_pids = set(re.findall(r"YUBAI-STALL [^\n]+ pid=(\d+)", observed))
        missing = observed_pids - full_pids
        if missing:
            diagnostics.append("Missing complete watchdog files/stderr for observed pids: " + ", ".join(sorted(missing)))
            (output / "export-status.txt").write_text("\n".join(diagnostics) + "\n")
            raise RuntimeError(diagnostics[-1])
    if not any("image=Yubai" in file.read_text() for file in files):
        for file in files:
            (output / file.name).with_suffix(".symbolicated.txt").write_text(file.read_text())
        status = f"Exported {len(files)} complete watchdog logs; no Yubai frames need symbolication"
        (output / "export-status.txt").write_text(status + "\n")
        print(status)
        return
    symbols_dir = output / "symbols"
    symbols_dir.mkdir(exist_ok=True)
    symbols = {}
    # dSYM names vary with ENABLE_DEBUG_DYLIB; inspect only this run's Products.
    products = derived_data / "Build" / "Products"
    if products.exists():
        for dsym in products.glob("Debug-iphonesimulator/Yubai*.dSYM"):
            shutil.copytree(dsym, symbols_dir / dsym.name, dirs_exist_ok=True)
        for binary in symbols_dir.glob("*.dSYM/Contents/Resources/DWARF/*"):
            symbols[binary.name] = binary
    for name in ["Yubai", "Yubai.debug.dylib"]:
        binary = app / name
        if binary.exists():
            shutil.copy2(binary, symbols_dir / name)
            symbols.setdefault(name, symbols_dir / name)
    for file in files:
        raw = output / file.name
        record = raw.read_text()
        try:
            result = symbolicate(record, symbols, lambda binary, base, pcs:
                command("xcrun", "atos", "-arch", "arm64", "-o", str(binary), "-l", base, *pcs))
            raw.with_suffix(".symbolicated.txt").write_text(result)
        except RuntimeError as error:
            diagnostics.append(file.name + ": " + str(error))
    # A shutdown/missing simulator is harmless when stderr and build products
    # supplied the complete records and symbols. Symbolication failures are not.
    failures = sum(1 for line in diagnostics if any(line.startswith(file.name + ":") for file in files))
    diagnostics.insert(0, f"Exported {len(files)} watchdog logs (host device/clone files + available stderr)")
    (output / "export-status.txt").write_text("\n".join(diagnostics) + "\n")
    print("\n".join(diagnostics))
    if failures:
        raise RuntimeError("Stall symbolication failed; raw logs and matching binaries are retained")


def self_test():
    # Exceed XCTest's single-value cap, preserving the bottom app frame.
    record = "YUBAI-STALL MAIN thread unresponsive\n" + "system frame\n" * 300
    record += "image=Yubai.debug.dylib load=0x100000 pc=0x100123\n"
    calls = []
    def resolve(binary, base, pcs):
        calls.append((binary, base, pcs))
        return "Yubai.AppStore.loadLedger() (YubaiApp.swift:600)"
    result = symbolicate(record, {"Yubai.debug.dylib": Path("synthetic")}, resolve)
    assert record.splitlines()[-1] in result and len(result) > 4000
    assert "AppStore.loadLedger()" in result and calls[0][1:] == ("0x100000", ["0x100123"])
    header = "YUBAI-STALL 2026-11-16T12:00:00.000Z pid=1 stall=5.000s source=app MAIN thread unresponsive"
    stack = header + "\n  00 0 Yubai.debug.dylib 0x100123 AppStore.loadLedger + 3 [0x100123]\n     image=Yubai.debug.dylib load=0x100000 pc=0x100123\n"
    captured = records_from_log(header + "\nquery noise\n" + stack + "\n" + stack)
    assert captured.count(header) == 1 and "AppStore.loadLedger" in captured and "pc=0x100123" in captured
    assert "source=app" in symbolicate(captured, {"Yubai.debug.dylib": Path("synthetic")}, resolve)
    for symbols, resolver in [({}, resolve), ({"Yubai.debug.dylib": Path("synthetic")}, lambda *args: "0x100123")]:
        try:
            symbolicate(record, symbols, resolver)
        except RuntimeError:
            pass
        else:
            raise AssertionError("Missing symbol names must be reported")
    # Compile the production classifier itself; no Apple SDK or packages needed.
    root = Path(__file__).resolve().parents[1]
    sample = r'''#include <assert.h>
#include "StallSource.h"
int main(void) {
    char *audit[] = {"Yubai capture_main", "UIKitCore _axAuditUpdateRowHeight", "Yubai $s5Yubai0A3AppV5$mainyyFZ"};
    char *snapshot[] = {"libsystem_trace _os_trace_writev", "XCTAutomationSupport matchingSnapshotsInSnapshotTree"};
    char *app[] = {"UIKitCore _axAuditCheckDynamicTextSupport", "Yubai.debug.dylib PaperShadowCache.image"};
    char *environment[] = {"Foundation ProcessInfo.environment", "Yubai $s7SwiftUI17EnvironmentValuesV5YubaiE17yubaiReduceMotionSbvg"};
    char *runtime[] = {"SwiftUICore DynamicPropertyCache", "Yubai $s5Yubai16AddEntryCalendarV7SwiftUI4ViewAadEP05_makeG4ListTW"};
    char *system[] = {"UIKitCore UIKeyboardTaskQueue", "Yubai __debug_main_executable_dylib_entry_point"};
    char *truncated[YUBAI_STALL_MAX_FRAMES];
    for (int i = 0; i < YUBAI_STALL_MAX_FRAMES; i++) { truncated[i] = "SwiftUICore layout"; }
    assert(strcmp(yubai_stall_source(audit, 3), "xctest-audit") == 0);
    assert(strcmp(yubai_stall_source(snapshot, 2), "xctest-snapshot") == 0);
    assert(strcmp(yubai_stall_source(app, 2), "app") == 0);
    assert(strcmp(yubai_stall_source(environment, 2), "app") == 0);
    assert(strcmp(yubai_stall_source(runtime, 2), "system") == 0);
    assert(strcmp(yubai_stall_source(system, 2), "system") == 0);
    assert(strcmp(yubai_stall_source(NULL, 0), "unknown") == 0);
    assert(strcmp(yubai_stall_source(truncated, YUBAI_STALL_MAX_FRAMES), "unknown") == 0);
    return 0;
}
'''
    with tempfile.TemporaryDirectory(prefix="yubai-stall-source-") as directory:
        binary = Path(directory) / "source-tests"
        compiler = shutil.which("cc") or shutil.which("clang")
        if compiler is None:
            raise RuntimeError("Stall source self-test requires a C compiler")
        subprocess.run([compiler, "-std=c11", "-Wall", "-Wextra", "-Werror", "-x", "c", "-",
                        "-I", str(root / "Sources/CUITestWatchdog"), "-o", str(binary)], input=sample, text=True, check=True)
        subprocess.run([str(binary)], check=True)
        device_set = Path(directory) / "Devices"
        clone = device_set / "shutdown-clone/data/Containers/Data/Application/fixture/Documents/tmp/yubai-stalls-1.log"
        clone.parent.mkdir(parents=True)
        clone.write_text(stack)
        assert simulator_stall_files(device_set) == [clone]
        assert simulator_stall_files(device_set, clone.stat().st_mtime + 1) == []
        # Exercise the actual exporter with summary-only runner output and a
        # shutdown XCTest clone: full app stderr forwarding is unnecessary.
        from unittest.mock import patch
        home = Path(directory) / "home"
        native = home / "Library/Developer/XCTestDevices/clone/data/Containers/Data/Application/fixture/Documents/tmp/yubai-stalls-1.log"
        native.parent.mkdir(parents=True)
        native.write_text(stack)
        derived = Path(directory) / "DerivedData"
        binary_dir = derived / "Build/Products/Debug-iphonesimulator/Yubai.app"
        binary_dir.mkdir(parents=True)
        (binary_dir / "Yubai.debug.dylib").write_bytes(b"synthetic symbols")
        runner = Path(directory) / "runner.log"
        runner.write_text("GALLERY-STALL test " + header + "\n")
        def offline(*args):
            if "get_app_container" in args:
                raise RuntimeError("synthetic simulator Shutdown")
            if "atos" in args:
                return "\n".join("Yubai.AppStore.loadLedger()" for _ in args[args.index("-l") + 2:])
            raise AssertionError(args)
        with patch("pathlib.Path.home", return_value=home), patch(__name__ + ".command", side_effect=offline):
            output = Path(directory) / "export"
            export("synthetic", output, derived, runner)
            assert (output / "clone-yubai-stalls-1.log").read_text() == stack
            assert "AppStore.loadLedger()" in (output / "clone-yubai-stalls-1.symbolicated.txt").read_text()
            native.unlink()
            try:
                export("synthetic", Path(directory) / "missing-export", derived, runner)
            except RuntimeError as error:
                assert "Missing complete watchdog" in str(error)
            else:
                raise AssertionError("A summary must never substitute for the complete watchdog record")
    print("Stall export and source classifier self-tests passed")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--simulator")
    parser.add_argument("--output", type=Path)
    parser.add_argument("--derived-data", type=Path)
    parser.add_argument("--log", type=Path, help="Complete xcodebuild stderr, including cloned/shutdown simulators")
    parser.add_argument("--since", type=float, help="Only collect files modified during this test run (Unix seconds)")
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        self_test()
    else:
        if not all([args.simulator, args.output, args.derived_data]):
            parser.error("--simulator, --output and --derived-data are required")
        export(args.simulator, args.output, args.derived_data, args.log, args.since)
