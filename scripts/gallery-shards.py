#!/usr/bin/env python3
"""Generate the gallery matrix; --only selects a part-name prefix."""
import argparse
import json
from pathlib import Path

from gallery_inventory import inventory


PARTS = [
    ('r47-a-light', 'testWalk47BatchA'),
    ('r47-a-dark', 'testWalk47BatchADark'),
    ('r47-a-a11y', 'testWalk47BatchALarge'),
    ('r47-a-hidden', 'testWalk47BatchAHidden'),
    ('r47-b-light', 'testWalk47BatchB'),
    ('r47-b-dark', 'testWalk47BatchBDark'),
    ('r47-b-a11y', 'testWalk47BatchBLarge'),
    ('r47-b-hidden', 'testWalk47BatchBHidden'),
    ('r47-c-light', 'testWalk47BatchC'),
    ('r47-c-dark', 'testWalk47BatchCDark'),
    ('r47-c-a11y', 'testWalk47BatchCLarge'),
    ('r47-c-hidden', 'testWalk47BatchCHidden'),
    ('r47-d-light', 'testWalk47BatchD'),
    ('r47-d-dark', 'testWalk47BatchDDark'),
    ('r47-d-a11y', 'testWalk47BatchDLarge'),
    ('r47-d-hidden', 'testWalk47BatchDHidden'),
    ('46-batch1', 'testWalk46Batch1'),
    ('46-batch1-dark', 'testWalk46Batch1Dark'),
    ('46-batch1-large', 'testWalk46Batch1Large'),
    ('46-batch1-hidden', 'testWalk46Batch1Hidden'),
    ('46-batch2', 'testWalk46Batch2'),
    ('46-batch2-dark', 'testWalk46Batch2Dark'),
    ('46-batch2-large', 'testWalk46Batch2Large'),
    ('46-batch2-hidden', 'testWalk46Batch2Hidden'),
    ('46-batch3', 'testWalk46Batch3'),
    ('46-batch3-dark', 'testWalk46Batch3Dark'),
    ('46-batch3-large', 'testWalk46Batch3Large'),
    ('46-batch3-hidden', 'testWalk46Batch3Hidden'),
    ('46-batch4', 'testWalk46Batch4'),
    ('46-batch4-dark', 'testWalk46Batch4Dark'),
    ('46-batch4-large', 'testWalk46Batch4Large'),
    ('46-batch4-hidden', 'testWalk46Batch4Hidden'),
    ('46-batch5', 'testWalk46Batch5'),
    ('46-batch5-dark', 'testWalk46Batch5Dark'),
    ('46-batch5-large', 'testWalk46Batch5Large'),
    ('46-batch5-hidden', 'testWalk46Batch5Hidden'),
    ('01-roots-and-ledger', 'testWalk01RootsAndLedger'),
    ('02-formula-and-accounts', 'testWalk02FormulaAndAccounts'),
    ('03-bills', 'testWalk03Bills'),
    ('04-saving', 'testWalk04Saving'),
    ('05-entry-sheets', 'testWalk05EntrySheets'),
    ('06-categories', 'testWalk06Categories'),
    ('07-yubai', 'testWalk07Yubai'),
    ('08-settings', 'testWalk08Settings'),
    ('09-imports', 'testWalk09Imports'),
    ('10-states', 'testWalk10States'),
    ('11-empty', 'testWalk11Empty'),
    ('accessibility-walk', 'testAccessibilityWalk'),
    ('dark-walk', 'testDarkWalk'),
]


def matrix(root: Path, only: str = "") -> dict:
    scheduled = [walk for _, walk in PARTS]
    walks = inventory(root)
    if len(set(scheduled)) != len(scheduled) or set(scheduled) != set(walks):
        raise ValueError("Gallery matrix must include every XCTest walk exactly once")
    rows = [{"part": part, "walks": walk} for part, walk in PARTS if part.startswith(only)]
    if not rows:
        raise ValueError("No gallery parts start with: " + only)
    return {"include": rows}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--only", default="", help="Only gallery parts starting with this prefix")
    parser.add_argument("--github-output", action="store_true")
    args = parser.parse_args()
    result = json.dumps(matrix(Path(__file__).resolve().parent.parent, args.only), separators=(",", ":"))
    print(("matrix=" if args.github_output else "") + result)
