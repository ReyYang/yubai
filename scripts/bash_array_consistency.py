"""Reject empty-array expansions that fail under macOS bash 3.2 with nounset."""
import re
import tempfile
from pathlib import Path

SHELL_FILES = ('scripts/gallery.sh', 'scripts/prepare-simulator-keyboard.sh')
WORKFLOW = '.github/workflows/ios.yml'
QUOTED_ARRAY = re.compile(r'"\$\{([A-Za-z_][A-Za-z0-9_]*)\[@\]\}"')
SAFE_ARRAY = re.compile(r'\$\{(?P<name>[A-Za-z_][A-Za-z0-9_]*)\[@\]\+"\$\{(?P=name)\[@\]\}"\}')
SCRIPT_REFERENCE = re.compile(r'\bscripts/[A-Za-z0-9_./-]+\.sh\b')
SOURCE = re.compile(r'''(?:^|[;&|]|\brun:)[ \t]*(?:source|\.)[ \t]+("[^"\n]+"|'[^'\n]+'|[^\s;&|=]+)''', re.M)


def split_comment(line):
    quote, escaped = None, False
    for index, char in enumerate(line):
        if escaped:
            escaped = False
        elif char == '\\' and quote != "'":
            escaped = True
        elif char == quote:
            quote = None
        elif quote is None:
            if char in ('"', "'"):
                quote = char
            elif char == '#' and (index == 0 or line[index - 1].isspace() or line[index - 1] in ';|&()'):
                return line[:index], line[index:]
    return line, ''


def violations(name, source):
    found = []
    for number, line in enumerate(source.splitlines(), 1):
        code, comment = split_comment(line)
        if re.match(r'#\s*nonempty-array\b', comment):
            continue
        # The nested expansion is allowed only when guarded by the same array.
        for match in QUOTED_ARRAY.finditer(SAFE_ARRAY.sub('', code)):
            array = match[1]
            safe = '${' + array + '[@]+"${' + array + '[@]}"}'
            found.append(f'{name}:{number}: bash 3.2 nounset: use {safe} '
                         'or document a proven non-empty array with # nonempty-array')
    return found


def check(root):
    root = root.resolve()
    pending = [root / name for name in (*SHELL_FILES, WORKFLOW)]
    visited, errors = set(), []
    while pending:
        path = pending.pop().resolve()
        if path in visited:
            continue
        visited.add(path)
        name = str(path.relative_to(root))
        try:
            source = path.read_text()
        except OSError as error:
            errors.append(f'{name}: cannot read checked shell: {error}')
            continue
        errors.extend(violations(name, source))
        source = '\n'.join(split_comment(line)[0] for line in source.splitlines())
        # Scan every workflow definition, including anchors shared by Mac jobs.
        # This conservative superset also covers Linux run blocks without PyYAML.
        pending.extend(root / match[0] for match in SCRIPT_REFERENCE.finditer(source))
        for match in SOURCE.finditer(source):
            target = match[1].strip('"\'')
            target = target.replace('${repo_root}/', str(root) + '/')
            target = target.replace('$repo_root/', str(root) + '/')
            bases = (root, path.parent) if name == WORKFLOW else (path.parent, root)
            resolved = next((base / target for base in bases if (base / target).is_file()), None)
            if resolved is None or not resolved.resolve().is_relative_to(root):
                line = source.count('\n', 0, match.start()) + 1
                errors.append(f'{name}:{line}: cannot resolve repository shell source {target!r}')
            else:
                pending.append(resolved)
    return errors


def self_test():
    for array in ('build_options', 'action', 'only'):
        raw = '"${' + array + '[@]}"'
        safe = '${' + array + '[@]+"${' + array + '[@]}"}'
        assert violations('fixture.sh', f'args=()\ncommand {raw}'), array
        assert not violations('fixture.sh', f'args=()\ncommand {safe}'), array
        assert not violations('fixture.sh', f'command {raw} # nonempty-array: set above'), array
        assert violations('fixture.sh', f'# nonempty-array\ncommand {raw}'), array
        assert violations('fixture.sh', f'command {safe} {raw}'), array
    assert violations('fixture.sh', 'command ${other[@]+"${args[@]}"}')
    assert violations('fixture.sh', 'command "# nonempty-array" "${args[@]}"')
    assert not violations('fixture.sh', '# Example: "${args[@]}"')
    assert not violations('fixture.sh', 'command ok # Example: "${args[@]}"')

    with tempfile.TemporaryDirectory(prefix='yubai-bash-arrays-') as directory:
        root = Path(directory)
        (root / 'scripts').mkdir()
        (root / '.github/workflows').mkdir(parents=True)
        (root / SHELL_FILES[0]).write_text('source "$repo_root/scripts/helpers.inc"\n')
        (root / SHELL_FILES[1]).write_text('set -euo pipefail\n')
        helper = root / 'scripts/helpers.inc'
        helper.write_text('. ./gallery.sh\ncommand "${sourced[@]}"\n')
        workflow = root / WORKFLOW
        workflow.write_text('steps:\n  - &shared\n    run: |\n      command "${inline[@]}"\n  - *shared\n')
        errors = check(root)
        assert len(errors) == 2, errors
        assert any('helpers.inc:2:' in error for error in errors), errors
        assert any('ios.yml:4:' in error for error in errors), errors
        helper.write_text('. ./gallery.sh\ncommand ${sourced[@]+"${sourced[@]}"}\n')
        workflow.write_text('run: command "${inline[@]}" # nonempty-array: initialized above\n')
        assert not check(root), check(root)
        extra = root / 'scripts/extra.sh'
        extra.write_text('command "${extra[@]}"\n')
        workflow.write_text('run: bash scripts/extra.sh\n')
        assert any('extra.sh:1:' in error for error in check(root))
        helper.write_text('source missing.inc\n')
        assert any('cannot resolve' in error for error in check(root))
        helper.write_text('')
        workflow.write_text('run: . ./scripts/helpers.inc\n')
        helper.write_text('command "${sourced[@]}"\n')
        assert any('helpers.inc:1:' in error for error in check(root))
    print('Bash array lint self-test: unsafe script/workflow/source expansions rejected; '
          'guards and nonempty-array comments accepted')
