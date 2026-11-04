#!/usr/bin/env python3
"""Conservative, dependency-free cross-file Swift access audit (not a type checker).

Emits every private/fileprivate declaration and every cross-file name match,
including code inside string interpolation and inactive conditional branches.
Same-name locals, argument labels and members of unrelated types need review.
private(set) is reported separately: it restricts writes, not reads.
"""

import argparse
import bisect
from collections import Counter, defaultdict
import csv
import json
from pathlib import Path
import re
import subprocess


IDENT = re.compile(r"[\w$]+", re.UNICODE)
DECL_KINDS = {"var", "let", "func", "struct", "class", "enum", "actor",
              "protocol", "typealias", "init", "subscript"}
TYPE_KINDS = {"struct", "class", "enum", "actor", "protocol", "extension"}


def lex(source):
    """Skip comments/literals, but recursively retain interpolated Swift code."""
    tokens = []
    newlines = [m.start() for m in re.finditer("\n", source)]

    def code(i, interpolation=False):
        depth = 1 if interpolation else 0
        while i < len(source):
            if source.startswith("//", i):
                end = source.find("\n", i)
                i = len(source) if end < 0 else end
                continue
            if source.startswith("/*", i):
                i += 2
                nesting = 1
                while i < len(source) and nesting:
                    if source.startswith("/*", i):
                        nesting += 1
                        i += 2
                    elif source.startswith("*/", i):
                        nesting -= 1
                        i += 2
                    else:
                        i += 1
                continue
            literal = re.match(r'(\#*)("""|")', source[i:])
            if literal:
                hashes, quote = literal.groups()
                i += len(literal.group())
                close, escape = quote + hashes, "\\" + hashes
                while i < len(source):
                    if source.startswith(close, i):
                        i += len(close)
                        break
                    if source.startswith(escape, i):
                        i += len(escape)
                        if source.startswith("(", i):
                            i = code(i + 1, interpolation=True)
                        else:
                            i += 1
                    else:
                        i += 1
                continue
            char = source[i]
            if interpolation:
                if char == "(":
                    depth += 1
                elif char == ")":
                    depth -= 1
                    if not depth:
                        return i + 1
            match = IDENT.match(source, i)
            if match:
                value, start = match.group(), i
                i = match.end()
            elif char == "`":
                end = source.index("`", i + 1)
                value, start, i = source[i + 1:end], i, end + 1
            elif not char.isspace():
                value, start = char, i
                i += 1
            else:
                i += 1
                continue
            tokens.append({"name": value, "offset": start,
                           "line": bisect.bisect_left(newlines, start) + 1})
        return i

    code(0)
    # Interpolation is emitted in source order, so offsets stay sorted.
    return tokens


