#!/usr/bin/env python3
"""Pure Python contracts for targeted CI shards; no Apple tools or dependencies."""
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import textwrap
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))


def load_script(name):
    spec = importlib.util.spec_from_file_location(name.replace("-", "_"), ROOT / "scripts" / f"{name}.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


UI = load_script("ui-test-shards")
GALLERY = load_script("gallery-shards")


def compact(value):
    return json.dumps(value, separators=(",", ":"))


class ShardTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.ui_rows = UI.matrix(ROOT)["include"]
        cls.gallery_rows = GALLERY.matrix(ROOT)["include"]
        cls.home = "ui-Round47HomeFlowTests"
        cls.exact = cls.home + "-04"

    def cli(self, script, *args):
        return subprocess.run([sys.executable, str(ROOT / "scripts" / f"{script}.py"), *args],
                              cwd=ROOT, capture_output=True, text=True)

    def test_legacy_ui_bytes_with_empty_parts_and_every_only_case(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            tests = root / "Tests/YubaiUITests"
            tests.mkdir(parents=True)
            expected = [{"part": "unit", "tests": ["YubaiCoreTests"]}]
            for name in ("AlphaTests", "Round47FlowTests"):
                methods = [f"testCase{i:02d}" for i in range(17)]
                (tests / f"{name}.swift").write_text(f"final class {name}: YubaiUITestCase {{\n"
                    + "".join(f"    func {method}() {{}}\n" for method in reversed(methods)) + "}\n")
                for number, start in enumerate(range(0, 17, 8), 1):
                    expected.append({"part": f"ui-{name}-{number:02d}", "tests":
                                     [f"YubaiUITests/{name}/{method}" for method in methods[start:start + 8]]})
            for only in ("", "r47-", "dark-walk", "arbitrary-prefix"):
                with self.subTest(only=only):
                    rows = expected if not only else [row for row in expected
                                                      if row["part"] == "unit" or "Round47" in row["part"]]
                    self.assertEqual(compact(UI.matrix(root, only=only, parts="")), compact({"include": rows}))
            self.assertEqual(UI.matrix(root, only="r47-", parts="ui-AlphaTests"), {"include": []})

    def test_legacy_gallery_bytes_with_empty_parts_for_every_valid_prefix(self):
        prefixes = {part[:end] for part, _ in GALLERY.PARTS for end in range(len(part) + 1)}
        for only in sorted(prefixes):
            with self.subTest(only=only):
                rows = [{"part": part, "walks": walk} for part, walk in GALLERY.PARTS if part.startswith(only)]
                self.assertEqual(compact(GALLERY.matrix(ROOT, only=only, parts="")), compact({"include": rows}))

    def test_invalid_gallery_only_still_fails_without_parts(self):
        with self.assertRaisesRegex(ValueError, "No gallery parts start with"):
            GALLERY.matrix(ROOT, only="no-such-prefix", parts="")

    def test_exact_selection_has_no_implicit_unit_and_keeps_inventory_order(self):
        parts = self.exact + ",ui-Round47ButlerFlowTests-02"
        expected = [row for row in self.ui_rows if row["part"] in parts.split(",")]
        self.assertEqual(len(expected), 2)
        self.assertEqual(UI.matrix(ROOT, parts=parts)["include"], expected)

    def test_class_selection_expands_all_shards_without_duplicates(self):
        expected = [row for row in self.ui_rows if row["part"].startswith(self.home + "-")]
        self.assertGreater(len(expected), 1)
        self.assertEqual(UI.matrix(ROOT, parts=f"{self.home}, {self.exact} {self.home}")["include"], expected)

    def test_class_selection_tracks_sorted_methods_when_a_new_test_moves_shards(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            tests = root / "Tests/YubaiUITests"
            tests.mkdir(parents=True)
            source = tests / "FlowTests.swift"
            methods = [f"testCase{i:02d}" for i in range(16)]
            def write():
                source.write_text("final class FlowTests: XCTestCase {\n"
                                  + "".join(f"    func {method}() {{}}\n" for method in reversed(methods)) + "}\n")
            write()
            before = UI.matrix(root, parts="ui-FlowTests")["include"]
            methods.insert(0, "testAddedFirst")
            write()
            after = UI.matrix(root, parts="ui-FlowTests")["include"]
            self.assertEqual((len(before), len(after)), (2, 3))
            self.assertNotEqual(before[0]["tests"], after[0]["tests"])
            self.assertEqual([test for row in after for test in row["tests"]],
                             [f"YubaiUITests/FlowTests/{method}" for method in sorted(methods)])

    def test_unit_is_kept_only_when_listed(self):
        self.assertEqual(UI.matrix(ROOT, parts="unit"), {"include": [self.ui_rows[0]]})
        selected = UI.matrix(ROOT, only="r47-", parts=f"{self.home},unit")["include"]
        self.assertEqual(selected[0], self.ui_rows[0])
        self.assertEqual(len(selected), 1 + len(UI.matrix(ROOT, parts=self.home)["include"]))

    def test_parts_apply_after_only(self):
        selected = GALLERY.matrix(ROOT, only="r47-", parts="dark-walk,r47-b-light")
        self.assertEqual(selected, {"include": [{"part": "r47-b-light", "walks": "testWalk47BatchB"}]})
        self.assertEqual(GALLERY.matrix(ROOT, only="r47-", parts="dark-walk"), {"include": []})
        self.assertEqual(GALLERY.matrix(ROOT, only="no-such-prefix", parts=self.home), {"include": []})

    def test_shared_list_allows_commas_spaces_newlines_and_duplicate_names(self):
        parts = f"  ,{self.exact},\n unit\tdark-walk, {self.exact}, "
        UI.validate_parts(ROOT, parts)
        self.assertEqual(UI.matrix(ROOT, parts=parts)["include"],
                         [row for row in self.ui_rows if row["part"] in ("unit", self.exact)])
        self.assertEqual(GALLERY.matrix(ROOT, parts=parts)["include"],
                         [row for row in self.gallery_rows if row["part"] == "dark-walk"])

    def test_other_script_names_produce_empty_sides(self):
        self.assertEqual(UI.matrix(ROOT, parts="dark-walk,r47-b-light"), {"include": []})
        self.assertEqual(GALLERY.matrix(ROOT, parts=f"unit,{self.home},{self.exact}"), {"include": []})

    def test_validation_accepts_the_full_namespace(self):
        names = [row["part"] for row in self.ui_rows + self.gallery_rows]
        names += [row["part"].rsplit("-", 1)[0] for row in self.ui_rows if row["part"].startswith("ui-")]
        UI.validate_parts(ROOT, ",".join(names))
        UI.validate_parts(ROOT, "")

    def test_unknown_exact_class_case_and_prefix_names_fail_readably(self):
        for typo in ("dark-wa", "ui-Round47HomeFlowTest", self.home + "-99", self.home + "-4", "UNIT"):
            with self.subTest(typo=typo):
                result = self.cli("ui-test-shards", "--validate-parts", "--parts", f"dark-walk,{self.exact},{typo}")
                self.assertEqual(result.returncode, 2)
                self.assertIn("Unknown shard part(s): " + typo, result.stderr)
                self.assertNotIn("Traceback", result.stderr)
                self.assertEqual(result.stdout, "")

    def test_validation_ignores_only_filter_and_runs_before_output(self):
        legacy = next(row["part"] for row in self.ui_rows
                      if row["part"].startswith("ui-") and "Round47" not in row["part"])
        result = self.cli("ui-test-shards", "--only", "r47-", "--parts", legacy, "--validate-parts")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout), {"include": []})

    def test_cli_json_and_github_outputs_include_empty_side_flags(self):
        for script, module, parts in (("ui-test-shards", UI, self.home), ("ui-test-shards", UI, "dark-walk"),
                                      ("gallery-shards", GALLERY, "dark-walk"), ("gallery-shards", GALLERY, self.home)):
            for parts in ("", parts):
                with self.subTest(script=script, parts=parts):
                    expected = module.matrix(ROOT, parts=parts)
                    result = self.cli(script, "--parts", parts)
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertEqual(result.stdout, compact(expected) + "\n")
                    result = self.cli(script, "--parts", parts, "--github-output")
                    self.assertEqual(result.returncode, 0, result.stderr)
                    outputs = dict(line.split("=", 1) for line in result.stdout.splitlines())
                    self.assertEqual(outputs["matrix"], compact(expected))
                    self.assertEqual(outputs["has-shards"], str(bool(expected["include"])).lower())


class ResultGateTests(unittest.TestCase):
    """Execute the actual final workflow shell so empty sides cannot hide failures."""
    def test_result_gate_modes_empty_sides_and_failures(self):
        workflow = (ROOT / ".github/workflows/ios.yml").read_text()
        job = workflow.split("\n  simulator-results:\n", 1)[1].split("\n  gallery-shards:\n", 1)[0]
        script = textwrap.dedent(job.split("        run: |\n", 1)[1])
        with tempfile.TemporaryDirectory() as directory:
            base = dict(os.environ, GITHUB_STEP_SUMMARY=str(Path(directory) / "summary"), SHARDS_RESULT="success")
            for mode in ("tests", "gallery", "both"):
                for tests in (True, False):
                    for gallery in (True, False):
                        env = dict(base, MODE=mode, TESTS_HAS_SHARDS=str(tests).lower(),
                                   TESTS_RESULT="success" if tests and mode != "gallery" else "skipped",
                                   GALLERY_HAS_SHARDS=str(gallery).lower(),
                                   GALLERY_SHARDS_RESULT="success" if mode != "tests" else "skipped",
                                   GALLERY_RESULT="success" if gallery and mode != "tests" else "skipped")
                        def run(values):
                            return subprocess.run(["bash", "-e", "-c", script], env=values,
                                                  capture_output=True, text=True).returncode
                        with self.subTest(mode=mode, tests=tests, gallery=gallery):
                            self.assertEqual(run(env), 0)
                            self.assertNotEqual(run(dict(env, SHARDS_RESULT="failure")), 0)
                            if mode != "gallery":
                                for failure in ("failure", "cancelled", "skipped" if tests else "success"):
                                    self.assertNotEqual(run(dict(env, TESTS_RESULT=failure)), 0)
                                self.assertNotEqual(run(dict(env, TESTS_HAS_SHARDS="")), 0)
                            if mode != "tests":
                                self.assertNotEqual(run(dict(env, GALLERY_SHARDS_RESULT="failure")), 0)
                                for failure in ("failure", "cancelled", "skipped" if gallery else "success"):
                                    self.assertNotEqual(run(dict(env, GALLERY_RESULT=failure)), 0)
                                self.assertNotEqual(run(dict(env, GALLERY_HAS_SHARDS="")), 0)


if __name__ == "__main__":
    unittest.main(verbosity=2)
