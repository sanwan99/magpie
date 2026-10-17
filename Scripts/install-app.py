#!/usr/bin/env python3
"""Install a verified app, with distinct first-install and upgrade transactions.

Public builds must pass Gatekeeper and Developer ID validation. --local-build is
an explicit developer-only opt-in for locally built/ad-hoc signed applications.
Backups cover the application bundle, not clipboard data or schema downgrades.
"""
import argparse
from datetime import datetime, timezone
import os
from pathlib import Path
import plistlib
import re
import shutil
import signal
import subprocess
import time
import uuid

TARGET = Path('/Applications/Magpie.app')
SUPPORT = Path.home() / 'Library/Application Support/Magpie'
BUNDLE_ID = 'com.sanwan.magpie'


def run(*args):
    return subprocess.run(args, check=True, text=True, capture_output=True)


def processes():
    result = subprocess.run(['/usr/bin/pgrep', '-x', 'Magpie'], text=True, capture_output=True)
    if result.returncode not in (0, 1):
        raise RuntimeError('Could not inspect running Magpie processes.')
    entries = []
    for pid in result.stdout.split():
        detail = run('/bin/ps', '-p', pid, '-o', 'comm=')
        entries.append((int(pid), detail.stdout.strip()))
    return entries


def stop_installed(target):
    executable = str(target / 'Contents/MacOS/Magpie')
    running = processes()
    if any(command != executable for _, command in running):
        raise RuntimeError('A different Magpie copy is running; close it before installing.')
    for pid, _ in running:
        os.kill(pid, signal.SIGTERM)
    deadline = time.monotonic() + 10
    while processes() and time.monotonic() < deadline:
        time.sleep(0.25)
    if processes():
        raise RuntimeError('Magpie did not exit; replacement was not performed.')


def validate_bundle(app):
    if app.is_symlink() or not app.is_dir():
        raise RuntimeError(f'Expected a regular application directory: {app}')
    with (app / 'Contents/Info.plist').open('rb') as handle:
        info = plistlib.load(handle)
    if info.get('CFBundleIdentifier') != BUNDLE_ID or info.get('CFBundleExecutable') != 'Magpie':
        raise RuntimeError('Unexpected application identity.')


def verify(app, local_build=False, expected_team=None):
    validate_bundle(app)
    requirement = '=identifier "com.sanwan.magpie"'
    if not local_build:
        requirement += ' and anchor apple generic and certificate leaf[field.1.2.840.113635.100.6.1.13] exists'
    if expected_team:
        if not re.fullmatch(r'[A-Z0-9]{10}', expected_team):
            raise RuntimeError('Invalid Developer ID team identifier.')
        requirement += f' and certificate leaf[subject.OU] = "{expected_team}"'
    run('/usr/bin/codesign', '--verify', '--deep', '--strict', '-R', requirement, str(app))
    if not local_build:
        run('/usr/sbin/spctl', '--assess', '--type', 'execute', '--verbose=2', str(app))
    details = run('/usr/bin/codesign', '-dv', '--verbose=4', str(app)).stderr
    match = re.search(r'^TeamIdentifier=([A-Z0-9]{10})$', details, re.MULTILINE)
    return match.group(1) if match else None


def launch_and_check(target):
    run('/usr/bin/open', str(target))
    deadline = time.monotonic() + 10
    executable = str(target / 'Contents/MacOS/Magpie')
    while time.monotonic() < deadline:
        running = processes()
        if len(running) == 1 and running[0][1] == executable:
            time.sleep(1)
            if processes() == running:
                return
        time.sleep(0.25)
    raise RuntimeError('Could not verify the installed process.')


def install(source, target=TARGET, support=SUPPORT, local_build=False, team_id=None):
    source = Path(source).absolute()
    target = Path(target).absolute()
    support = Path(support)
    if source.is_symlink() or source.resolve() == target.resolve():
        raise RuntimeError('Source must be a separate app bundle, not a symlink or installed target.')
    previous_exists = target.exists() or target.is_symlink()
    source_team = verify(source, local_build, team_id)
    if previous_exists:
        # Verify the old bundle as well; do not silently replace a damaged or
        # differently signed installation. Explicit --local-build allows a
        # developer to migrate a locally signed app to another local identity.
        old_team = verify(target, local_build)
        if not local_build and old_team != source_team:
            raise RuntimeError('Developer ID changed. Inspect the release before upgrading.')
    target.parent.mkdir(parents=True, exist_ok=True)
    support.mkdir(parents=True, exist_ok=True, mode=0o700)
    backup_root = support / 'Backups'
    backup_root.mkdir(parents=True, exist_ok=True, mode=0o700)
    backup = backup_root / (datetime.now(timezone.utc).strftime('%Y%m%d-%H%M%S') + '-' + uuid.uuid4().hex[:8])
    backup.mkdir(mode=0o700)
    staged = target.parent / ('.Magpie-staging-' + uuid.uuid4().hex)
    previous = target.parent / ('.Magpie-previous-' + uuid.uuid4().hex)
    displaced = False
    installed = False
    try:
        run('/usr/bin/ditto', str(source), str(staged))
        verify(staged, local_build, team_id or (source_team if not local_build else None))
        stop_installed(target)
        if previous_exists:
            archive = backup / 'Magpie.zip'
            run('/usr/bin/ditto', '-c', '-k', '--sequesterRsrc', '--keepParent', str(target), str(archive))
            run('/usr/bin/unzip', '-tq', str(archive))
            os.replace(target, previous)  # Same volume, atomic rename.
            displaced = True
        os.replace(staged, target)
        installed = True
        verify(target, local_build, team_id or (source_team if not local_build else None))
        launch_and_check(target)
    except Exception as original:
        try:
            if installed:
                stop_installed(target)
                shutil.move(str(target), str(backup / 'Magpie.failed'))
            if displaced:
                os.replace(previous, target)
                run('/usr/bin/open', str(target))
        except Exception as rollback_error:
            raise RuntimeError(f'Installation and rollback failed. Original bundle is at {previous}; backup at {backup}.') from rollback_error
        raise original
    finally:
        if staged.exists():
            shutil.rmtree(staged)
    if previous.exists():
        # A verified ZIP remains. Retain the previous app as an extra recovery
        # copy; no user data is removed by the installer.
        shutil.move(str(previous), str(backup / 'Magpie.previous'))
    return backup


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path)
    parser.add_argument('--local-build', action='store_true', help='Developer-only: allow an explicitly trusted local/ad-hoc build')
    parser.add_argument('--team-id', help='Expected 10-character Developer ID team, from the verified release instructions')
    args = parser.parse_args()
    os.umask(0o077)
    backup = install(args.source, local_build=args.local_build, team_id=args.team_id)
    print(f'Installed {TARGET}. Application backup/recovery directory: {backup}')


if __name__ == '__main__':
    try:
        main()
    except (subprocess.CalledProcessError, RuntimeError, OSError, ValueError) as error:
        raise SystemExit(str(error))
