#!/usr/bin/env python3
"""Generate exact XCTest selectors from source; keep the gallery in its own job."""
import argparse
import json
from pathlib import Path
import re


def matrix(root: Path, size: int = 8, only: str = "") -> dict:
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
    return {"include": shards}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--github-output", action="store_true")
    parser.add_argument("--only", default="", help="When set, keep unit and Round47 UI shards")
    args = parser.parse_args()
    result = json.dumps(matrix(Path(__file__).resolve().parent.parent, only=args.only), separators=(",", ":"))
    print(("matrix=" if args.github_output else "") + result)
