#!/usr/bin/env python3
"""Generate the native design tokens. Python stdlib only; --check never writes."""
import argparse
import difflib
import json
import re
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
HEADER = '// 由 scripts/generate-design-tokens.py 从 design-tokens.json 生成，不要手改。\n'


def items(section):
    return ((key, value) for key, value in section.items() if not key.startswith('$'))


def camel(name):
    head, *tail = name.split('-')
    return head + ''.join(word[:1].upper() + word[1:] for word in tail)


def literal(value):
    return json.dumps(value, ensure_ascii=False)


def rgba(value):
    value = value.removeprefix('#')
    if len(value) not in (6, 8):
        raise ValueError(f'Invalid sRGB hex: {value}')
    return f'0x{value[:6]}', (str(int(value[6:], 16)) + ' / 255.0' if len(value) == 8 else '1')


def theme(data):
    lines = [HEADER.rstrip(), 'import SwiftUI', '#if os(iOS)', 'import UIKit', '#elseif os(macOS)', 'import AppKit', '#endif', '',
             'enum DS {', '    enum Color {']
    for name, token in items(data['color']):
        light, la = rgba(token['light'])
        dark, da = rgba(token['dark'])
        lines += [f"        /// {token['usage']}",
                  f'        static let {camel(name)}: SwiftUI.Color = DS.adaptive({light}, {dark}, lightAlpha: {la}, darkAlpha: {da})']
    lines += ['', '        struct Sample: Identifiable {', '            let name: String', '            let lightHex: String', '            let darkHex: String', '            let color: SwiftUI.Color', '            var id: String { name }', '        }', '        static let all: [Sample] = [']
    for name, token in items(data['color']):
        lines += [f'            Sample(name: {literal(name)}, lightHex: {literal(token["light"])}, darkHex: {literal(token["dark"])}, color: {camel(name)}),']
    lines += ['        ]', '    }', '', '    struct TextStyle {', '        enum Family: Equatable {', '            case text, num', '            var design: SwiftUI.Font.Design {', '                switch self {', f'                case .text: .{data["typography"]["families"]["text"]["swift"]}', f'                case .num: .{data["typography"]["families"]["num"]["swift"]}', '                }', '            }', '        }', '        let size: CGFloat', '        let lineHeight: CGFloat', '        let weight: SwiftUI.Font.Weight', '        let tracking: CGFloat', '        let family: Family', '        let relativeTo: SwiftUI.Font.TextStyle', '        let monospacedDigit: Bool', '        var design: SwiftUI.Font.Design { family.design }', '    }', '', '    enum Font {']
    for name, token in items(data['typography']['styles']):
        family = data['typography']['families'][token['family']]
        mono = str(family.get('monospacedDigit', False)).lower()
        lines += [f"        /// {token['usage']}", f'        static let {camel(name)} = TextStyle(size: {token["size"]}, lineHeight: {token["lineHeight"]}, weight: .{token["weight"]}, tracking: {token["tracking"]}, family: .{token["family"]}, relativeTo: .{token["relativeTo"]}, monospacedDigit: {mono})']
    lines += ['', '        struct Sample: Identifiable {', '            let name: String', '            let style: TextStyle', '            var id: String { name }', '        }', '        static let all: [Sample] = [']
    for name, _ in items(data['typography']['styles']):
        lines += [f'            Sample(name: {literal(name)}, style: {camel(name)}),']
    lines += ['        ]', '    }']
    for section, namespace in [('spacing', 'Space'), ('radius', 'Radius'), ('stroke', 'Stroke'), ('size', 'Size')]:
        lines += ['', f'    enum {namespace} {{']
        for name, token in items(data[section]):
            member = 's' + name.removeprefix('space-') if section == 'spacing' else camel(name.removeprefix('radius-')) if section == 'radius' else camel(name)
            lines += [f"        /// {token['usage']}"]
            if token['value'] == 'capsule':
                lines += ['        static let isPill = true']
            else:
                lines += [f'        static let {member}: CGFloat = {token["value"]}']
        lines += ['    }']
    lines += ['', '    enum Shape {', '        static var pill: Capsule { Capsule(style: .continuous) }', '    }', '', '    /// Exactly the four SwiftUI shadow arguments. No spread or inset.', '    struct Shadow {', '        let color: SwiftUI.Color', '        let radius: CGFloat', '        let x: CGFloat', '        let y: CGFloat']
    for name, token in items(data['shadow']):
        light, dark = token['light'], token['dark']
        if any(light[k] != dark[k] for k in ('radius', 'x', 'y')):
            raise ValueError(f'{name}: scheme-dependent geometry needs a new schema')
        light_hex, _ = rgba(data['color'][light['color']]['light'])
        dark_hex, _ = rgba(data['color'][dark['color']]['dark'])
        lines += [f"        /// {token['usage']}", f'        static let {camel(name.removeprefix("shadow-"))} = Shadow(color: DS.adaptive({light_hex}, {dark_hex}, lightAlpha: {light["opacity"]}, darkAlpha: {dark["opacity"]}), radius: {light["radius"]}, x: {light["x"]}, y: {light["y"]})']
    lines += ['    }', '', '    enum Material {', '        struct Descriptor {', '            let swift: String', '            let fallbackName: String', f'            var fallback: SwiftUI.Material {{ .{data["material"]["bar"]["fallback"].removesuffix("Material")} }}', '        }']
    for name, token in items(data['material']):
        lines += [f"        /// {token['usage']}", f'        static let {camel(name)} = Descriptor(swift: {literal(token["swift"])}, fallbackName: {literal(token["fallback"])})']
    lines += ['    }', '', '    enum Icon {']
    for name, symbol in items(data['icon']['symbols']):
        lines += [f'        static let {camel(name)} = {literal(symbol)}']
    lines += ['        enum Weight {']
    for name, weight in items(data['icon']['weight']):
        lines += [f'            static let {camel(name)}: SwiftUI.Font.Weight = .{weight}']
    lines += ['        }', '    }', '',
              '    private static func adaptive(_ light: UInt32, _ dark: UInt32, lightAlpha: CGFloat = 1, darkAlpha: CGFloat = 1) -> SwiftUI.Color {',
              '        #if os(iOS)',
              '        return SwiftUI.Color(uiColor: UIColor(dynamicProvider: { traits in',
              '            let isDark = traits.userInterfaceStyle == .dark',
              '            let hex = isDark ? dark : light',
              '            return UIColor(red: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: isDark ? darkAlpha : lightAlpha)',
              '        }))', '        #elseif os(macOS)',
              '        return SwiftUI.Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in',
              '            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua',
              '            let hex = isDark ? dark : light',
              '            return NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: isDark ? darkAlpha : lightAlpha)',
              '        }))', '        #endif', '    }', '}', '']
    return '\n'.join(lines)


