#!/usr/bin/env python3
"""Export lossless simulator watchdog logs and symbolicate Yubai frames offline."""
import argparse
import re
import shutil
import subprocess
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


def export(simulator, output, derived_data):
    output.mkdir(parents=True, exist_ok=True)
    diagnostics = []
    try:
        data = Path(command("xcrun", "simctl", "get_app_container", simulator, "app.yubai.personal", "data"))
        app = Path(command("xcrun", "simctl", "get_app_container", simulator, "app.yubai.personal", "app"))
    except RuntimeError as error:
        # Unit-only shards and failed installs legitimately have no app container.
        (output / "export-status.txt").write_text(str(error) + "\n")
        return
    files = sorted((data / "Documents" / "tmp").glob("yubai-stalls-*.log"))
    for file in files:
        shutil.copy2(file, output / file.name)
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
    diagnostics.insert(0, f"Exported {len(files)} complete watchdog logs from {data}")
    (output / "export-status.txt").write_text("\n".join(diagnostics) + "\n")
    print("\n".join(diagnostics))
    if len(diagnostics) > 1:
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
    for symbols, resolver in [({}, resolve), ({"Yubai.debug.dylib": Path("synthetic")}, lambda *args: "0x100123")]:
        try:
            symbolicate(record, symbols, resolver)
        except RuntimeError:
            pass
        else:
            raise AssertionError("Missing symbol names must be reported")
    print("Stall export self-test passed")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--simulator")
    parser.add_argument("--output", type=Path)
    parser.add_argument("--derived-data", type=Path)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        self_test()
    else:
        if not all([args.simulator, args.output, args.derived_data]):
            parser.error("--simulator, --output and --derived-data are required")
        export(args.simulator, args.output, args.derived_data)
