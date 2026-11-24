#!/usr/bin/env python3
"""Accept only completed snapshot-recording failures, never crashes or image diffs."""
import argparse
import json
from pathlib import Path
import re


def recording_only(summary, png_count):
    failures = summary.get('testFailures', [])
    total = summary.get('totalTestCount', 0)
    completed = summary.get('passedTests', 0) + summary.get('failedTests', 0)
    if (summary.get('result') != 'Failed' or not failures or total <= 0 or completed != total
            or summary.get('skippedTests', 0) or png_count != 14):
        return False
    for failure in failures:
        text = failure.get('failureText') or failure.get('message') or ''
        test = failure.get('testIdentifierString') or failure.get('testName') or ''
        if 'DesignSystemSnapshotTests' not in test:
            return False
        if not re.search(r'(Record mode is on|No reference was found on disk).*Automatically recorded snapshot|recorded new snapshot', text, re.S | re.I):
            return False
        if re.search(r'PNG export failed|crash|XCTAssert|does not match reference|timed out', text, re.I):
            return False
    return True


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('summary', type=Path)
    parser.add_argument('--png-dir', type=Path, required=True)
    args = parser.parse_args()
    summary = json.loads(args.summary.read_text())
    if not recording_only(summary, len(list(args.png_dir.glob('*.png')))):
        raise SystemExit('Snapshot failures were not exclusively successful recordings; see xcresult.')
    print('Snapshot recording: 14 PNGs; only expected recording assertions failed.')


if __name__ == '__main__':
    main()