def motion(data):
    tokens = data['motion']
    lines = [HEADER.rstrip(), 'import SwiftUI', '', 'enum DSMotion {', '    struct SpringToken {', '        let mass: Double', '        let stiffness: Double', '        let damping: Double', '        var spring: Spring { Spring(mass: mass, stiffness: stiffness, damping: damping) }', '    }']
    for name, token in items(tokens['springs']):
        lines += [f"    /// {token['usage']}", f'    static let {name} = Spring(mass: {token["mass"]}, stiffness: {token["stiffness"]}, damping: {token["damping"]})', f'    static let {name}Token = SpringToken(mass: {token["mass"]}, stiffness: {token["stiffness"]}, damping: {token["damping"]})', f'    static let {name}Animation: Animation = .spring({name})']
    lines += ['', '    static func interpolating(_ s: SpringToken) -> Animation {', '        .interpolatingSpring(mass: s.mass, stiffness: s.stiffness, damping: s.damping, initialVelocity: 0)', '    }', '', '    enum Press {', f'        static let scale: CGFloat = {tokens["press"]["scale"]}', f'        static let animation = {tokens["press"]["spring"]}Animation', f'        static let haptic: SensoryFeedback = .impact(weight: .{tokens["press"]["haptic"].removeprefix("impact-")})', '    }', '', '    enum Role: CaseIterable {']
    for name, token in items(tokens['roles']):
        lines += [f"        /// {token['usage']}", f'        case {camel(name)}']
    lines += ['', '        var animation: Animation? {', '            switch self {']
    for name, token in items(tokens['roles']):
        value = 'nil' if token['spring'] == 'system' else f'{token["spring"]}Animation'
        lines += [f'            case .{camel(name)}: {value}']
    lines += ['            }', '        }']
    for prop, swift_type in [('staggerDelay', 'Double'), ('offsetY', 'CGFloat')]:
        lines += [f'        var {prop}: {swift_type} {{', '            switch self {']
        for name, token in items(tokens['roles']):
            if prop in token:
                lines += [f'            case .{camel(name)}: {token[prop]}']
        lines += ['            default: 0', '            }', '        }']
    # The existing schema stores the float appearance scale in the role usage.
    # Preserve that source value instead of inventing or modifying a JSON token.
    float_scale = re.search(r'缩放 ([0-9.]+)', tokens['roles']['float-card']['usage'])
    if not float_scale:
        raise ValueError('motion.roles.float-card.usage must specify its appearance scale')
    lines += ['        var initialScale: CGFloat {', '            switch self {', f'            case .floatCard: {float_scale[1]}', '            default: 1', '            }', '        }']
    lines += ['    }', '', '    enum Property { case movement, opacity }', f'    static let reduceMotionAnimation: Animation = .spring({tokens["reduceMotion"]["spring"]})', f'    static let reduceMotionAllowed = {literal(tokens["reduceMotion"]["allow"])}',
              '    /// Reduced motion: callers MUST apply the opacity animation to opacity only.',
              '    /// Movement, scale, rotation and numeric replacement must jump immediately.',
              '    /// Sheet returns nil because the native presenter owns its spring.',
              '    static func animation(_ role: Role, reduceMotion: Bool) -> Animation? {', '        animation(role, reduceMotion: reduceMotion, property: .movement)', '    }', '    static func animation(_ role: Role, reduceMotion: Bool, property: Property) -> Animation? {',
              '        if reduceMotion { return property == .opacity ? reduceMotionAnimation : nil }', '        return role.animation', '    }', '', '    enum Haptic {']
    for name, value in items(tokens['haptics']):
        lines += [f'        static let {camel(name)}: SensoryFeedback = .{value}']
    lines += ['    }', '', '    struct LoopToken {', '        let phases: [Double]', '        let property: String', '        let spring: Spring', '        let hold: Double', '        var animation: Animation { .spring(spring).delay(hold) }', '    }', '    enum Loop {']
    for name, token in items(tokens['loops']):
        lines += [f"        /// {token['usage']}", f'        static let {camel(name)} = LoopToken(phases: {literal(token["phases"])}, property: {literal(token["property"])}, spring: {token["spring"]}, hold: {token["hold"]})']
    lines += ['    }', '}', '']
    return '\n'.join(lines)


def outputs(data):
    return {'DSTheme.swift': theme(data), 'DSMotion.swift': motion(data)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    data = json.loads((ROOT / 'design-tokens.json').read_text(encoding='utf-8'))
    stale = False
    for name, expected in outputs(data).items():
        path = ROOT / 'Sources/YubaiApp' / name
        actual = path.read_text(encoding='utf-8') if path.exists() else ''
        if args.check:
            if actual != expected:
                stale = True
                sys.stdout.writelines(difflib.unified_diff(actual.splitlines(keepends=True), expected.splitlines(keepends=True), fromfile=str(path.relative_to(ROOT)), tofile=f'{name} (generated)'))
        else:
            path.write_text(expected, encoding='utf-8')
            print(path.relative_to(ROOT))
    if stale:
        raise SystemExit(1)
    if args.check:
        print('Design tokens: PASS (generated Swift matches design-tokens.json)')


if __name__ == '__main__':
    main()
