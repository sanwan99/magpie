import importlib.util
import io
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('installer', ROOT / 'Scripts/install-app.py')
installer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(installer)


class InstallerTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.source = self.root / 'source/Magpie.app'
        self.target = self.root / 'Applications/Magpie.app'
        self.support = self.root / 'Support'
        self.make_app(self.source, b'new')
        self.commands = []
        self.addCleanup(patch.stopall)
        patch.object(installer, 'run', side_effect=self.run_command).start()
        patch.object(installer, 'stop_installed').start()
        self.launch = patch.object(installer, 'launch_and_check').start()

    def make_app(self, app, data):
        (app / 'Contents/MacOS').mkdir(parents=True)
        (app / 'Contents/MacOS/Magpie').write_bytes(data)
        (app / 'Contents/Info.plist').write_bytes(plistlib.dumps({
            'CFBundleIdentifier': installer.BUNDLE_ID, 'CFBundleExecutable': 'Magpie'}))

    def run_command(self, *args):
        self.commands.append(args)
        if args[0] == '/usr/bin/ditto':
            if '-c' in args:
                Path(args[-1]).write_bytes(b'archive')
            else:
                shutil.copytree(args[-2], args[-1])
        return subprocess.CompletedProcess(args, 0, '', 'TeamIdentifier=ABCDEFGHIJ\n')

    def install(self, **kwargs):
        if not kwargs.get('local_build'):
            kwargs.setdefault('team_id', 'ABCDEFGHIJ')
        return installer.install(self.source, self.target, self.support, **kwargs)

    def test_first_public_install_requires_expected_team_from_release(self):
        with self.assertRaisesRegex(RuntimeError, '--team-id'):
            installer.install(self.source, self.target, self.support)
        self.assertFalse(self.target.exists())

    def test_public_install_rejects_missing_team_identity(self):
        with patch.object(installer, 'verify', return_value=None):
            with self.assertRaisesRegex(RuntimeError, 'Developer ID team'):
                self.install()
        self.assertFalse(self.target.exists())

    def test_first_install_does_not_require_old_app_or_identity(self):
        self.install()
        self.assertEqual((self.target / 'Contents/MacOS/Magpie').read_bytes(), b'new')
        self.assertTrue(any(c[0] == '/usr/sbin/spctl' for c in self.commands))
        self.assertFalse(any('-c' in c for c in self.commands))

    def test_upgrade_backs_up_and_keeps_previous_bundle(self):
        self.make_app(self.target, b'old')
        backup = self.install()
        self.assertTrue((backup / 'Magpie.zip').exists())
        self.assertEqual((backup / 'Magpie.previous/Contents/MacOS/Magpie').read_bytes(), b'old')

    def test_post_install_archive_failure_preserves_recovery_and_reports_success(self):
        self.make_app(self.target, b'old')
        original_replace = installer.os.replace

        def fail_archive(source, destination):
            if Path(destination).name == 'Magpie.previous':
                raise OSError('archive unavailable')
            return original_replace(source, destination)

        warning = io.StringIO()
        with patch.object(installer.os, 'replace', side_effect=fail_archive), \
                patch.object(installer.sys, 'stderr', warning):
            backup = self.install()

        self.assertEqual((self.target / 'Contents/MacOS/Magpie').read_bytes(), b'new')
        self.launch.assert_called_once_with(self.target)
        previous = list(self.target.parent.glob('.Magpie-previous-*'))
        self.assertEqual(len(previous), 1)
        self.assertEqual((previous[0] / 'Contents/MacOS/Magpie').read_bytes(), b'old')
        self.assertTrue((backup / 'Magpie.zip').exists())
        self.assertFalse((backup / 'Magpie.previous').exists())
        self.assertIn('Installation succeeded', warning.getvalue())
        self.assertIn(str(previous[0]), warning.getvalue())
        self.assertIn(str(backup / 'Magpie.zip'), warning.getvalue())

    def test_upgrade_launch_failure_restores_original(self):
        self.make_app(self.target, b'old')
        self.launch.side_effect = RuntimeError('launch failed')
        with self.assertRaises(RuntimeError): self.install()
        self.assertEqual((self.target / 'Contents/MacOS/Magpie').read_bytes(), b'old')
        self.assertFalse(list(self.target.parent.glob('.Magpie-staging-*')))

    def test_first_install_launch_failure_leaves_no_installed_app(self):
        self.launch.side_effect = RuntimeError('launch failed')
        with self.assertRaises(RuntimeError): self.install()
        self.assertFalse(self.target.exists())

    def test_bad_signature_leaves_existing_app_untouched(self):
        self.make_app(self.target, b'old')
        def reject(*args):
            if args[0] == '/usr/bin/codesign':
                raise subprocess.CalledProcessError(1, args)
            return self.run_command(*args)
        installer.run.side_effect = reject
        with self.assertRaises(subprocess.CalledProcessError): self.install()
        self.assertEqual((self.target / 'Contents/MacOS/Magpie').read_bytes(), b'old')

    def test_local_build_is_explicit_and_still_verifies_signature(self):
        self.install(local_build=True)
        self.assertFalse(any(c[0] == '/usr/sbin/spctl' for c in self.commands))
        self.assertTrue(any(c[0] == '/usr/bin/codesign' and '--verify' in c for c in self.commands))

    def test_team_mismatch_refuses_upgrade(self):
        self.make_app(self.target, b'old')
        with patch.object(installer, 'verify', side_effect=['ABCDEFGHIJ', 'KLMNOPQRST']):
            with self.assertRaises(RuntimeError): self.install()
        self.assertEqual((self.target / 'Contents/MacOS/Magpie').read_bytes(), b'old')

    def test_symlink_source_is_rejected(self):
        link = self.root / 'linked.app'
        link.symlink_to(self.source)
        with self.assertRaises(RuntimeError):
            installer.install(link, self.target, self.support)

    def test_invalid_bundle_is_rejected(self):
        (self.source / 'Contents/Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier': 'other'}))
        with self.assertRaises(RuntimeError): self.install()

    def test_staging_failure_preserves_old_bundle_and_cleans_staging(self):
        self.make_app(self.target, b'old')
        original_verify = installer.verify
        def reject_staged(app, *args):
            if '.Magpie-staging-' in str(app): raise RuntimeError('staged verification failed')
            return original_verify(app, *args)
        with patch.object(installer, 'verify', side_effect=reject_staged):
            with self.assertRaises(RuntimeError): self.install()
        self.assertEqual((self.target / 'Contents/MacOS/Magpie').read_bytes(), b'old')
        self.assertFalse(list(self.target.parent.glob('.Magpie-staging-*')))
