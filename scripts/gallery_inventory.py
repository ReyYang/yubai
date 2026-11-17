#!/usr/bin/env python3
"""Derive captures from XCTest routes, including the round-47 hidden key selection."""
import argparse
import json
import importlib.util
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

    # Hidden walks select existing routes before stop() executes their closures.
    # Resolve only these explicit wrappers, not same-named local route helpers.
    for name, body in bodies.items():
        selection = re.search(r'\bonlyStops\(\[([^\]]*)\]\)', body)
        if not selection:
            continue
        selected = re.findall(r'"([^"\n]+)"', selection[1])
        called = dict.fromkeys(re.findall(r'\b(\w+)\(', body))
        routes = [stop for owner in called if owner in owners for stop in owners[owner]]
        if len(selected) != len(set(selected)):
            raise ValueError('Duplicate selected gallery stops in ' + name)
        unknown = set(selected) - set(routes)
        if unknown:
            raise ValueError('Selected gallery stops without routes in ' + name + ': ' + ', '.join(sorted(unknown)))
        owners[name] = [stop for stop in routes if stop in selected]

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
        called.update(re.findall(r'walk(?:46|47)\(\.\w+,\s*(\w+)\)', body))
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
    captures = {stop for names in walks.values() for stop in names}
    full_modes = ('light', 'dark', 'a11y')
    round47 = {mode: {stop.removeprefix('V47-' + mode + '-') for stop in captures
                      if stop.startswith('V47-' + mode + '-')} for mode in full_modes}
    if len(round47['light']) != 138 or any(round47[mode] != round47['light'] for mode in full_modes):
        raise ValueError('Round-47 light, dark and a11y must retain the same complete 138 stops')
    for mode in full_modes:
        revision_b = {name: stops for name, stops in walks.items() if name.startswith('testWalk47BatchB')
                      and all(stop.startswith('V47-' + mode + '-') for stop in stops)}
        if len(revision_b) != 4 or sum(map(len, revision_b.values())) != 77:
            raise ValueError('Round-47 B must retain all 77 stops in ' + mode + ' across four short walks')
        if any(len(stops) > 20 for stops in revision_b.values()):
            raise ValueError('Round-47 B exceeds the 20-stop walk budget; split it without dropping stops')

    keys = (root / 'scripts/round47-hidden-key-boards.txt').read_text().splitlines()
    if len(keys) != 28 or len(set(keys)) != 28 or not set(keys) <= round47['light']:
        raise ValueError('Round-47 hidden key manifest must contain exactly 28 unique board names without the mode')
    expected_hidden = {'V47-hidden-' + key for key in keys}
    hidden = [stop for names in walks.values() for stop in names if stop.startswith('V47-hidden-')]
    if set(hidden) != expected_hidden or len(hidden) != len(keys):
        raise ValueError('Round-47 hidden must contain exactly the key boards: missing=' + str(sorted(expected_hidden - set(hidden))) +
                         ', extra=' + str(sorted(set(hidden) - expected_hidden)))
    hidden_walks = [stops for stops in walks.values() if any(stop.startswith('V47-hidden-') for stop in stops)]
    if len(hidden_walks) != 2 or any(len(stops) > 20 for stops in hidden_walks):
        raise ValueError('Round-47 hidden must use two walks of at most 20 stops each')

    boards = (root / 'scripts/round46-boards.txt').read_text().splitlines()
    boards += (root / 'scripts/round47-boards.txt').read_text().splitlines()
    missing = [board for board in boards if any(board.split('-', 1)[0] + '-' + mode + '-' + board.split('-', 1)[1] not in captures
                                              for mode in (full_modes if board.startswith('V47-') else (*full_modes, 'hidden')))]
    spec = importlib.util.spec_from_file_location('gallery_shards', root / 'scripts/gallery-shards.py')
    shards = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(shards)
    scheduled = [row['walks'] for row in shards.matrix(root)['include']]
    workflow = (root / '.github/workflows/ios.yml').read_text()
    if 'python3 scripts/gallery-shards.py' not in workflow or 'fromJSON(needs.gallery-shards.outputs.matrix)' not in workflow:
        raise ValueError('CI gallery must use scripts/gallery-shards.py')
    if sorted(scheduled) != sorted(walks):
        raise ValueError('CI walks differ from XCTest inventory: missing=' + str(sorted(walks.keys() - set(scheduled))) +
                         ', extra/duplicate=' + str([n for n in scheduled if n not in walks or scheduled.count(n) > 1]))
    if missing:
        raise ValueError('Design boards without every required variant: ' + ', '.join(missing))
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
