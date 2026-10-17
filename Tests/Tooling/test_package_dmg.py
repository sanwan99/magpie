import hashlib
import importlib.util
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import unittest
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('packager', ROOT / 'Scripts/package-dmg.py')
packager = importlib.util.module_from_spec(spec)
spec.loader.exec_module(packager)


class PackageDMGTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.source = self.root / 'source/Magpie.app'
        self.output = self.root / 'dist/Magpie-0.4.0-alpha.1.dmg'
        self.checksum = self.output.with_name(self.output.name + '.sha256')
        (self.source / 'Contents/MacOS').mkdir(parents=True)
        (self.source / 'Contents/MacOS/Magpie').write_bytes(b'synthetic executable')
        (self.source / 'Contents/Info.plist').write_bytes(plistlib.dumps({
            'CFBundleIdentifier': 'com.sanwan.magpie', 'CFBundleExecutable': 'Magpie'}))
        self.commands = []
        self.fail_when = lambda args: False
        self.before_verify_image = lambda: None
        self.addCleanup(patch.stopall)
        patch.object(packager, 'run', side_effect=self.command).start()
        patch.object(packager.installer, 'run', side_effect=self.command).start()

    def command(self, *args):
        self.commands.append(args)
        if self.fail_when(args):
            raise subprocess.CalledProcessError(1, args)
        if args[0] == '/usr/bin/ditto':
            shutil.copytree(args[1], args[2], symlinks=True)
        if args[:2] == ('/usr/bin/hdiutil', 'create'):
            contents = Path(args[args.index('-srcfolder') + 1])
            self.assertEqual((contents / 'Applications').readlink(), Path('/Applications'))
            self.assertEqual((contents / 'Magpie.app/Contents/MacOS/Magpie').read_bytes(),
                             b'synthetic executable')
            self.assertIn('UDZO', args)
            self.assertNotIn('-ov', args)
            self.assertFalse(self.output.exists())
            self.assertFalse(self.checksum.exists())
            Path(args[-1]).write_bytes(b'synthetic verified disk image')
        if args[:2] == ('/usr/bin/hdiutil', 'verify'):
            self.before_verify_image()
        return subprocess.CompletedProcess(args, 0, '', 'TeamIdentifier=ABCDEFGHIJ\n')

    def package(self, **kwargs):
        return packager.package(kwargs.get('source', self.source),
                                kwargs.get('output', self.output),
                                kwargs.get('team_id', 'ABCDEFGHIJ'))

    def assert_no_artifacts(self):
        self.assertFalse(self.output.exists())
        self.assertFalse(self.checksum.exists())
        self.assertFalse(list(self.output.parent.glob('.magpie-package-*')))
        self.assertEqual((self.source / 'Contents/MacOS/Magpie').read_bytes(),
                         b'synthetic executable')

    def test_verified_copy_image_and_checksum_without_source_changes(self):
        image, checksum, digest = self.package()
        self.assertEqual((image, checksum), (self.output, self.checksum))
        self.assertEqual(digest, hashlib.sha256(self.output.read_bytes()).hexdigest())
        self.assertEqual(checksum.read_text(), f'{digest}  {self.output.name}\n')
        self.assertEqual(len([c for c in self.commands if c[0] == '/usr/sbin/spctl']), 2)
        self.assertEqual(len([c for c in self.commands if c[:3] ==
                             ('/usr/bin/xcrun', 'stapler', 'validate')]), 2)
        codesign = [c for c in self.commands if c[:2] == ('/usr/bin/codesign', '--verify')]
        self.assertEqual(len(codesign), 2)
        self.assertTrue(all('ABCDEFGHIJ' in c[c.index('-R') + 1] for c in codesign))
        self.assertFalse(any('--sign' in c or 'submit' in c or 'staple' in c or
                             'attach' in c for c in self.commands))
        self.assertFalse(list(self.output.parent.glob('.magpie-package-*')))
        self.assertFalse((self.source / 'Applications').exists())

    def test_missing_or_invalid_team_rejected_before_system_commands(self):
        for team in (None, '', 'too-short', 'ABCDEFGHI;'):
            with self.subTest(team=team), self.assertRaises(ValueError):
                self.package(team_id=team)
        self.assertEqual(self.commands, [])

    def test_wrong_identity_rejected(self):
        (self.source / 'Contents/Info.plist').write_bytes(plistlib.dumps({
            'CFBundleIdentifier': 'other', 'CFBundleExecutable': 'Magpie'}))
        with self.assertRaisesRegex(RuntimeError, 'identity'):
            self.package()
        self.assert_no_artifacts()

    def test_different_team_rejected_even_if_mocked_verifier_returns_it(self):
        with patch.object(packager.installer, 'verify', return_value='KLMNOPQRST'):
            with self.assertRaisesRegex(RuntimeError, 'team'):
                self.package()
        self.assert_no_artifacts()

    def test_symlink_source_rejected(self):
        link = self.root / 'linked.app'
        link.symlink_to(self.source)
        with self.assertRaises(RuntimeError):
            self.package(source=link)
        self.assert_no_artifacts()

    def test_bad_signature_or_gatekeeper_or_ticket_rejects_without_output(self):
        for executable in ('/usr/bin/codesign', '/usr/sbin/spctl', '/usr/bin/xcrun'):
            with self.subTest(executable=executable):
                self.fail_when = lambda args: args[0] == executable
                with self.assertRaises(subprocess.CalledProcessError):
                    self.package()
                self.assert_no_artifacts()

    def test_staged_ticket_failure_cleans_staging(self):
        self.fail_when = lambda args: args[0] == '/usr/bin/xcrun' and '.magpie-package-' in args[-1]
        with self.assertRaises(subprocess.CalledProcessError):
            self.package()
        self.assert_no_artifacts()

    def test_disk_image_create_or_verify_failure_cleans_staging(self):
        for operation in ('create', 'verify'):
            with self.subTest(operation=operation):
                self.fail_when = lambda args: args[:2] == ('/usr/bin/hdiutil', operation)
                with self.assertRaises(subprocess.CalledProcessError):
                    self.package()
                self.assert_no_artifacts()

    def test_existing_outputs_and_dangling_symlinks_are_never_overwritten(self):
        self.output.parent.mkdir()
        for destination in (self.output, self.checksum):
            for symlink in (False, True):
                with self.subTest(destination=destination.name, symlink=symlink):
                    if symlink:
                        destination.symlink_to(self.root / 'missing')
                    else:
                        destination.write_bytes(b'preexisting')
                    with self.assertRaises(FileExistsError):
                        self.package()
                    if symlink:
                        self.assertTrue(destination.is_symlink())
                    else:
                        self.assertEqual(destination.read_bytes(), b'preexisting')
                    destination.unlink()
        self.assertEqual(self.commands, [])

    def test_concurrent_dmg_publication_is_not_overwritten_and_own_checksum_removed(self):
        self.before_verify_image = lambda: self.output.write_bytes(b'other publisher')
        with self.assertRaises(FileExistsError):
            self.package()
        self.assertEqual(self.output.read_bytes(), b'other publisher')
        self.assertFalse(self.checksum.exists())
        self.assertFalse(list(self.output.parent.glob('.magpie-package-*')))

    def test_concurrent_checksum_publication_is_preserved(self):
        self.before_verify_image = lambda: self.checksum.write_bytes(b'other checksum')
        with self.assertRaises(FileExistsError):
            self.package()
        self.assertEqual(self.checksum.read_bytes(), b'other checksum')
        self.assertFalse(self.output.exists())

    def test_publication_error_does_not_leave_output_or_checksum(self):
        original_link = packager.os.link

        def fail_image(source, destination, **kwargs):
            if Path(destination) == self.output:
                raise OSError('filesystem cannot publish image')
            return original_link(source, destination, **kwargs)

        with patch.object(packager.os, 'link', side_effect=fail_image):
            with self.assertRaises(OSError):
                self.package()
        self.assert_no_artifacts()

    def test_invalid_output_and_output_inside_source_rejected(self):
        for output in (self.root / 'not-a-dmg.zip', self.root / 'bad\nname.dmg',
                       self.source / 'nested.dmg'):
            with self.subTest(output=repr(str(output))), self.assertRaises(ValueError):
                self.package(output=output)
        self.assertEqual(self.commands, [])
