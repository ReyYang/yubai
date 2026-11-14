#!/usr/bin/env python3
"""Round-46 source contracts. Run on Linux before the Apple SDK build."""
import argparse
import re
from pathlib import Path
from gallery_inventory import check as check_gallery

ROOT = Path(__file__).resolve().parents[1]
# Only the shared design system implements input, navigation and geometry.
# Domain/fixture/page files receive no blanket exceptions.
SHARED = 'DesignSystem.swift'
OLD_NAMES = ('\u6211\u7684\u6d88\u8d39\u89c2', '\u5e38\u8bb0\u7684\u51e0\u7b14', '\u8fdb\u51fa\u8bb0\u5f55',
             '\u85cf\u8d77\u6765\u7684', '\u5206\u4e00\u5206', '\u4e00\u4e2a\u4e2a\u5206', '\u6309\u5bf9\u65b9\u5206',
             '\u4f59\u767d\u60f3\u8fd9\u6837\u6539', '\u6574\u7406\u597d\u4e86', '\u5f85\u5904\u7406')
OLD_NAMES += ('\u5b58\u7740\u4e0d\u52a8', '\u5907\u7528\u91d1')
TOKEN = re.compile(r'//[^\n]*|/\*.*?\*/|"(?:\\.|[^"\\])*"', re.S)
NUMBER = r'-?\d+(?:\.\d+)?(?![\w.])'
GEOMETRY = re.compile(r'\b(?:spacing|rowSpacing|topPadding|minLength|minimumDistance|lineHeight|topLeadingRadius|topTrailingRadius|bottomLeadingRadius|bottomTrailingRadius|min|ideal|max|width|height|minWidth|maxWidth|minHeight|maxHeight|idealWidth|idealHeight|cornerRadius|radius|size|minimum|maximum|lineWidth|top|bottom|leading|trailing|x|y):\s*' + NUMBER)
PADDING = re.compile(r'\.padding\(\s*(?:\.[A-Za-z]+,\s*)?' + NUMBER)
DETENT = re.compile(r'\.(?:height|presentationCornerRadius)\(\s*' + NUMBER)


def masks(source):
    """Ignore quoted examples and comments in code checks; retain strings for names."""
    def mask(m):
        return ''.join('\n' if ch == '\n' else ' ' for ch in m[0])
    code = TOKEN.sub(mask, source)
    comments = TOKEN.sub(lambda m: m[0] if m[0].startswith('"') else mask(m), source)
    return code, comments


def violations(name, source):
    code, comments = masks(source)
    found = []
    def reject(pattern, reason, text=code):
        for match in re.finditer(pattern, text):
            line = text.count('\n', 0, match.start()) + 1
            found.append(f'{name}:{line}: {reason}')
    for old in OLD_NAMES:
        reject(re.escape(old), 'obsolete interface name', comments)
    reject(r'CashTimeline|PaceChart|LineMark|AreaMark|AnswerChart|ShowChartTool|show_chart|import\s+Charts', 'deleted line-chart code')
    reject(r'\b(?:ContentViewportTarget|ViewportButtonStyle|yubaiContentViewport)\b|\.contentViewportTarget\s*\(',
           'removed per-control viewport gate: bound the scroll view in layout')
    reject(r'\.buttonStyle\((?:PressButtonStyle|TextLinkStyle)\([^)]*\)\)\s*\.yubaiHitTarget\(',
           'external link hit target: put it inside the label or use TextLinkStyle')
    if name == SHARED:
        # Card/search/chat must all reach the same full-height native editor.
        # A DS-only blanket exemption previously allowed a one-line AX node to
        # bypass the shared field row and its minimum hit area.
        input_ranges = []
        for declaration in re.finditer(r'\bstruct\s+(?:RowTextInput|NativeRowInput)\b[^\{]*\{', code):
            depth, end = 1, declaration.end()
            while end < len(code) and depth:
                depth += (code[end] == '{') - (code[end] == '}')
                end += 1
            input_ranges.append((declaration.start(), end))
        for match in re.finditer(r'\b(?:TextField|SecureField|TextEditor|UITextField|UITextView)\s*\(', code):
            if not any(start <= match.start() < end for start, end in input_ranges):
                found.append(f'{name}:{code.count(chr(10), 0, match.start()) + 1}: input bypasses shared RowTextInput')
        return found
    reject(r'\b(?:TextField|SecureField|TextEditor|UITextField|UITextView|DatePicker)\s*\(', 'raw input: use a DS control')
    reject(r'"(?:chevron\.left|arrow\.left)"|navigationBarBackButtonHidden|struct\s+\w*BackButton\b', 'hand-made back button', comments)
    reject(r'struct\s+\w*(?:Toast|UndoBar)\b|accessibilityIdentifier\("toastMessage"\)', 'hand-made toast: use Toast', comments)
    reject(GEOMETRY, 'raw geometry: use a design token')
    reject(PADDING, 'raw padding: use a spacing token')
    reject(DETENT, 'raw sheet size: use a DS sheet')
    # Catch page-specific constants and ternary geometry, as well as direct literals.
    reject(r'\b(?:let|var)\s+\w*(?:Size|Height|Width|Spacing|Radius)\s*:\s*CGFloat\s*=\s*' + NUMBER, 'page geometry constant belongs in DS')
    for match in re.finditer(r'\.(?:padding|frame|offset)\([^\n;]*?\)', code):
        if '?' in match[0] and re.search(r'(?:\?|:)\s*' + NUMBER, match[0]):
            found.append(f'{name}:{code.count(chr(10), 0, match.start()) + 1}: raw conditional geometry')
    reject(r'(?:navigationTitle|manualSheetHeader)\("(?:一组|明细|分类对应)"', 'ambiguous page name', comments)
    return found


