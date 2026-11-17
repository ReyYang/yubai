#!/usr/bin/env python3
"""Pure Python contracts for CI tiers and targeted shards; no Apple tools or dependencies."""
from collections import Counter
from contextlib import redirect_stderr, redirect_stdout
import importlib.util
import io
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import textwrap
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))


def load_script(name):
    spec = importlib.util.spec_from_file_location(name.replace("-", "_"), ROOT / "scripts" / f"{name}.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


UI = load_script("ui-test-shards")
GALLERY = load_script("gallery-shards")
DIAGNOSTICS = load_script("diagnostic-summary")


def compact(value):
    return json.dumps(value, separators=(",", ":"))


def fixture(root, manifest=""):
    tests = root / "Tests/YubaiUITests"
    tests.mkdir(parents=True)
    (root / "scripts").mkdir()
    (root / "scripts/test-ui-helpers.py").write_text("names = " + repr(list(UI.LINUX_ONLY_CLASSES)))
    (root / UI.DIAGNOSTIC_MANIFEST).write_text(manifest)
    return tests


class ShardTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.ui_rows = UI.matrix(ROOT)["include"]
        cls.gallery_rows = GALLERY.matrix(ROOT)["include"]
        cls.home = "ui-Round47HomeFlowTests"
        cls.exact = cls.home + "-02"
        cls.diag = "diag-Round47HomeFlowTests"

    def cli(self, script, *args):
        return subprocess.run([sys.executable, str(ROOT / "scripts" / f"{script}.py"), *args],
                              cwd=ROOT, capture_output=True, text=True)

    def test_unlisted_ui_keeps_sorted_gate_shards_with_every_only_case(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            tests = fixture(root)
            expected = [{"part": "unit", "tests": ["YubaiCoreTests"], "blocking": True}]
            for name in ("AlphaTests", "Round47FlowTests"):
                methods = [f"testCase{i:02d}" for i in range(17)]
                (tests / f"{name}.swift").write_text(f"final class {name}: YubaiUITestCase {{\n"
                    + "".join(f"    func {method}() {{}}\n" for method in reversed(methods)) + "}\n")
                for number, start in enumerate(range(0, 17, 8), 1):
                    expected.append({"part": f"ui-{name}-{number:02d}", "tests":
                                     [f"YubaiUITests/{name}/{method}" for method in methods[start:start + 8]],
                                     "blocking": True})
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

    def test_diagnostic_exact_and_class_parts_mix_with_gate_unit_and_gallery(self):
        parts = f"{self.diag},{self.diag}-02 {self.exact},unit dark-walk"
        UI.validate_parts(ROOT, parts)
        selected = UI.matrix(ROOT, only="r47", parts=parts)["include"]
        self.assertEqual(selected, [row for row in self.ui_rows
                                   if row["part"] in ("unit", self.exact)
                                   or row["part"].startswith(self.diag + "-")])
        self.assertEqual(sum(not row["blocking"] for row in selected), 2)
        self.assertEqual(GALLERY.matrix(ROOT, parts=parts)["include"],
                         [row for row in self.gallery_rows if row["part"] == "dark-walk"])
        self.assertEqual(UI.matrix(ROOT, parts=self.diag + "-02")["include"],
                         [row for row in self.ui_rows if row["part"] == self.diag + "-02"])

    def test_inventory_is_partitioned_exactly_once_and_excluded_helpers_stay_on_linux(self):
        source_tests = []
        excluded = []
        for path in (ROOT / "Tests/YubaiUITests").glob("*.swift"):
            name = None
            for line in path.read_text().splitlines():
                declaration = re.match(r"(?:final )?class (\w+): (?:XCTestCase|YubaiUITestCase)\s*\{", line)
                if declaration:
                    name = declaration[1]
                method = re.match(r"    func (test\w+)\s*\(", line)
                if method and name != "ScreenGalleryTests":
                    self.assertIsNotNone(name, path)
                    selector = f"YubaiUITests/{name}/{method[1]}"
                    (excluded if name in UI.LINUX_ONLY_CLASSES else source_tests).append(selector)
        scheduled = [test for row in self.ui_rows for test in row["tests"] if test != "YubaiCoreTests"]
        self.assertEqual(Counter(scheduled), Counter(source_tests))
        self.assertEqual(len(scheduled), len(set(scheduled)))
        self.assertTrue(excluded)
        self.assertFalse(set(scheduled) & set(excluded))
        diagnostics = {line.split("#", 1)[0].strip() for line in (ROOT / UI.DIAGNOSTIC_MANIFEST).read_text().splitlines()}
        diagnostics.discard("")
        self.assertEqual({test.removeprefix("YubaiUITests/") for row in self.ui_rows
                          if not row["blocking"] for test in row["tests"]}, diagnostics)
        for row in self.ui_rows:
            self.assertEqual(row["part"].startswith("diag-"), not row["blocking"])
        expected = [row for row in self.ui_rows if row["part"] == "unit" or "Round47" in row["part"]]
        self.assertEqual(UI.matrix(ROOT, only="r47")["include"], expected)
        self.assertTrue(any(not row["blocking"] for row in expected))

    def test_manifest_comments_and_strict_unknown_duplicate_validation(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            tests = fixture(root, "# reviewed\n\nFlowTests/testKnown # diagnostic\n")
            (tests / "FlowTests.swift").write_text("class FlowTests: XCTestCase {\n    func testKnown() {}\n}\n")
            rows = UI.matrix(root)["include"]
            self.assertEqual([row["part"] for row in rows], ["unit", "diag-FlowTests-01"])
            for text, message in (("FlowTests/testMissing", "Unknown diagnostic test"),
                                  ("MissingTests/testKnown", "Unknown diagnostic test"),
                                  ("FlowTests/testKnown\nFlowTests/testKnown # duplicate", "Duplicate diagnostic test")):
                with self.subTest(text=text):
                    (root / UI.DIAGNOSTIC_MANIFEST).write_text(text)
                    with self.assertRaisesRegex(ValueError, message):
                        UI.matrix(root, parts="dark-walk")
                    script = root / "scripts/ui-test-shards.py"
                    script.write_text((ROOT / "scripts/ui-test-shards.py").read_text())
                    result = subprocess.run([sys.executable, str(script)], capture_output=True, text=True)
                    self.assertEqual(result.returncode, 2)
                    self.assertIn(message, result.stderr)
                    self.assertNotIn("Traceback", result.stderr)
                    self.assertEqual(result.stdout, "")

    def test_exclusion_fails_if_the_actual_linux_runner_list_loses_a_class(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            tests = fixture(root)
            (tests / "FlowTests.swift").write_text("class FlowTests: XCTestCase {\n    func testKnown() {}\n}\n")
            for missing in UI.LINUX_ONLY_CLASSES:
                (root / "scripts/test-ui-helpers.py").write_text(
                    "names = " + repr([name for name in UI.LINUX_ONLY_CLASSES if name != missing])
                    + f"\n# {missing} is not actually run\n")
                with self.subTest(missing=missing), self.assertRaisesRegex(ValueError, "Mac-excluded classes missing.*" + missing):
                    UI.matrix(root)

    def test_linux_only_tests_cannot_be_reintroduced_as_diagnostics(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            name = UI.LINUX_ONLY_CLASSES[0]
            tests = fixture(root, name + "/testKnown")
            (tests / (name + ".swift")).write_text(f"class {name}: XCTestCase {{\n    func testKnown() {{}}\n}}\n")
            with self.assertRaisesRegex(ValueError, "Linux-only class"):
                UI.matrix(root)

    def test_class_selection_tracks_sorted_methods_when_a_new_test_moves_shards(self):
        for prefix in ("ui", "diag"):
            with self.subTest(prefix=prefix), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                source = fixture(root) / "FlowTests.swift"
                methods = [f"testCase{i:02d}" for i in range(16)]
                def write():
                    source.write_text("final class FlowTests: XCTestCase {\n"
                                      + "".join(f"    func {method}() {{}}\n" for method in reversed(methods)) + "}\n")
                    if prefix == "diag":
                        (root / UI.DIAGNOSTIC_MANIFEST).write_text("\n".join("FlowTests/" + method for method in methods))
                write()
                before = UI.matrix(root, parts=prefix + "-FlowTests")["include"]
                methods.insert(0, "testAddedFirst")
                write()
                after = UI.matrix(root, parts=prefix + "-FlowTests")["include"]
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
        self.assertEqual(GALLERY.matrix(ROOT, parts=f"unit,{self.home},{self.exact},{self.diag},{self.diag}-01"), {"include": []})

    def test_validation_accepts_the_full_namespace(self):
        names = [row["part"] for row in self.ui_rows + self.gallery_rows]
        names += [row["part"].rsplit("-", 1)[0] for row in self.ui_rows if row["part"].startswith(("ui-", "diag-"))]
        UI.validate_parts(ROOT, ",".join(names))
        UI.validate_parts(ROOT, "")

    def test_unknown_exact_class_case_and_prefix_names_fail_readably(self):
        for typo in ("dark-wa", "ui-Round47HomeFlowTest", self.home + "-99", self.home + "-4", "UNIT",
                     "diag-Round47HomeFlowTest", self.diag + "-99", self.diag + "-1", "diag-Round47FrameWaitTests"):
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
        for script, module, parts in (("ui-test-shards", UI, self.home), ("ui-test-shards", UI, self.diag),
                                      ("ui-test-shards", UI, "dark-walk"),
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
                    if module is UI:
                        for tier, blocking in (("gate", True), ("diagnostic", False)):
                            rows = [row for row in expected["include"] if row["blocking"] == blocking]
                            self.assertEqual(outputs[tier + "-matrix"], compact({"include": rows}))
                            self.assertEqual(outputs["has-" + tier + "-shards"], str(bool(rows)).lower())


class ResultGateTests(unittest.TestCase):
    """Execute the actual final workflow shell so empty sides cannot hide failures."""
    def test_result_gate_modes_empty_sides_and_failures(self):
        workflow = (ROOT / ".github/workflows/ios.yml").read_text()
        job = workflow.split("\n  simulator-results:\n", 1)[1].split("\n  gallery-shards:\n", 1)[0]
        script = textwrap.dedent(job.split("        run: |\n", 1)[1].split("\n      - name: Non-blocking diagnostics", 1)[0])
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
                            for diagnostics in ("success", "failure", "cancelled", "skipped"):
                                self.assertEqual(run(dict(env, DIAGNOSTICS_RESULT=diagnostics)), 0)
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


class DiagnosticSummaryTests(unittest.TestCase):
    def test_counts_failed_jobs_and_lists_incomplete_jobs_separately(self):
        parts = [f"diag-FlowTests-{i:02d}" for i in range(1, 6)]
        jobs = [dict(id=i, name=part, conclusion=result, html_url=f"https://example.test/jobs/{i}")
                for i, (part, result) in enumerate(zip(parts, ("failure", "timed_out", "success", "cancelled")), 1)]
        jobs.append(dict(id=9, name="simulator (unit)", conclusion="failure"))
        result = DIAGNOSTICS.summary(parts, jobs)
        self.assertTrue(result.startswith("non-blocking diagnostics: 2 failed; 2 cancelled, skipped or incomplete\n"))
        self.assertIn("[`diag-FlowTests-01`](https://example.test/jobs/1): failure", result)
        self.assertIn("diag-FlowTests-04", result)
        self.assertIn("`diag-FlowTests-05`: not completed / missing", result)
        self.assertNotIn("diag-FlowTests-03", result)
        self.assertNotIn("simulator", result)

    def test_partial_reruns_keep_unrepeated_jobs_and_latest_attempt_wins(self):
        jobs = [dict(id=8, name="diag-A-01", conclusion="success"),
                dict(id=2, name="diag-A-01", conclusion="failure"),
                dict(id=3, name="diag-A-02", conclusion="success"),
                dict(id=9, name="diag-A-02", conclusion="failure"),
                dict(id=4, name="diag-A-03", conclusion="success")]
        result = DIAGNOSTICS.summary(["diag-A-01", "diag-A-02", "diag-A-03"], jobs)
        self.assertIn("non-blocking diagnostics: 1 failed", result)
        self.assertIn("`diag-A-02`: failure", result)
        self.assertNotIn("diag-A-01", result)
        self.assertNotIn("diag-A-03", result)

    def test_reads_all_job_pages_without_extra_dependencies(self):
        jobs = [dict(id=i, name=f"diag-A-{i}", conclusion="success") for i in range(101)]
        responses = [io.BytesIO(json.dumps(dict(total_count=101, jobs=page)).encode())
                     for page in (jobs[:100], jobs[100:])]
        env = dict(GITHUB_API_URL="https://api.example.test", GITHUB_REPOSITORY="owner/repo",
                   GITHUB_RUN_ID="42", GH_TOKEN="test-token")
        with patch.dict(os.environ, env), patch.object(DIAGNOSTICS, "urlopen", side_effect=responses) as request:
            self.assertEqual(DIAGNOSTICS.workflow_jobs(), jobs)
        self.assertEqual(request.call_count, 2)
        self.assertIn("filter=all&per_page=100&page=1", request.call_args_list[0].args[0].full_url)
        self.assertIn("&page=2", request.call_args_list[1].args[0].full_url)

    def test_empty_selection_and_gallery_mode_need_no_api(self):
        for mode, matrix in (("tests", '{"include":[]}'), ("gallery", "")):
            output = io.StringIO()
            with patch.dict(os.environ, MODE=mode, DIAGNOSTIC_MATRIX=matrix), redirect_stdout(output), \
                    patch.object(DIAGNOSTICS, "workflow_jobs") as request:
                DIAGNOSTICS.main()
                request.assert_not_called()
            self.assertIn("non-blocking diagnostics: 0 failed", output.getvalue())

    def test_diagnostic_and_reporting_failures_never_raise_a_gate_failure(self):
        env = dict(MODE="tests", DIAGNOSTIC_MATRIX='{"include":[{"part":"diag-A-01"}]}',
                   DIAGNOSTICS_RESULT="failure")
        for error in (None, OSError("unavailable")):
            output, warnings = io.StringIO(), io.StringIO()
            with patch.dict(os.environ, env), redirect_stdout(output), redirect_stderr(warnings), \
                    patch.object(DIAGNOSTICS, "workflow_jobs", side_effect=error,
                                 return_value=[dict(id=1, name="diag-A-01", conclusion="failure")]):
                self.assertIsNone(DIAGNOSTICS.main())
            if error:
                self.assertIn("count unavailable (jobs: failure)", output.getvalue())
                self.assertIn("::warning::", warnings.getvalue())
            else:
                self.assertIn("non-blocking diagnostics: 1 failed", output.getvalue())


if __name__ == "__main__":
    unittest.main(verbosity=2)
