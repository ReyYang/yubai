#!/usr/bin/env bash
# macOS / Apple Silicon. Usage: scripts/gallery.sh [simulator-UDID]
# TEST_RUNNER_ is stripped by xcodebuild for the XCTest runner (not the app).
# https://developer.apple.com/documentation/xcode-release-notes/xcode-13-release-notes
set -euo pipefail
repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
simulator="${1:-${SIM:-37FDA39F-AF08-48EA-9E35-0AAB017AAFE0}}"
if (( $# > 1 )); then printf 'Usage: %s [simulator-UDID]\n' "$0" >&2; exit 2; fi
for tool in xcodebuild xcrun python3 git; do
    command -v "$tool" >/dev/null || { printf 'Missing command: %s\n' "$tool" >&2; exit 1; }
done
shots="$repo_root/.shots"
rm -rf -- "$shots"
mkdir -p -- "$shots"
run_dir="$(mktemp -d /tmp/yubai-gallery.XXXXXX)"
result="$run_dir/gallery.xcresult"
printf 'Simulator: %s\nResults and log: %s\n' "$simulator" "$run_dir"
# GALLERY_ONLY="testWalk46Batch1 testWalk46Batch1Dark testWalk46Batch1Large" captures this batch.
# Batch 4: GALLERY_ONLY="testWalk46Batch4 testWalk46Batch4Dark testWalk46Batch4Large"
# Any space-separated walk names can be selected for a partial inventory.
only=()
for name in ${GALLERY_ONLY:-}; do only+=("-only-testing:YubaiUITests/ScreenGalleryTests/$name"); done
(( ${#only[@]} )) || only=("-only-testing:YubaiUITests/ScreenGalleryTests")
set +e
env TEST_RUNNER_YUBAI_GALLERY_DIR="$shots" xcodebuild test \
    -project "$repo_root/Yubai.xcodeproj" -scheme Yubai -configuration Debug \
    -destination "platform=iOS Simulator,id=$simulator" \
    "${only[@]}" \
    -parallel-testing-enabled NO -maximum-concurrent-test-simulator-destinations 1 \
    -derivedDataPath "$run_dir/DerivedData" -resultBundlePath "$result" \
    ARCHS=arm64 ONLY_ACTIVE_ARCH=YES CODE_SIGNING_ALLOWED=NO 2>&1 | tee "$run_dir/xcodebuild.log"
build_status=${PIPESTATUS[0]}
set -e

if ! find "$shots" -type f -name '*.png' -print -quit | grep -q . && [[ -d "$result" ]]; then
    # A runner on some Xcode versions cannot write outside its sandbox. Attachments
    # still survive and include the exact shot names and the missing-stop reports.
    xcrun xcresulttool export attachments --path "$result" --output-path "$shots" \
        > "$run_dir/export.log" 2>&1 || cat "$run_dir/export.log" >&2
fi

python3 - "$shots" "$repo_root" "$build_status" "$result" <<'PY'
import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

shots, repo = map(Path, sys.argv[1:3])
status, result = sys.argv[3:5]
unmapped = []

def attachments(node):
    if isinstance(node, dict):
        if isinstance(node.get("exportedFileName"), str):
            yield node
        for child in node.values():
            yield from attachments(child)
    elif isinstance(node, list):
        for child in node:
            yield from attachments(child)

# xcresulttool's manifest uses exportedFileName + suggestedHumanReadableName.
# Walk recursively so both the list and grouped manifest forms are supported.
for manifest in sorted(shots.rglob("manifest.json")):
    try:
        exported = json.loads(manifest.read_text())
    except (OSError, ValueError) as error:
        unmapped.append(f"{manifest.relative_to(shots)}: {error}")
        continue
    for item in attachments(exported):
        source = manifest.parent / item["exportedFileName"]
        if not source.is_file():
            matches = list(shots.rglob(Path(item["exportedFileName"]).name))
            if not matches:
                continue
            source = matches[0]
        name = item.get("suggestedHumanReadableName") or item.get("name") or ""
        name = Path(name).name
        # Xcode may append the file extension to the suggested name.
        if source.suffix.lower() == ".png" and re.match(r"^(?:\d{2}-|DS-Nav|Quick|Home-|Deck|Payday-Amount|First|Recon|Over-|Big-Home|Spend|Saved|Goal|Butler-Kinds|Words|Bills-|Bill-|Accounts)", name):
            name = re.sub(r"\.png$", "", name, flags=re.I)
            destination = shots / (re.sub(r"[^A-Za-z0-9._-]", "_", name) + ".png")
        elif name.startswith(("missing-", "planned-", "write-errors-")):
            destination = shots / name
        else:
            if source.suffix.lower() == ".png":
                unmapped.append(str(source.relative_to(shots)))
            continue
        if source.resolve() != destination.resolve():
            if destination.exists():
                # Keep the runner's direct write in preference to an exported duplicate.
                if source.suffix.lower() == ".png":
                    source.unlink()
            else:
                shutil.move(str(source), str(destination))

source = (repo / "Tests/YubaiUITests/ScreenGalleryTests.swift").read_text()
full, reduced = source.split("    private func reduced(", 1)
names = re.findall(r'\bstop\("([^"\n]+)"', full)
small = re.findall(r'\bstop\("([^"\n]+)"', reduced)
round46 = full.split("    private func round46Batch1(", 1)[1].split("    private func audit46(", 1)[0]
board_names = re.findall(r'\bstop\("([^"\n]+)"', round46)
round46_bills = full.split("    private func round46Batch4(", 1)[1]
board_names += re.findall(r'\bstop\("([^"\n]+)"', round46_bills)
expected = sorted(names + [prefix + name for prefix in ("46-dark-", "46-a11y-") for name in board_names]
                  + [prefix + name for prefix in ("80-a11y-", "90-dark-") for name in small])
if len(expected) != len(set(expected)):
    raise SystemExit("Gallery stop IDs must be unique")
if os.environ.get("GALLERY_ONLY"):
    # A partial run is only accountable for the stops its own walks planned.
    expected = sorted({line for report in shots.glob("planned-*.txt") for line in report.read_text().splitlines() if line.strip()})
(shots / "expected.txt").write_text("\n".join(expected) + "\n")

missing = set()
for report in shots.glob("missing-*.txt"):
    missing.update(line for line in report.read_text().splitlines() if line.strip())
if (shots / "missing.txt").exists():
    missing.update(line for line in (shots / "missing.txt").read_text().splitlines() if line.strip())
for name in expected:
    if not (shots / (name + ".png")).exists() and not any(line.startswith(name + "-MISSING:") for line in missing):
        missing.add(name + "-MISSING: no PNG produced; inspect the xcresult / build log")
(shots / "missing.txt").write_text("\n".join(sorted(missing)) + ("\n" if missing else ""))
pngs = sorted(str(path.relative_to(shots)) for path in shots.rglob("*.png"))
sha = subprocess.check_output(["git", "-C", str(repo), "rev-parse", "--short", "HEAD"], text=True).strip()
index = [f"PNG count: {len(pngs)}", f"Planned states: {len(expected)}", f"Git: {sha}",
         f"xcodebuild exit: {status}", f"Result bundle: {result}", "", "Files:", *pngs,
         "", f"Missing stops: {len(missing)}", *sorted(missing)]
if unmapped:
    index += ["", "Attachments without a gallery name:", *unmapped]
(shots / "index.txt").write_text("\n".join(index) + "\n")
print(f"Gallery: {len(pngs)} PNGs in {shots} ({len(missing)} missing stops)")
sys.exit(0 if pngs and not missing and status == "0" else 1)
PY
