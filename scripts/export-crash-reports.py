#!/usr/bin/env python3
"""Copy this run's Yubai crash reports without changing the test result."""
import argparse
import json
import re
import shutil
import tempfile
from pathlib import Path


def is_app_report(path):
    if "yubai" in path.name.lower():
        return True
    if path.suffix.lower() not in {".ips", ".crash", ".diag"}:
        return False
    # Some .ips names omit the process. Match identity in the report, including
    # Apple's two-JSON-object IPS format; never export unrelated app reports.
    text = path.read_text(errors="replace")
    return bool(re.search(r'app\.yubai\.personal|["\'](?:app_name|procName|process|name)["\']\s*:\s*["\']Yubai(?:["\'. /])|/Yubai\.app/', text, re.I))


def export(output, since, home=None, device_sets=None):
    home = home or Path.home()
    output.mkdir(parents=True, exist_ok=True)
    roots = [("host", home / "Library/Logs/DiagnosticReports")]
    sets = device_sets if device_sets is not None else [
        home / "Library/Developer/CoreSimulator/Devices",
        home / "Library/Developer/XCTestDevices",
    ]
    diagnostics, copied, seen = [], [], set()
    for index, device_set in enumerate(sets):
        try:
            devices = sorted(device_set.iterdir()) if device_set.exists() else []
        except OSError as error:
            diagnostics.append(f"{device_set}: {error}")
            continue
        for device in devices:
            if not device.is_dir():
                continue
            # Include shutdown XCTest clones: they may own the process even
            # when the requested simulator UDID has no crash reports.
            for folder in ["Library/Logs/CrashReporter", "Library/Logs/DiagnosticReports", "Logs/CrashReporter"]:
                roots.append((f"simulator-{index}/{device.name}/{folder}", device / "data" / folder))
    for label, root in roots:
        try:
            if not root.exists():
                continue
            for source in sorted(root.rglob("*")):
                try:
                    if not source.is_file():
                        continue
                    modified = source.stat().st_mtime
                    resolved = source.resolve()
                    if modified < since or resolved in seen or not is_app_report(source):
                        continue
                    relative = Path(label) / source.relative_to(root)
                    safe = Path(*(re.sub(r'[\\"`:<>|*?\r\n]', "-", part) for part in relative.parts))
                    destination = output / safe
                    destination.parent.mkdir(parents=True, exist_ok=True)
                    shutil.copy2(source, destination)
                    seen.add(resolved)
                    copied.append({"source": str(source), "file": str(safe), "modified": modified})
                except OSError as error:
                    diagnostics.append(f"{source}: {error}")
        except OSError as error:
            diagnostics.append(f"{root}: {error}")
    (output / "manifest.json").write_text(json.dumps({"since": since, "reports": copied, "errors": diagnostics}, indent=2) + "\n")
    status = f"Exported {len(copied)} Yubai crash reports created/updated during this run"
    if not copied:
        status += "; no matching report available (does not prove the app did not crash)"
    (output / "export-status.txt").write_text("\n".join([status, *diagnostics]) + "\n")
    print(status)
    return copied, diagnostics


def self_test():
    import os
    from unittest.mock import patch
    with tempfile.TemporaryDirectory(prefix="yubai-crash-export-") as directory:
        home = Path(directory) / "home"
        host = home / "Library/Logs/DiagnosticReports"
        host.mkdir(parents=True)
        fresh = host / "Yubai-2026.ips"
        fresh.write_bytes(b'{"app_name":"Yubai"}\n{"faultingThread":0}')
        old = host / "Yubai-old.crash"
        old.write_text("old")
        os.utime(old, (1, 1))
        unrelated = host / "Other.ips"
        unrelated.write_text('{"app_name":"Other"}')
        nested = host / "Retired/report.ips"
        nested.parent.mkdir()
        nested.write_text('{"bundleInfo":{"CFBundleIdentifier":"app.yubai.personal"}}')
        sets = [home / "Library/Developer/CoreSimulator/Devices", home / "Library/Developer/XCTestDevices"]
        device = sets[0] / "requested/data/Library/Logs/CrashReporter/Yubai-device.ips"
        clone = sets[1] / "shutdown-clone/data/Library/Logs/DiagnosticReports/unknown.ips"
        for path in [device, clone]:
            path.parent.mkdir(parents=True)
            path.write_text('{"procName":"Yubai"}')
        copied, errors = export(Path(directory) / "export", since=2, home=home)
        assert len(copied) == 4 and not errors
        assert {row["source"] for row in copied} == {str(p) for p in [fresh, nested, device, clone]}
        for row in copied:
            assert (Path(directory) / "export" / row["file"]).read_bytes() == Path(row["source"]).read_bytes()
        assert fresh.exists() and old.exists() and unrelated.exists() and clone.exists()
        copy = shutil.copy2
        def partly_unreadable(source, destination):
            if source == fresh:
                raise PermissionError("synthetic denied report")
            return copy(source, destination)
        with patch("shutil.copy2", side_effect=partly_unreadable):
            copied, errors = export(Path(directory) / "partial", since=2, home=home)
        assert len(copied) == 3 and len(errors) == 1
        copied, errors = export(Path(directory) / "absent", since=2, home=home / "absent")
        assert not copied and not errors
    print("Crash export self-test passed (host, device, shutdown clone, timestamp, identity, non-fatal partial failure)")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--since", type=float, default=0)
    parser.add_argument("--device-set", type=Path, action="append")
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        self_test()
    else:
        if args.output is None:
            parser.error("--output is required")
        try:
            export(args.output, args.since, device_sets=args.device_set)
        except Exception as error:
            # Missing reports, simulator directories or host permissions must
            # never turn a passing gallery into a failure or mask its failure.
            print("warning: crash report export unavailable: " + str(error))
