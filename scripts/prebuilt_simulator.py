#!/usr/bin/env python3
"""Validate relocatable simulator products; print the sole usable xctestrun path."""
import argparse
import json
from pathlib import Path
import plistlib
import subprocess


def identity() -> dict[str, str]:
    root = Path(__file__).resolve().parent.parent
    return {
        "revision": subprocess.check_output(["git", "-C", str(root), "rev-parse", "HEAD"], text=True).strip(),
        "xcode": subprocess.check_output(["xcodebuild", "-version"], text=True).strip(),
        "developer_dir": subprocess.check_output(["xcode-select", "-p"], text=True).strip(),
    }


def test_targets(node):
    if isinstance(node, dict):
        if "TestBundlePath" in node:
            yield node
        else:
            for child in node.values():
                yield from test_targets(child)
    elif isinstance(node, list):
        for child in node:
            yield from test_targets(child)


def strings(node):
    if isinstance(node, str):
        yield node
    elif isinstance(node, dict):
        for child in node.values():
            yield from strings(child)
    elif isinstance(node, list):
        for child in node:
            yield from strings(child)


def validate_prebuilt(directory: str, record: bool = False) -> Path:
    if not directory:
        raise ValueError("YUBAI_PREBUILT_DERIVED_DATA is empty")
    derived = Path(directory).resolve()
    products = derived / "Build/Products"
    runs = sorted(products.glob("*.xctestrun"))
    if len(runs) != 1:
        raise ValueError(f"Expected exactly one .xctestrun in {products}, found {len(runs)}")
    current = identity()
    manifest = products / "yubai-prebuilt.json"
    metadata = ({**current, "derived_data": str(derived), "xctestrun": runs[0].name}
                if record else json.loads(manifest.read_text()))
    if not isinstance(metadata, dict) or any(metadata.get(key) != value for key, value in current.items()):
        raise ValueError("Prebuilt Git revision or selected Xcode differs from this shard")
    if (metadata.get("xctestrun") != runs[0].name
            or not isinstance(metadata.get("derived_data"), str) or not metadata["derived_data"]):
        raise ValueError("Prebuilt manifest does not identify these products")
    with runs[0].open("rb") as file:
        data = plistlib.load(file)
    # Fail instead of rewriting build-machine paths or falling back to compilation.
    for value in strings(data):
        if str(derived) in value or metadata["derived_data"] in value:
            raise ValueError(f"Non-relocatable .xctestrun path: {value}")
    targets = list(test_targets(data))  # Both classic and test-plan plist formats.
    bundles = set()
    for target in targets:
        def resolve(value: str, host: str = "") -> Path:
            if not isinstance(value, str) or not value.startswith(("__TESTROOT__/", "__TESTHOST__/", "__PLATFORMS__/")):
                raise ValueError(f"Non-relocatable .xctestrun product path: {value}")
            path = (value.replace("__TESTROOT__", str(products))
                    .replace("__PLATFORMS__", current["developer_dir"] + "/Platforms"))
            if "__TESTHOST__" in path:
                if not host:
                    raise ValueError(f"Missing TestHostPath for {value}")
                path = path.replace("__TESTHOST__", host)
            resolved = Path(path).resolve()
            if not resolved.exists():
                raise ValueError(f"Missing prebuilt test dependency: {resolved}")
            if not value.startswith("__PLATFORMS__/") and not resolved.is_relative_to(products):
                raise ValueError(f"Test product escapes Build/Products: {value}")
            return resolved

        host = str(resolve(target["TestHostPath"])) if target.get("TestHostPath") else ""
        bundle = resolve(target["TestBundlePath"], host)
        if not bundle.is_relative_to(products):
            raise ValueError(f"Test bundle is outside Build/Products: {bundle}")
        bundles.add(bundle.stem)
        if target.get("UITargetAppPath"):
            resolve(target["UITargetAppPath"], host)
        for dependency in target.get("DependentProductPaths", []):
            resolve(dependency, host)
    if bundles != {"YubaiCoreTests", "YubaiUITests"}:
        raise ValueError(f"Expected Core and UI test bundles, found {sorted(bundles)}")
    if not (products / "Debug-iphonesimulator/Yubai.app").is_dir():
        raise ValueError("Missing Debug simulator app")
    if not any(path.is_file() for path in products.glob("Debug-iphonesimulator/Yubai*.dSYM/Contents/Resources/DWARF/*")):
        raise ValueError("Missing Yubai dSYM for stall symbolication")
    if record:
        manifest.write_text(json.dumps(metadata, indent=2) + "\n")
    return runs[0]


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("derived_data")
    parser.add_argument("--record", action="store_true", help="Record build identity before archiving")
    args = parser.parse_args()
    try:
        print(validate_prebuilt(args.derived_data, record=args.record))
    except (OSError, ValueError, plistlib.InvalidFileException, subprocess.CalledProcessError) as error:
        parser.exit(2, f"Prebuilt simulator artifact unusable; refusing to rebuild: {error}\n")
