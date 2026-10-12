#!/usr/bin/env python3
"""Install a verified Magpie build with a local backup and rollback on launch failure."""
import argparse
from datetime import datetime
import hashlib
import json
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


def run(*args):
    return subprocess.run(args, check=True, text=True, capture_output=True)


def processes():
    result = subprocess.run(['/usr/bin/pgrep', '-x', 'Magpie'], text=True, capture_output=True)
    if result.returncode not in (0, 1):
        raise RuntimeError(result.stderr)
    entries = []
    for pid in result.stdout.split():
        detail = subprocess.run(['/bin/ps', '-p', pid, '-o', 'comm='], text=True, capture_output=True)
        if detail.returncode == 0:
            entries.append((int(pid), detail.stdout.strip()))
    return entries


def stop_installed():
    executable = str(TARGET / 'Contents/MacOS/Magpie')
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


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path)
    parser.add_argument('--migrate-screen-permission', action='store_true',
                        help='One-time reset of only Magpie ScreenCapture after a signing identity migration')
    args = parser.parse_args()
    source = args.source.resolve()
    state = json.loads((SUPPORT / 'Signing/identity.json').read_text())
    if state.get('name') != 'Magpie Local Development' or not re.fullmatch(r'[A-F0-9]{40}', state.get('sha1', '')):
        raise RuntimeError('Invalid local signing identity metadata.')
    requirement = f'=identifier "com.sanwan.magpie" and certificate leaf = H"{state["sha1"]}"'
    for app in (source, TARGET):
        if not app.is_dir() or app.is_symlink():
            raise RuntimeError(f'Expected app directory: {app}')
        with (app / 'Contents/Info.plist').open('rb') as handle:
            if plistlib.load(handle).get('CFBundleIdentifier') != 'com.sanwan.magpie':
                raise RuntimeError(f'Unexpected bundle: {app}')
    run('/usr/bin/codesign', '--verify', '--deep', '--strict', '-R', requirement, str(source))
    previous_matches = subprocess.run(['/usr/bin/codesign', '--verify', '-R', requirement, str(TARGET)],
                                      capture_output=True).returncode == 0
    backup = SUPPORT / 'Backups' / (datetime.now().strftime('%Y%m%d-%H%M%S') + '-' + uuid.uuid4().hex[:6])
    backup.mkdir(parents=True, mode=0o700)
    archive = backup / 'Magpie.zip'
    run('/usr/bin/ditto', '-c', '-k', '--sequesterRsrc', '--keepParent', str(TARGET), str(archive))
    run('/usr/bin/unzip', '-tq', str(archive))
    staged = TARGET.parent / ('.Magpie-staging-' + uuid.uuid4().hex)
    run('/usr/bin/ditto', str(source), str(staged))
    run('/usr/bin/codesign', '--verify', '--deep', '--strict', '-R', requirement, str(staged))
    stop_installed()
    previous = backup / 'Magpie.previous'
    shutil.move(str(TARGET), str(previous))
    reset = False
    try:
        os.replace(staged, TARGET)
        run('/usr/bin/codesign', '--verify', '--deep', '--strict', '-R', requirement, str(TARGET))
        if args.migrate_screen_permission and not previous_matches:
            run('/usr/bin/tccutil', 'reset', 'ScreenCapture', 'com.sanwan.magpie')
            reset = True
        run('/usr/bin/open', str(TARGET))
        deadline = time.monotonic() + 10
        executable = str(TARGET / 'Contents/MacOS/Magpie')
        while time.monotonic() < deadline:
            running = processes()
            if len(running) == 1 and running[0][1] == executable:
                time.sleep(1)
                if processes() == running:
                    break
            time.sleep(0.25)
        else:
            raise RuntimeError('Could not verify the installed process.')
    except Exception:
        stop_installed()
        if TARGET.exists():
            shutil.move(str(TARGET), str(backup / 'Magpie.failed'))
        shutil.move(str(previous), str(TARGET))
        run('/usr/bin/open', str(TARGET))
        raise
    report = {
        'installed': str(TARGET), 'pid': running[0][0], 'backup': str(archive),
        'signing_sha1': state['sha1'], 'screen_permission_migrated': reset,
        'sha256': hashlib.sha256((TARGET / 'Contents/MacOS/Magpie').read_bytes()).hexdigest(),
        'installed_at': datetime.now().astimezone().isoformat()
    }
    (SUPPORT / 'last-install.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report, indent=2))


if __name__ == '__main__':
    try:
        main()
    except subprocess.CalledProcessError as error:
        raise SystemExit((error.stderr or error.stdout or str(error)).strip())
    except (RuntimeError, ValueError, KeyError) as error:
        raise SystemExit(str(error))
