#!/usr/bin/env python3
"""Run the actual Foundation/XCTest UI helpers and app probe contract on Linux."""
from pathlib import Path
import os
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
subprocess.run([sys.executable, str(ROOT / "scripts/tests/test_shards.py")], check=True)
UI = ROOT / "Tests/YubaiUITests"
names = ["Round47FrameWaitTests", "Round47RevealProgressTests", "Round47ViewportGeometryTests",
         "Round47KeyboardOwnershipTests", "Round47GalleryProcessTests"]
helpers = ["UIFrameWait", "UIConditionWait", "UIRevealProgress", "UIRevealMotionWait",
           "UIViewportGeometry", "UIKeyboardOwnership", "GalleryProcessHistory"]
tests = [UI / (name + ".swift") for name in names]
names.append("UIWindowMetricsContractTests")
tests.append(ROOT / "scripts/tests/UIWindowMetricsContractTests.swift")
cases = []
for name, path in zip(names, tests):
    methods = re.findall(r"^    func (test\w+)\(", path.read_text(), re.M)
    cases.append("testCase([\n" + ",\n".join(f'("{m}", {name}.{m})' for m in methods) + "\n])")
swiftc = shutil.which("swiftc") or "/opt/swift-rootfs/usr/bin/swiftc"
env = dict(os.environ, CLANG_MODULE_CACHE_PATH="/tmp/r47r/cmc", SWIFTPM_MODULECACHE_OVERRIDE="/tmp/r47r/smc")
with tempfile.TemporaryDirectory(prefix="yubai-ui-helpers-") as directory:
    out = Path(directory)
    main = out / "main.swift"
    main.write_text("import XCTest\nXCTMain([\n" + ",\n".join(cases) + "\n])\n")
    sources = [UI / (name + ".swift") for name in helpers] + tests
    # The UIKit half is excluded on Linux; the exact app dictionary/serializer
    # and failure-packet implementation are compiled, without extraction/copies.
    sources.append(ROOT / "Sources/YubaiApp/UITestSupport.swift")
    subprocess.run([swiftc, "-swift-version", "5", "-D", "DEBUG", *map(str, sources),
                    str(main), "-o", str(out / "tests")], env=env, check=True)
    subprocess.run([str(out / "tests")], env=env, check=True)
