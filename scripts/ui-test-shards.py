#!/usr/bin/env python3
"""Generate exact XCTest selectors from source; keep the gallery in its own job."""
import argparse
import importlib.util
import json
from pathlib import Path
import re


def matrix(root: Path, size: int = 8, only: str = "", parts: str = "") -> dict:
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
    shards = [{"part": "unit", "tests": ["YubaiCoreTests"]}]
    for name, methods in sorted(classes.items()):
        for start in range(0, len(methods), size):
            shards.append({"part": f"ui-{name}-{start // size + 1:02d}",
                           "tests": [f"YubaiUITests/{name}/{method}" for method in methods[start:start + size]]})
    if only:
        shards = [row for row in shards if row["part"] == "unit" or "Round47" in row["part"]]
    requested = set(filter(None, re.split(r"[\s,]+", parts)))
    if requested:
        shards = [row for row in shards if row["part"] in requested
                  or row["part"].rsplit("-", 1)[0] in requested]
    return {"include": shards}


def validate_parts(root: Path, parts: str) -> None:
    """Validate the shared namespace once in CI, before --only or mode filtering."""
    requested = set(filter(None, re.split(r"[\s,]+", parts)))
    if not requested:
        return
    rows = matrix(root)["include"]
    known = {row["part"] for row in rows}
    known.update(row["part"].rsplit("-", 1)[0] for row in rows if row["part"].startswith("ui-"))
    spec = importlib.util.spec_from_file_location("gallery_shards", Path(__file__).with_name("gallery-shards.py"))
    gallery = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(gallery)
    known.update(row["part"] for row in gallery.matrix(root)["include"])
    unknown = requested - known
    if unknown:
        raise ValueError("Unknown shard part(s): " + ", ".join(sorted(unknown))
                         + ". Use exact UI/gallery part names or ui-<XCTestClass> for all class shards.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--github-output", action="store_true")
    parser.add_argument("--only", default="", help="When set, keep unit and Round47 UI shards")
    parser.add_argument("--parts", default="", help="Space/comma-separated exact parts or ui-<XCTestClass> names")
    parser.add_argument("--validate-parts", action="store_true", help="Reject parts unknown to both shard scripts")
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    try:
        if args.validate_parts:
            validate_parts(root, args.parts)
        selected = matrix(root, only=args.only, parts=args.parts)
    except ValueError as error:
        parser.error(str(error))
    result = json.dumps(selected, separators=(",", ":"))
    print(("matrix=" if args.github_output else "") + result)
    if args.github_output:
        print("has-shards=" + str(bool(selected["include"])).lower())
