#!/usr/bin/env python3
"""Conservative source guard for production diagnostic sinks (not taint analysis)."""
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]


def calls(source):
    for match in re.finditer(r'\b(NSLog|print|debugPrint|os_log|fatalError)\s*\(', source):
        start = match.end()
        depth, quoted, escaped = 1, False, False
        for end in range(start, len(source)):
            ch = source[end]
            if quoted:
                if escaped: escaped = False
                elif ch == '\\': escaped = True
                elif ch == '"': quoted = False
            elif ch == '"': quoted = True
            elif ch == '(': depth += 1
            elif ch == ')':
                depth -= 1
                if depth == 0:
                    yield match.group(1), source[start:end], source.count('\n', 0, match.start()) + 1
                    break


def violations(source, allow_safe_adapter=False):
    problems = []
    for sink, args, line in calls(source):
        # This is the only permitted object formatter: the adapter accepts
        # StaticString and an NSError numeric code, never a raw description.
        safe_adapter = args.strip() == '"[%@] failed code=%ld", String(describing: event), (error as NSError).code'
        if allow_safe_adapter and safe_adapter: continue
        if sink in ('print', 'debugPrint', 'os_log') or not args.lstrip().startswith('"'):
            problems.append((line, 'Use fixed NSLog events or DiagnosticLog.failure'))
        elif '\\(' in args or '%@' in args or '%s' in args:
            problems.append((line, 'Content interpolation/string arguments are forbidden'))
        else:
            expressions = re.sub(r'"(?:\\.|[^"\\])*"', '""', args)
            if re.search(r'\b(title|body|snippet|shortcut|payload|path|searchText|error|localizedDescription|userInfo)\b', expressions):
                problems.append((line, 'Potential sensitive value in diagnostic sink'))
    return problems


def main():
    found=[]
    for path in (ROOT/'Sources/Magpie').rglob('*.swift'):
        for line, reason in violations(path.read_text(), path.name == 'SecretDetector.swift'):
            found.append(f'{path.relative_to(ROOT)}:{line}: {reason}')
    print('\n'.join(found) if found else 'Privacy log guard: passed')
    return bool(found)

if __name__ == '__main__': sys.exit(main())
