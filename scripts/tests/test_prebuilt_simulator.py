#!/usr/bin/env python3
"""Validate simulator artifacts without Xcode or a simulator."""
import importlib.util
from pathlib import Path
import plistlib
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("prebuilt_simulator", ROOT / "scripts/prebuilt_simulator.py")
PREBUILT = importlib.util.module_from_spec(spec)
spec.loader.exec_module(PREBUILT)

BUNDLES = ("YubaiCoreTests", "YubaiDesignSystemTests", "YubaiUITests")


class PrebuiltSimulatorTests(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.derived = Path(directory.name) / "DerivedData"
        self.products = self.derived / "Build/Products"
        debug = self.products / "Debug-iphonesimulator"
        app = debug / "Yubai.app"
        app.mkdir(parents=True)
        self.targets = {}
        for name in (*BUNDLES, "UnexpectedTests"):
            bundle = (app / "PlugIns" if name == "YubaiDesignSystemTests" else debug) / (name + ".xctest")
            bundle.mkdir(parents=True)
            self.targets[name] = {"TestBundlePath": "__TESTROOT__/" + bundle.relative_to(self.products).as_posix()}
            if name == "YubaiDesignSystemTests":
                self.targets[name]["TestHostPath"] = "__TESTROOT__/Debug-iphonesimulator/Yubai.app"
        dwarf = debug / "Yubai.app.dSYM/Contents/Resources/DWARF/Yubai"
        dwarf.parent.mkdir(parents=True)
        dwarf.touch()
        self.xctestrun = self.products / "Yubai_iphonesimulator.xctestrun"
        identity = patch.object(PREBUILT, "identity", return_value={
            "revision": "test-revision", "xcode": "Xcode 26", "developer_dir": "/Applications/Xcode.app/Contents/Developer",
        })
        identity.start()
        self.addCleanup(identity.stop)

    def write_run(self, names, test_plan):
        targets = {name: self.targets[name] for name in names}
        data = {"TestConfigurations": [{"TestTargets": list(targets.values())}]} if test_plan else targets
        with self.xctestrun.open("wb") as file:
            plistlib.dump(data, file)

    def test_record_and_reuse_accept_all_three_bundles(self):
        for test_plan in (False, True):
            with self.subTest(test_plan=test_plan):
                self.write_run(BUNDLES, test_plan)
                self.assertEqual(PREBUILT.validate_prebuilt(str(self.derived), record=True), self.xctestrun)
                self.assertEqual(PREBUILT.validate_prebuilt(str(self.derived)), self.xctestrun)

    def test_missing_or_extra_bundles_are_rejected(self):
        invalid = [tuple(name for name in BUNDLES if name != missing) for missing in BUNDLES]
        invalid.append((*BUNDLES, "UnexpectedTests"))
        for test_plan in (False, True):
            self.write_run(BUNDLES, test_plan)
            PREBUILT.validate_prebuilt(str(self.derived), record=True)
            for names in invalid:
                self.write_run(names, test_plan)
                for record in (False, True):
                    with self.subTest(test_plan=test_plan, names=names, record=record):
                        with self.assertRaisesRegex(ValueError, "Expected test bundles"):
                            PREBUILT.validate_prebuilt(str(self.derived), record=record)


if __name__ == "__main__":
    unittest.main(verbosity=2)
