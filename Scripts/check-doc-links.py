#!/usr/bin/env python3
"""Validate repository-relative Markdown links/images without network access."""
from pathlib import Path
import re
import subprocess
import sys
from urllib.parse import unquote, urlsplit

ROOT = Path(__file__).resolve().parents[1]


def without_fences(text):
    return re.sub(r'^\s*(`{3,}|~{3,}).*?^\s*\1\s*$', '', text, flags=re.M | re.S)


def anchors(text):
    result, seen = set(), {}
    for line in without_fences(text).splitlines():
        match = re.match(r'^#{1,6}\s+(.+?)\s*#*$', line)
        if not match:
            continue
        title = re.sub(r'<[^>]+>', '', match[1]).lower()
        title = re.sub(r'[^\w\-\s]', '', title)
        slug = re.sub(r'\s', '-', title)
        count = seen.get(slug, 0)
        seen[slug] = count + 1
        result.add(slug if not count else f'{slug}-{count}')
    return result


def check(path):
    source = without_fences(path.read_text())
    targets = re.findall(r'\[[^\]\n]*\]\(([^\s)]+)(?:\s+"[^"]*")?\)', source)
    targets += re.findall(r'(?:src|href)=["\']([^"\']+)["\']', source)
    failures = []
    for target in targets:
        url = urlsplit(target.strip('<>'))
        if url.scheme or url.netloc:
            continue
        destination = (path.parent / unquote(url.path)).resolve() if url.path else path
        if not destination.exists():
            failures.append(f'{path.relative_to(ROOT)}: missing {target}')
        elif url.fragment and destination.suffix.lower() == '.md':
            if unquote(url.fragment) not in anchors(destination.read_text()):
                failures.append(f'{path.relative_to(ROOT)}: missing anchor {target}')
    return failures


def main():
    # Include newly created documentation as well as tracked Markdown.
    result = subprocess.run(['git', 'ls-files', '--cached', '--others', '--exclude-standard', '-z'],
                            cwd=ROOT, check=True, capture_output=True)
    files = {ROOT / p.decode() for p in result.stdout.split(b'\0') if p and p.endswith(b'.md')}
    failures = [failure for path in sorted(files) if path.exists() for failure in check(path)]
    print('\n'.join(failures) if failures else f'Document links: passed ({len(files)} Markdown files; external URLs not fetched)')
    return bool(failures)


if __name__ == '__main__':
    sys.exit(main())
