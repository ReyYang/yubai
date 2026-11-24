#!/usr/bin/env python3
"""Linux contracts for token regeneration, hosted targets and record-failure handling."""
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import struct
import subprocess
import sys
import tempfile
import unittest
import xml.etree.ElementTree as ET
import zlib

ROOT = Path(__file__).resolve().parents[2]


def module(name):
    spec = importlib.util.spec_from_file_location(name.replace('-', '_'), ROOT / 'scripts' / (name + '.py'))
    loaded = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(loaded)
    return loaded


GEN = module('generate-design-tokens')
RECORD = module('check-ds-snapshot-result')


class SourceLintTests(unittest.TestCase):
    def test_lint_and_its_self_tests_pass(self):
        result = subprocess.run([sys.executable, str(ROOT / 'scripts/ui_consistency.py'), '--self-test'],
                                cwd=ROOT, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


class TokenGenerationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.data = json.loads((ROOT / 'design-tokens.json').read_text())
        cls.outputs = GEN.outputs(cls.data)

    def test_checked_in_files_are_exactly_reproducible(self):
        self.assertEqual(self.outputs, GEN.outputs(self.data))
        for name, content in self.outputs.items():
            self.assertTrue(content.startswith(GEN.HEADER))
            self.assertEqual((ROOT / 'Sources/YubaiApp' / name).read_text(), content)

    def test_rgba_keeps_srgb_channels_and_alpha(self):
        self.assertEqual(GEN.rgba('#112233'), ('0x112233', '1'))
        self.assertEqual(GEN.rgba('#11223380'), ('0x112233', '128 / 255.0'))
        self.assertIn('lightAlpha: 191 / 255.0, darkAlpha: 191 / 255.0', self.outputs['DSTheme.swift'])
        self.assertIn('lightAlpha: 82 / 255.0, darkAlpha: 128 / 255.0', self.outputs['DSTheme.swift'])
        with self.assertRaises(ValueError):
            GEN.rgba('#123')

    def test_every_spring_preserves_its_physical_parameters(self):
        motion = self.outputs['DSMotion.swift']
        for name, token in GEN.items(self.data['motion']['springs']):
            arguments = f'mass: {token["mass"]}, stiffness: {token["stiffness"]}, damping: {token["damping"]}'
            self.assertIn(f'static let {name} = Spring({arguments})', motion)
            self.assertIn(f'static let {name}Token = SpringToken({arguments})', motion)
            self.assertIn(f'static let {name}Animation: Animation = .spring({name})', motion)
        self.assertIn('initialVelocity: 0', motion)
        self.assertIn('case .floatCard: 0.96', motion)
        self.assertNotRegex(motion, r'\.(easeIn|easeOut|easeInOut|linear|timingCurve)\b')

    def test_families_are_read_from_json(self):
        changed = json.loads(json.dumps(self.data))
        changed['typography']['families']['num']['swift'] = 'monospaced'
        changed['typography']['families']['num']['monospacedDigit'] = False
        output = GEN.theme(changed)
        self.assertIn('case .num: .monospaced', output)
        self.assertIn('relativeTo: .largeTitle, monospacedDigit: false', output)

    def test_naming_and_negative_tracking(self):
        self.assertEqual([GEN.camel(value) for value in ('ink-2', 'accent-soft', 'n-spine-lg')], ['ink2', 'accentSoft', 'nSpineLg'])
        self.assertIn('static let s12: CGFloat = 12', self.outputs['DSTheme.swift'])
        self.assertIn('tracking: -0.3', self.outputs['DSTheme.swift'])
        self.assertIn('Capsule(style: .continuous)', self.outputs['DSTheme.swift'])

    def test_shadow_has_four_fields_and_separate_scheme_opacity(self):
        theme = self.outputs['DSTheme.swift']
        shadow = theme.split('struct Shadow {', 1)[1].split('enum Material', 1)[0]
        self.assertEqual(re.findall(r'^        let (\w+):', shadow, re.M), ['color', 'radius', 'x', 'y'])
        self.assertIn('lightAlpha: 0.22, darkAlpha: 0.55', shadow)
        self.assertNotIn('spread', shadow)

    def test_check_is_read_only_and_reports_missing_and_stale_files(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'scripts').mkdir()
            (root / 'Sources/YubaiApp').mkdir(parents=True)
            (root / 'scripts/generate-design-tokens.py').write_text((ROOT / 'scripts/generate-design-tokens.py').read_text())
            (root / 'design-tokens.json').write_text(json.dumps(self.data))
            command = [sys.executable, str(root / 'scripts/generate-design-tokens.py')]
            missing = subprocess.run(command + ['--check'], capture_output=True, text=True)
            self.assertEqual(missing.returncode, 1)
            self.assertFalse((root / 'Sources/YubaiApp/DSTheme.swift').exists())
            self.assertEqual(subprocess.run(command, capture_output=True).returncode, 0)
            self.assertEqual(subprocess.run(command + ['--check'], capture_output=True).returncode, 0)
            stale = root / 'Sources/YubaiApp/DSMotion.swift'
            stale.write_text(stale.read_text().replace('stiffness: 300', 'stiffness: 301'))
            before = stale.read_bytes()
            result = subprocess.run(command + ['--check'], capture_output=True, text=True)
            self.assertEqual(result.returncode, 1)
            self.assertIn('--- Sources/YubaiApp/DSMotion.swift', result.stdout)
            self.assertIn('+    static let snappy = Spring(mass: 1, stiffness: 300, damping: 22)', result.stdout)
            self.assertEqual(stale.read_bytes(), before)


class HostedProjectTests(unittest.TestCase):
    def test_generated_project_is_stable_and_snapshot_link_is_test_only(self):
        paths = [ROOT / 'Yubai.xcodeproj/project.pbxproj', ROOT / 'Yubai.xcodeproj/xcshareddata/xcschemes/Yubai.xcscheme']
        before = [path.read_bytes() for path in paths]
        resolved = (ROOT / 'Package.resolved').read_bytes()
        result = subprocess.run([sys.executable, str(ROOT / 'scripts/generate-project.py')], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual([path.read_bytes() for path in paths], before)
        self.assertEqual((ROOT / 'Package.resolved').read_bytes(), resolved)
        pbx = paths[0].read_text()
        def ident(name):
            return hashlib.sha1(name.encode()).hexdigest()[:24].upper()
        def obj(name):
            return re.search(r'^' + ident(name) + r' = (.*?)(?=\n[0-9A-F]{24} = |\n}; rootObject)', pbx, re.M | re.S)[1]
        self.assertIn('kind = exactVersion; version = 1.19.6;', obj('snapshot-package'))
        self.assertNotIn(ident('snapshot-package-product'), obj('target'))
        self.assertIn(ident('snapshot-package-product'), obj('snapshot-target'))
        self.assertNotIn(ident('snapshot-link'), obj('frameworks'))
        self.assertIn(ident('snapshot-link'), obj('snapshot-frameworks'))
        self.assertIn('BUNDLE_LOADER = "$(TEST_HOST)"', obj('snapshot-config:Debug'))
        self.assertIn('TEST_HOST = "$(BUILT_PRODUCTS_DIR)/Yubai.app/Yubai"', obj('snapshot-config:Debug'))
        for file in ('DSTheme.swift', 'DSMotion.swift', 'DSStyle.swift', 'DSComponents.swift', 'DesignSystemGalleryView.swift'):
            self.assertIn(ident('Sources/YubaiApp/' + file), pbx)
        testables = ET.parse(paths[1]).findall('./TestAction/Testables/TestableReference/BuildableReference')
        self.assertIn('YubaiDesignSystemTests', [element.attrib['BlueprintName'] for element in testables])


class RecordingResultTests(unittest.TestCase):
    def summary(self, message='Record mode is on. Automatically recorded snapshot: /tmp/test.png'):
        return {'result': 'Failed', 'totalTestCount': 1, 'passedTests': 0, 'failedTests': 1,
                'skippedTests': 0, 'testFailures': [{'testName': 'DesignSystemSnapshotTests.testGallerySections', 'failureText': message}]}

    def test_expected_recording_assertions_are_accepted(self):
        self.assertTrue(RECORD.recording_only(self.summary(), 20))
        self.assertTrue(RECORD.recording_only(self.summary('No reference was found on disk. Automatically recorded snapshot: /tmp/image.png'), 20))

    def test_mismatches_and_export_errors_are_failures(self):
        for message in ('Snapshot does not match reference', 'PNG export failed', 'Application crashed', 'XCTAssertEqual failed', 'Timed out', ''):
            self.assertFalse(RECORD.recording_only(self.summary(message), 20), message)

    def test_incomplete_or_missing_runs_cannot_pass(self):
        for count in (0, 1, 14, 19, 21):
            self.assertFalse(RECORD.recording_only(self.summary(), count))
        for key, value in (('totalTestCount', 0), ('failedTests', 0), ('skippedTests', 1), ('testFailures', []), ('result', 'Stopped')):
            summary = self.summary(); summary[key] = value
            self.assertFalse(RECORD.recording_only(summary, 20), key)
        summary = self.summary()
        summary['testFailures'][0]['testName'] = 'OtherTests.testUnexpected'
        self.assertFalse(RECORD.recording_only(summary, 20))

    def test_a_second_unexpected_failure_stays_failing(self):
        summary = self.summary()
        summary['testFailures'].append({'testName': 'DesignSystemSnapshotTests.testGallerySections', 'failureText': 'PNG export failed'})
        self.assertFalse(RECORD.recording_only(summary, 20))


class PNGValidationTests(unittest.TestCase):
    @staticmethod
    def png(colour_type, scanlines, *, depth=8, interlace=0):
        """Build a 2×2 PNG from already-filtered bytes, with two IDAT chunks."""
        def chunk(kind, data):
            return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind + data))
        header = struct.pack('>IIBBBBB', 2, 2, depth, colour_type, 0, 0, interlace)
        compressed = zlib.compress(scanlines)
        middle = len(compressed) // 2
        return (b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', header)
                + chunk(b'IDAT', compressed[:middle]) + chunk(b'IDAT', compressed[middle:])
                + chunk(b'IEND', b''))

    def test_single_flat_colour_is_rejected_for_all_supported_types_and_filters(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'flat.png'
            for colour_type, pixel in ((0, b'\x50'), (2, b'\x50\x64\x78'),
                                       (4, b'\x50\xff'), (6, b'\x50\x64\x78\xff')):
                zero = bytes(len(pixel))
                half = bytes(value - value // 2 for value in pixel)
                # Known encodings of two identical rows of two identical pixels.
                scanlines = (
                    (b'\x00' + pixel * 2) * 2,                         # None
                    (b'\x01' + pixel + zero) * 2,                      # Sub
                    b'\x02' + pixel * 2 + b'\x02' + zero * 2,           # Up
                    b'\x03' + pixel + half + b'\x03' + half + zero,     # Average
                    b'\x04' + pixel + zero + b'\x04' + zero * 2,         # Paeth
                )
                for filter_type, encoded in enumerate(scanlines):
                    with self.subTest(colour_type=colour_type, filter_type=filter_type):
                        path.write_bytes(self.png(colour_type, encoded))
                        self.assertIn('flat colour', RECORD.png_blank_reason(path))

    def test_transparent_images_with_varying_hidden_colours_are_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'transparent.png'
            for colour_type, scanlines in (
                (4, b'\x00\x10\x00\x80\x00\x00\xc0\x00\xff\x00'),
                (6, b'\x00' + bytes((10, 20, 30, 0, 90, 80, 70, 0))
                    + b'\x00' + bytes((100, 120, 130, 0, 200, 210, 220, 0))),
            ):
                with self.subTest(colour_type=colour_type):
                    path.write_bytes(self.png(colour_type, scanlines))
                    self.assertIn('fully transparent', RECORD.png_blank_reason(path))

    def test_visible_variation_in_the_last_pixel_is_accepted(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'visible.png'
            for colour_type, pixel in ((0, b'\x50'), (2, b'\x50\x64\x78'),
                                       (4, b'\x00\xff'), (6, b'\x00\x00\x00\xff')):
                with self.subTest(colour_type=colour_type):
                    zero = bytes(len(pixel))
                    path.write_bytes(self.png(colour_type, b'\x00' + zero * 2 + b'\x00' + zero + pixel))
                    self.assertIsNone(RECORD.png_blank_reason(path))

    def test_malformed_and_unsupported_images_are_rejected(self):
        valid = self.png(0, b'\x00\x10\x20\x00\x30\x40')
        images = (
            b'not a PNG', valid[:20], valid[:-12], valid[:-1] + bytes([valid[-1] ^ 1]),
            self.png(0, b'\x00\x10\x20\x00\x30\x40', depth=16),
            self.png(0, b'\x00\x10\x20\x00\x30\x40', interlace=1),
            self.png(3, b'\x00\x10\x20\x00\x30\x40'),
            self.png(0, b'\x05\x10\x20\x00\x30\x40'),
            self.png(0, b'\x00\x10\x20'),
        )
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'invalid.png'
            for index, data in enumerate(images):
                with self.subTest(image=index):
                    path.write_bytes(data)
                    with self.assertRaises(ValueError):
                        RECORD.png_blank_reason(path)

    def test_cli_rejects_blank_exports_even_when_recording_assertions_are_expected(self):
        valid = self.png(0, b'\x00\x10\x20\x00\x30\x40')
        blanks = (
            self.png(4, b'\x00\x10\x00\x80\x00\x00\xc0\x00\xff\x00'),
            self.png(2, (b'\x00' + bytes((50, 100, 150)) * 2) * 2),
        )
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            summary = root / 'summary.json'
            summary.write_text(json.dumps(RecordingResultTests().summary()))
            for index in range(19):
                (root / f'section-{index}.png').write_bytes(valid)
            path = root / 'components-skeleton-light.png'
            path.write_bytes(valid)
            # CI validates successful comparisons as well as expected record failures.
            for summary_args in ([], [str(summary)]):
                command = [sys.executable, str(ROOT / 'scripts/check-ds-snapshot-result.py'),
                           *summary_args, '--png-dir', str(root)]
                result = subprocess.run(command, capture_output=True, text=True)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                for blank in blanks:
                    path.write_bytes(blank)
                    result = subprocess.run(command, capture_output=True, text=True)
                    self.assertNotEqual(result.returncode, 0)
                    self.assertIn(f'Blank PNG {path.name}', result.stderr)
                path.unlink()
                result = subprocess.run(command, capture_output=True, text=True)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn('Expected 20 PNGs, found 19', result.stderr)
                path.write_bytes(valid)


if __name__ == '__main__':
    unittest.main()