def self_test():
    invalid = ['struct ContentViewportTarget: ViewModifier {}',
               'TextField("名字", text: $name)', 'SecureField("密钥", text: $key)',
               'DatePicker("日期", selection: $date)',
               'Button { back() } label: { Image(systemName: "chevron.left") }',
               'struct HandmadeToast: View {}', 'VStack(spacing: 12) {}',
               'Text("x").frame(height: 52)', 'Text("x").padding(.horizontal, 20)',
               'Text("x").frame(height: large ? 48 : 44)',
               'Button("全部") {}.buttonStyle(PressButtonStyle()).yubaiHitTarget()']
    for sample in invalid:
        assert violations('Page.swift', sample), sample
    assert not violations('Page.swift', '// TextField("sample", text: $name)\nVStack(spacing: YubaiSpace.gapGroup) { CardTextFieldRow(title: "名字", text: $name) }')
    assert violations(SHARED, 'TextField("", text: $text).frame(height: 52)')
    assert violations(SHARED, 'UITextView()')
    assert not violations(SHARED, 'private struct RowTextInput: View { TextField("", text: $text) }')
    assert not violations(SHARED, 'private struct NativeRowInput { let field = UITextField() }')
    print('UI lint self-test: raw inputs, back, toast, geometry rejected; tokens accepted')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--self-test', action='store_true')
    args = parser.parse_args()
    if args.self_test:
        self_test()
    errors = []
    for path in sorted((ROOT / 'Sources/YubaiApp').glob('*.swift')):
        errors.extend(violations(path.name, path.read_text()))
    for directory in ('Sources/YubaiCore', 'Tests'):
        for path in (ROOT / directory).rglob('*.swift'):
            code, _ = masks(path.read_text())
            if re.search(r'CashTimeline|PaceChart|LineMark|AreaMark|AnswerChart|ShowChartTool|show_chart|import\s+Charts', code):
                errors.append(str(path.relative_to(ROOT)) + ': deleted chart reference')
    ds = (ROOT / 'Sources/YubaiApp' / SHARED).read_text()
    app_source = '\n'.join(p.read_text() for p in (ROOT / 'Sources/YubaiApp').glob('*.swift'))
    for symbol in ('CardTextFieldRow', 'MoneyInputRow', 'SearchInput', 'ChatInputBar', 'Toast', 'ManualSheetHeader', 'HeaderIconButton', 'ConfirmationSheet', 'KeypadSheet', 'AmountKeypad', 'EntryCalendarView', 'EntryDateChip', 'Segmented', 'CategoryChoiceChip', 'EmptyState', 'DestructiveButtonStyle', 'TextLinkStyle', 'RowToggleStyle', 'AdaptiveValueRow'):
        if len(re.findall(r'\bstruct ' + symbol + r'\b', ds)) != 1 or len(re.findall(r'\bstruct ' + symbol + r'\b', app_source)) != 1:
            errors.append('Expected one DS definition: ' + symbol)
    # Names also occur in accessibility fixtures and documentation; forbid stale
    # presentation wording there. Escaped archived raw values remain compatible.
    text_files = list((ROOT / 'Sources').rglob('*.swift')) + list((ROOT / 'Tests').rglob('*.swift'))
    text_files += list((ROOT / 'docs').rglob('*.md')) + [ROOT / 'CONTEXT.md', ROOT / 'README.md']
    for path in text_files:
        for old in OLD_NAMES:
            if old in path.read_text():
                errors.append(str(path.relative_to(ROOT)) + ': obsolete name in source/test/docs')
    try:
        walks, boards = check_gallery(ROOT)
        print(f'Gallery coverage: {len(boards)} boards; {len(walks)} CI walks; no missing stops')
    except ValueError as error:
        errors.append(str(error))
    if errors:
        print('\n'.join(errors))
        raise SystemExit(1)
    print('UI consistency: PASS (shared inputs/back/toast, tokens, vocabulary, charts, gallery)')


if __name__ == '__main__':
    main()
