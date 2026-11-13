#!/usr/bin/env python3
"""Derive every expected capture from the actual XCTest walks, for all variants."""
import argparse
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def inventory(root=ROOT):
    source = (root / 'Tests/YubaiUITests/ScreenGalleryTests.swift').read_text()
    headers = list(re.finditer(r'^    (?:@\w+ )?(?:private )?func (\w+)\(', source, re.M))
    bodies = {m[1]: source[m.end():headers[i + 1].start() if i + 1 < len(headers) else len(source)]
              for i, m in enumerate(headers)}

    # Each public test references one area function, which owns literal stops.
    # Do not recursively resolve same-named local helpers (e.g. saving()).
    owners = {name: re.findall(r'\bstop\("([^"\n]+)"', body) for name, body in bodies.items()}

    walks = {}
    for name, body in bodies.items():
        if not name.startswith('test'):
            continue
        variant = re.search(r'walk(46|47)\(\.(\w+)', body)
        prefix = 'V' + variant[1] + '-' + variant[2] + '-' if variant else ''
        legacy_prefix = re.search(r'prefix = "([^"]*)"', body)
        if legacy_prefix:
            prefix = legacy_prefix[1]
        called = set(re.findall(r'\b(\w+)\(', body))
        called.update(re.findall(r'walk46\(\.\w+,\s*(\w+)\)', body))
        areas47 = re.findall(r'walk47\(\.\w+,\s*(\w+)\)', body)
        called.update(areas47)
        if 'walk47(' in body and not areas47:
            called.add('round47BatchA')
        names = [prefix + value for owner in sorted(called & owners.keys()) for value in owners[owner]]
        if not names:
            raise ValueError('Gallery walk has no stops: ' + name)
        walks[name] = names
    expected = [value for values in walks.values() for value in values]
    if len(expected) != len(set(expected)):
        duplicates = sorted({v for v in expected if expected.count(v) > 1})
        raise ValueError('Duplicate gallery stops: ' + ', '.join(duplicates))
    return walks


def check(root=ROOT):
    walks = inventory(root)
    boards = (root / 'scripts/round46-boards.txt').read_text().splitlines()
    boards += (root / 'scripts/round47-boards.txt').read_text().splitlines()
    captures = {stop for names in walks.values() for stop in names}
    missing = [board for board in boards if any(board.split('-', 1)[0] + '-' + mode + '-' + board.split('-', 1)[1] not in captures
                                              for mode in ('light', 'dark', 'a11y', 'hidden'))]
    workflow = (root / '.github/workflows/ios.yml').read_text()
    scheduled = re.findall(r'^\s+walks:\s*(.+)$', workflow, re.M)
    scheduled = [name for line in scheduled for name in line.split()]
    if sorted(scheduled) != sorted(walks):
        raise ValueError('CI walks differ from XCTest inventory: missing=' + str(sorted(walks.keys() - set(scheduled))) +
                         ', extra/duplicate=' + str([n for n in scheduled if n not in walks or scheduled.count(n) > 1]))
    if missing:
        raise ValueError('Design boards without every variant: ' + ', '.join(missing))
    return walks, boards


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--json', action='store_true')
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    walks, boards = check()
    if args.json:
        print(json.dumps(walks, indent=2))
    else:
        print(f'Gallery: {len(boards)} boards, {len(walks)} walks, {sum(map(len, walks.values()))} captures; no missing boards or CI walks')
