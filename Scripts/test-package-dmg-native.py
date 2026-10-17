#!/usr/bin/env python3
"""macOS-only smoke test for real DMG tools using a disposable ad-hoc bundle.

This tests packaging mechanics, not Developer ID, Gatekeeper or notarization.
Only this test process replaces the packager's public-app verification callback.
No production command-line bypass exists; no real app or signing identity is used.
"""
import hashlib
import importlib.util
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tempfile
from unittest.mock import patch


def run(*args):
    return subprocess.run(args, check=True, text=True, capture_output=True, timeout=120)


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def main():
    if sys.platform != 'darwin':
        raise SystemExit('This native smoke test requires macOS; it has not run on this platform.')
    os.umask(0o077)
    spec = importlib.util.spec_from_file_location(
        'magpie_packager_native_test', Path(__file__).resolve().with_name('package-dmg.py'))
    packager = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(packager)
    work = Path(tempfile.mkdtemp(prefix='magpie-native-package-test-'))
    mount = work / 'mounted'
    attached = False
    try:
        source = work / 'source/Magpie.app'
        executable = source / 'Contents/MacOS/Magpie'
        executable.parent.mkdir(parents=True)
        fixture = b'#!/bin/sh\n# Disposable packaging fixture; never launched.\nexit 0\n'
        executable.write_bytes(fixture)
        executable.chmod(0o755)
        info = {
            'CFBundleIdentifier': 'com.sanwan.magpie',
            'CFBundleExecutable': 'Magpie',
            'CFBundleName': 'Magpie',
            'CFBundlePackageType': 'APPL',
            'CFBundleVersion': '1',
            'CFBundleShortVersionString': '0.0.0',
        }
        with (source / 'Contents/Info.plist').open('wb') as handle:
            plistlib.dump(info, handle)
        run('/usr/bin/codesign', '--force', '--sign', '-', str(source))

        verified = []

        def verify_disposable_app(app, _synthetic_team):
            # This single substitution is scoped to the smoke test. Every actual
            # ditto/hdiutil/file-publication operation still uses production code.
            packager.installer.verify(app, local_build=True)
            verified.append(Path(app))

        output = work / 'output/Magpie-native-smoke.dmg'
        with patch.object(packager, 'verify_app', side_effect=verify_disposable_app):
            image, checksum, digest = packager.package(source, output, 'TESTNATIVE')
            require(len(verified) == 2, 'Source and staged signatures were not both verified.')
            try:
                packager.package(source, output, 'TESTNATIVE')
            except FileExistsError:
                pass
            else:
                raise RuntimeError('Packaging overwrote an existing output.')

        actual_digest = hashlib.sha256(image.read_bytes()).hexdigest()
        require(actual_digest == digest, 'DMG digest does not match its bytes.')
        require(checksum.read_text() == f'{actual_digest}  {image.name}\n',
                'Checksum sidecar does not describe the generated DMG.')
        require(executable.read_bytes() == fixture, 'Source bundle changed during packaging.')
        require(not list(image.parent.glob('.magpie-package-*')), 'Packaging staging was retained.')

        # Inspect the real read-only filesystem, including the symlink as stored
        # in the image. Never launch the fixture or follow the Applications link.
        mount.mkdir()
        run('/usr/bin/hdiutil', 'attach', '-readonly', '-nobrowse', '-noautoopen',
            '-mountpoint', str(mount), str(image))
        attached = True
        require((mount / 'Applications').is_symlink(), 'Applications shortcut is not a symlink.')
        require(os.readlink(mount / 'Applications') == '/Applications',
                'Applications shortcut has an unexpected target.')
        require((mount / 'Magpie.app/Contents/MacOS/Magpie').read_bytes() == fixture,
                'Mounted executable differs from the source fixture.')
        with (mount / 'Magpie.app/Contents/Info.plist').open('rb') as handle:
            require(plistlib.load(handle) == info, 'Mounted bundle metadata changed.')
        packager.installer.verify(mount / 'Magpie.app', local_build=True)
    finally:
        # Also handle an attach command that mounted before reporting an error.
        # If detach fails, keep the mount's directory for recovery rather than
        # recursively deleting through a mounted filesystem.
        try:
            if attached or os.path.ismount(mount):
                run('/usr/bin/hdiutil', 'detach', str(mount))
        finally:
            if os.path.ismount(mount):
                print(f'Native test volume remains mounted at {mount}; detach it before cleanup.',
                      file=sys.stderr)
            else:
                shutil.rmtree(work)
    print('NATIVE_DMG_SMOKE: PASS — real ad-hoc codesign, ditto, hdiutil create/verify, '
          'read-only mount, Applications link, SHA-256 and no-overwrite checks.')
    print('Developer ID, Gatekeeper, notarization and end-user installation were not tested.')


if __name__ == '__main__':
    try:
        main()
    except subprocess.CalledProcessError as error:
        print(error.stderr or '', file=sys.stderr)
        raise SystemExit(str(error))
    except (RuntimeError, OSError, ValueError, subprocess.TimeoutExpired) as error:
        raise SystemExit(str(error))
