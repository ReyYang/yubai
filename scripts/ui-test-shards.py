#!/usr/bin/env python3
"""Generate blocking UI and non-blocking diagnostic shards from exact selectors."""
import argparse
import ast
import importlib.util
import json
from pathlib import Path
import re


# These source files stay in the UI target, but execute only in the Linux runner.
LINUX_ONLY_CLASSES = (
    "Round47FrameWaitTests",
    "Round47GalleryProcessTests",
    "Round47KeyboardOwnershipTests",
    "Round47RevealProgressTests",
    "Round47ViewportGeometryTests",
)
DIAGNOSTIC_MANIFEST = "Tests/YubaiUITests/diagnostic-tests.txt"


def validate_linux_coverage(root: Path) -> None:
    runner = root / "scripts/test-ui-helpers.py"
    try:
        tree = ast.parse(runner.read_text())
        names = next(ast.literal_eval(node.value) for node in tree.body
                     if isinstance(node, ast.Assign)
                     and any(isinstance(target, ast.Name) and target.id == "names" for target in node.targets))
    except (OSError, SyntaxError, StopIteration, ValueError, TypeError) as error:
        raise ValueError(f"Cannot read Linux helper class list in {runner}: {error}") from error
    missing = set(LINUX_ONLY_CLASSES) - set(names)
    if missing:
        raise ValueError("Mac-excluded classes missing from scripts/test-ui-helpers.py: " + ", ".join(sorted(missing)))


def diagnostic_tests(root: Path, classes: dict[str, list[str]]) -> set[str]:
    path = root / DIAGNOSTIC_MANIFEST
    try:
        lines = path.read_text().splitlines()
    except OSError as error:
        raise ValueError(f"Cannot read diagnostic manifest {path}: {error}") from error
    selected: set[str] = set()
    for number, line in enumerate(lines, 1):
        test = line.split("#", 1)[0].strip()
        if not test:
            continue
        name, _, method = test.partition("/")
        if method not in classes.get(name, []):
            raise ValueError(f"{path}:{number}: Unknown diagnostic test: {test}")
        if test in selected:
            raise ValueError(f"{path}:{number}: Duplicate diagnostic test: {test}")
        if name in LINUX_ONLY_CLASSES:
            raise ValueError(f"{path}:{number}: Diagnostic test belongs to a Linux-only class: {test}")
        selected.add(test)
    return selected


def matrix(root: Path, size: int = 8, only: str = "", parts: str = "", include_diagnostics: bool = True) -> dict:
    validate_linux_coverage(root)
    classes: dict[str, list[str]] = {}
    for path in sorted((root / "Tests/YubaiUITests").glob("*.swift")):
        source = path.read_text()
        declarations = list(re.finditer(r"(?m)^(?:final )?class (\w+): (?:XCTestCase|YubaiUITestCase)\s*\{", source))
        assigned = 0
        for index, match in enumerate(declarations):
            name = match[1]
            end = declarations[index + 1].start() if index + 1 < len(declarations) else len(source)
            methods = re.findall(r"(?m)^    func (test\w+)\s*\(", source[match.end():end])
            assigned += len(methods)
            if name == "YubaiUITestCase" and not methods:
                continue  # shared launch/interaction helper, no test selectors
            if name == "ScreenGalleryTests":
                continue
            if name in classes or len(methods) != len(set(methods)) or not methods:
                raise ValueError(f"Invalid or duplicate XCTest class: {path}: {name}")
            classes[name] = sorted(methods)
        if assigned != len(re.findall(r"(?m)^\s*func test\w+\s*\(", source)):
            raise ValueError(f"Unassigned test methods in {path}; add their XCTestCase class to the inventory")
    if not classes:
        raise ValueError("No UI test classes found")
    diagnostics = diagnostic_tests(root, classes)
    shards = [{"part": "unit", "tests": ["YubaiCoreTests"], "blocking": True}]
    for name, methods in sorted(classes.items()):
        if name in LINUX_ONLY_CLASSES:
            continue
        for prefix, blocking in (("ui", True), ("diag", False)):
            tier = [method for method in methods if (f"{name}/{method}" not in diagnostics) == blocking]
            for start in range(0, len(tier), size):
                shards.append({"part": f"{prefix}-{name}-{start // size + 1:02d}",
                               "tests": [f"YubaiUITests/{name}/{method}" for method in tier[start:start + size]],
                               "blocking": blocking})
    if only:
        shards = [row for row in shards if row["part"] == "unit" or "Round47" in row["part"]]
    requested = set(filter(None, re.split(r"[\s,]+", parts)))
    if requested:
        shards = [row for row in shards if row["part"] in requested
                  or row["part"].rsplit("-", 1)[0] in requested]
    elif not include_diagnostics:
        shards = [row for row in shards if row["blocking"]]
    return {"include": shards}


def validate_parts(root: Path, parts: str) -> None:
    """Validate the shared namespace once in CI, before --only or mode filtering."""
    requested = set(filter(None, re.split(r"[\s,]+", parts)))
    if not requested:
        return
    rows = matrix(root)["include"]
    known = {row["part"] for row in rows}
    known.update(row["part"].rsplit("-", 1)[0] for row in rows if row["part"].startswith(("ui-", "diag-")))
    spec = importlib.util.spec_from_file_location("gallery_shards", Path(__file__).with_name("gallery-shards.py"))
    gallery = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(gallery)
    known.update(row["part"] for row in gallery.matrix(root)["include"])
    unknown = requested - known
    if unknown:
        raise ValueError("Unknown shard part(s): " + ", ".join(sorted(unknown))
                         + ". Use exact UI/diagnostic/gallery parts or ui-<XCTestClass>/diag-<XCTestClass>.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--github-output", action="store_true")
    parser.add_argument("--only", default="", help="When set, keep unit and Round47 UI shards")
    parser.add_argument("--parts", default="", help="Exact parts or ui-<XCTestClass>/diag-<XCTestClass>, separated by spaces/commas")
    parser.add_argument("--validate-parts", action="store_true", help="Reject parts unknown to both shard scripts")
    parser.add_argument("--diagnostics", choices=("true", "false"), default="true",
                        help="Include unrequested diagnostics (CI passes false by default; local inventory is unchanged)")
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    try:
        if args.validate_parts:
            validate_parts(root, args.parts)
        selected = matrix(root, only=args.only, parts=args.parts, include_diagnostics=args.diagnostics == "true")
    except ValueError as error:
        parser.error(str(error))
    result = json.dumps(selected, separators=(",", ":"))
    print(("matrix=" if args.github_output else "") + result)
    if args.github_output:
        print("has-shards=" + str(bool(selected["include"])).lower())
        for tier, blocking in (("gate", True), ("diagnostic", False)):
            rows = [row for row in selected["include"] if row["blocking"] == blocking]
            print(tier + "-matrix=" + json.dumps({"include": rows}, separators=(",", ":")))
            print("has-" + tier + "-shards=" + str(bool(rows)).lower())
