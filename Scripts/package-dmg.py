#!/usr/bin/env python3
"""Package an already Developer ID-signed, notarized and stapled Magpie.app.

Requires macOS tools and Python 3. Produces a local DMG and SHA-256 sidecar without
signing, submitting to Apple, installing, mounting, overwriting or publishing anything.
The new DMG container is not itself signed/notarized by this script.
"""
import argparse
import hashlib
import importlib.util
import os
from pathlib import Path
import re
import subprocess
import tempfile


def load_installer():
    path = Path(__file__).resolve().with_name('install-app.py')
    spec = importlib.util.spec_from_file_location('magpie_installer_for_packaging', path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


installer = load_installer()


def run(*args):
    return subprocess.run(args, check=True, text=True, capture_output=True)


def verify_app(app, team_id):
    actual_team = installer.verify(app, local_build=False, expected_team=team_id)
    if actual_team != team_id:
        raise RuntimeError('The application does not match the expected Developer ID team.')
    run('/usr/bin/xcrun', 'stapler', 'validate', str(app))


def exists(path):
    # Dangling symlinks also reserve a destination; never follow or overwrite one.
    return path.exists() or path.is_symlink()


def sha256(path):
    digest = hashlib.sha256()
    with path.open('rb') as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b''):
            digest.update(chunk)
    return digest.hexdigest()


def package(source, output, team_id):
    source = Path(source).absolute()
    output = Path(output).absolute()
    checksum_output = output.with_name(output.name + '.sha256')
    if not re.fullmatch(r'[A-Z0-9]{10}', team_id or ''):
        raise ValueError('Provide the independently verified 10-character Developer ID team.')
    if output.suffix.lower() != '.dmg' or any(c in output.name for c in '\r\n\\'):
        raise ValueError('Output must be a .dmg filename without line breaks or backslashes.')
    if source.resolve() in output.resolve().parents:
        raise ValueError('Do not write packaging output inside the application bundle.')
    if exists(output) or exists(checksum_output):
        raise FileExistsError('The DMG or its checksum already exists; choose a new output name.')
    verify_app(source, team_id)
    output.parent.mkdir(parents=True, exist_ok=True)

    # Keep staging on the output filesystem: hard links below are both atomic and
    # no-clobber, unlike a preflight existence check followed by os.replace().
    with tempfile.TemporaryDirectory(prefix='.magpie-package-', dir=output.parent) as temporary:
        work = Path(temporary)
        contents = work / 'contents'
        contents.mkdir()
        staged_app = contents / 'Magpie.app'
        run('/usr/bin/ditto', str(source), str(staged_app))
        verify_app(staged_app, team_id)
        (contents / 'Applications').symlink_to('/Applications', target_is_directory=True)
        image = work / 'Magpie.dmg'
        run('/usr/bin/hdiutil', 'create', '-volname', 'Magpie', '-srcfolder', str(contents),
            '-fs', 'HFS+', '-format', 'UDZO', str(image))
        if image.is_symlink() or not image.is_file():
            raise RuntimeError('The disk-image tool did not create a regular DMG file.')
        run('/usr/bin/hdiutil', 'verify', str(image))
        digest = sha256(image)
        checksum = work / 'Magpie.dmg.sha256'
        with checksum.open('x', encoding='utf-8', newline='\n') as handle:
            handle.write(f'{digest}  {output.name}\n')
            handle.flush()
            os.fsync(handle.fileno())
        # Distribution artifacts are readable; the private temporary directory
        # still prevents access until the final links are created.
        image.chmod(0o644)
        checksum.chmod(0o644)
        with image.open('r+b') as handle:
            os.fsync(handle.fileno())

        # A pair of filesystem entries cannot be published as one atomic rename.
        # Publish the checksum first and the complete DMG last. On ordinary
        # failure, remove only our own checksum, never another writer's file.
        # A process/power interruption may leave a checksum without a DMG;
        # rerunning still refuses to overwrite it.
        checksum_published = False
        try:
            os.link(checksum, checksum_output, follow_symlinks=False)
            checksum_published = True
            os.link(image, output, follow_symlinks=False)
        except OSError:
            if checksum_published and not checksum_output.is_symlink():
                try:
                    if checksum_output.samefile(checksum):
                        checksum_output.unlink()
                except FileNotFoundError:
                    pass
            raise
    return output, checksum_output, digest


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path, help='Already signed, notarized and stapled Magpie.app')
    parser.add_argument('output', type=Path, help='New .dmg path; an existing DMG/checksum is rejected')
    parser.add_argument('--team-id', required=True, help='Independently verified Developer ID team')
    args = parser.parse_args()
    os.umask(0o077)
    image, checksum, digest = package(args.source, args.output, args.team_id)
    print(f'Created local packaging artifact: {image}')
    print(f'SHA-256: {digest}\nChecksum file: {checksum}')
    print('The DMG container has not been signed, notarized or published by this script.')


if __name__ == '__main__':
    try:
        main()
    except (subprocess.CalledProcessError, RuntimeError, OSError, ValueError) as error:
        raise SystemExit(str(error))
