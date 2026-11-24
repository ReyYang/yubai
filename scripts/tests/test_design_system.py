#!/usr/bin/env python3
"""Linux contracts for token regeneration, hosted targets and record-failure handling."""
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import unittest
import xml.etree.ElementTree as ET

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
        self.assertTrue(RECORD.recording_only(self.summary(), 14))
        self.assertTrue(RECORD.recording_only(self.summary('No reference was found on disk. Automatically recorded snapshot: /tmp/image.png'), 14))

    def test_mismatches_and_export_errors_are_failures(self):
        for message in ('Snapshot does not match reference', 'PNG export failed', 'Application crashed', 'XCTAssertEqual failed', 'Timed out', ''):
            self.assertFalse(RECORD.recording_only(self.summary(message), 14), message)

    def test_incomplete_or_missing_runs_cannot_pass(self):
        for count in (0, 1, 13, 15):
            self.assertFalse(RECORD.recording_only(self.summary(), count))
        for key, value in (('totalTestCount', 0), ('failedTests', 0), ('skippedTests', 1), ('testFailures', []), ('result', 'Stopped')):
            summary = self.summary(); summary[key] = value
            self.assertFalse(RECORD.recording_only(summary, 14), key)
        summary = self.summary()
        summary['testFailures'][0]['testName'] = 'OtherTests.testUnexpected'
        self.assertFalse(RECORD.recording_only(summary, 14))

    def test_a_second_unexpected_failure_stays_failing(self):
        summary = self.summary()
        summary['testFailures'].append({'testName': 'DesignSystemSnapshotTests.testGallerySections', 'failureText': 'PNG export failed'})
        self.assertFalse(RECORD.recording_only(summary, 14))


if __name__ == '__main__':
    unittest.main()