def inventory(path, source):
    tokens = lex(source)
    scopes, pending, declarations = [], None, []
    for i, token in enumerate(tokens):
        name = token["name"]
        owner = next((scope["owner"] for scope in reversed(scopes) if scope), None)
        token.update(file=path, owner=owner)
        if name in TYPE_KINDS and i + 1 < len(tokens):
            # class also appears as a member modifier (class func/var).
            if tokens[i + 1]["name"] not in DECL_KINDS:
                inherited = (tokens[i - 1]["name"] if name == "extension" and i
                             and tokens[i - 1]["name"] in {"private", "fileprivate"} else None)
                pending = {"owner": tokens[i + 1]["name"], "extension_access": inherited}
        # A private extension restricts its members, not the extended type.
        if (name in DECL_KINDS and scopes and scopes[-1]
                and scopes[-1]["extension_access"]):
            start = i - 1
            while start >= 0 and tokens[start]["name"] not in {"{", "}", ";"}:
                if tokens[start]["name"] in {"private", "fileprivate", "internal", "public", "open"}:
                    break
                start -= 1
            else:
                start = -1
            if start < 0 or tokens[start]["name"] in {"{", "}", ";"}:
                symbol = name if name in {"init", "subscript"} else tokens[i + 1]["name"]
                declarations.append({"file": path, "line": token["line"],
                                     "access": scopes[-1]["extension_access"],
                                     "setter_only": False, "kind": name, "name": symbol,
                                     "owner": owner, "implicit_extension_access": True})
        if name == "{":
            scopes.append(pending)
            pending = None
        elif name == "}":
            if scopes:
                scopes.pop()
        if name not in {"private", "fileprivate"}:
            continue
        j, setter_only = i + 1, False
        if j < len(tokens) and tokens[j]["name"] == "(":
            setter_only = True
            while j < len(tokens) and tokens[j]["name"] != ")":
                j += 1
            j += 1
        while j < len(tokens) and tokens[j]["name"] not in DECL_KINDS | {"extension"}:
            if tokens[j]["name"] in {"{", "}", ";"}:
                raise ValueError(f"Unrecognized access declaration: {path}:{token['line']}")
            j += 1
        if j == len(tokens):
            raise ValueError(f"Unrecognized access declaration: {path}:{token['line']}")
        kind = tokens[j]["name"]
        symbol = kind if kind in {"init", "subscript"} else tokens[j + 1]["name"]
        declarations.append({"file": path, "line": token["line"], "access": name,
                             "setter_only": setter_only, "kind": kind,
                             "name": symbol, "owner": owner})
    return tokens, declarations


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--revision", help="Read tracked files from a Git revision")
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--summary", type=Path, help="Also write every candidate to a TSV review list")
    args = parser.parse_args()
    root = args.root.resolve()
    if args.revision:
        paths = sorted(p for p in subprocess.check_output(
            ["git", "ls-tree", "-r", "--name-only", args.revision, "--",
             "Sources/YubaiApp", "Tests/YubaiUITests"], cwd=root, text=True).splitlines()
                       if p.endswith(".swift"))
    else:
        paths = sorted(str(p.relative_to(root)) for base in ("Sources/YubaiApp", "Tests/YubaiUITests")
                       for p in (root / base).rglob("*.swift"))
    all_tokens, declarations = [], []
    for path in paths:
        source = (subprocess.check_output(["git", "show", f"{args.revision}:{path}"], cwd=root).decode()
                  if args.revision else (root / path).read_text())
        tokens, found = inventory(path, source)
        all_tokens.extend(tokens)
        if path.startswith("Sources/YubaiApp/"):
            declarations.extend(found)
    by_name = defaultdict(list)
    for token in all_tokens:
        by_name[token["name"]].append(token)
    candidates = []
    for decl in declarations:
        if decl["kind"] == "extension":
            continue
        # Constructors can be invoked as Type(...) or Type.init(...); retain
        # all .init occurrences too, because Swift may infer their receiver.
        names = [decl["name"]]
        if decl["kind"] in {"var", "let"}:
            # Include property-wrapper projections/backing storage (and
            # Observation's backing storage), even when only those are used.
            names.extend(("$" + decl["name"], "_" + decl["name"]))
        if decl["kind"] == "init" and decl["owner"]:
            names.append(decl["owner"])
        hits = [t for name in names for t in by_name[name] if t["file"] != decl["file"]]
        if hits:
            same_owner = [t for t in hits if decl["owner"] and t["owner"] == decl["owner"]]
            candidates.append({**decl, "same_owner_hits": same_owner, "hits": hits})
    payload = {"revision": args.revision or "working-tree", "files": paths,
               "declarations": declarations, "candidates": candidates}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n")
    if args.summary:
        args.summary.parent.mkdir(parents=True, exist_ok=True)
        with args.summary.open("w", newline="") as output:
            writer = csv.writer(output, delimiter="\t")
            writer.writerow(("declaration", "symbol", "kind", "access", "setter_only",
                             "cross_file_matches", "same_owner_matches", "all_locations"))
            for c in candidates:
                writer.writerow((f"{c['file']}:{c['line']}", f"{c['owner']}.{c['name']}",
                                 c["kind"], c["access"], c["setter_only"], len(c["hits"]),
                                 len(c["same_owner_hits"]),
                                 ", ".join(sorted({f"{h['file']}:{h['line']}" for h in c["hits"]}))))
    app_count = sum(p.startswith("Sources/YubaiApp/") for p in paths)
    print(f"{payload['revision']}: {app_count} App files + {len(paths) - app_count} UI files; "
          f"{len(declarations)} access declarations; "
          f"{sum(d['setter_only'] for d in declarations)} setter-only")
    print("Kinds:", dict(sorted(Counter(d["kind"] for d in declarations).items())))
    print(f"{len(candidates)} declarations have cross-file name matches; "
          f"{sum(len(c['hits']) for c in candidates)} total matches. "
          f"Full inventory: {args.output}")
    for candidate in candidates:
        if candidate["same_owner_hits"] and not candidate["setter_only"]:
            print(f"SAME OWNER: {candidate['file']}:{candidate['line']} "
                  f"{candidate['owner']}.{candidate['name']}")
            for hit in candidate["same_owner_hits"]:
                print(f"  {hit['file']}:{hit['line']}")


if __name__ == "__main__":
    main()
