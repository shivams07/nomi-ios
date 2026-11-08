#!/usr/bin/env python3
"""Copy a Swift file with every #Preview invocation removed.

Usage: python3 -I scripts/strip_previews.py <in.swift> <out.swift>

Each code-level `#Preview` token is removed together with its trailing
closure, from the token through the brace that closes the closure. Text
inside string literals and comments is never treated as code, so a
`#Preview` mentioned in a comment is kept and braces inside strings do not
change the count. All other text is copied byte for byte.

Exits 1 with a message (file and line) if a preview or string cannot be
matched, so the harness fails loudly rather than compiling a broken copy.
"""
import re
import sys

PREVIEW = re.compile(r'#Preview(?![A-Za-z0-9_])')


class ScanError(Exception):
    def __init__(self, message, offset):
        Exception.__init__(self, message)
        self.offset = offset


def scan_code(src, i, code, interp=False):
    """Mark code characters in `code` from index i onward.

    Returns the index after the run: the end of input, or, when `interp` is
    True (inside a string interpolation), the index just past the ')' that
    closes the interpolation.
    """
    n = len(src)
    depth = 0
    while i < n:
        if src.startswith('//', i):
            j = src.find('\n', i)
            i = n if j == -1 else j
            continue
        if src.startswith('/*', i):
            level = 1
            j = i + 2
            while j < n and level:
                if src.startswith('/*', j):
                    level += 1
                    j += 2
                elif src.startswith('*/', j):
                    level -= 1
                    j += 2
                else:
                    j += 1
            if level:
                raise ScanError('unterminated block comment', i)
            i = j
            continue
        c = src[i]
        if c == '#' or c == '"':
            h = 0
            j = i
            while j < n and src[j] == '#':
                h += 1
                j += 1
            if j < n and src[j] == '"':
                i = scan_string(src, j, h, code)
                continue
        if interp:
            if c == '(':
                depth += 1
            elif c == ')':
                if depth == 0:
                    return i + 1
                depth -= 1
        code[i] = True
        i += 1
    if interp:
        raise ScanError('unterminated string interpolation', i)
    return i


def scan_string(src, j, h, code):
    """Skip a string literal whose opening quote is at j.

    `h` is the number of '#' that open a raw string (0 for a plain string).
    Returns the index just past the closing delimiter.
    """
    n = len(src)
    multiline = src.startswith('"""', j)
    quote = '"""' if multiline else '"'
    close = quote + '#' * h
    esc = '\\' + '#' * h
    k = j + len(quote)
    while k < n:
        if src.startswith(esc + '(', k):
            k = scan_code(src, k + len(esc) + 1, code, interp=True)
            continue
        if src.startswith(esc, k):
            k += len(esc) + 1
            continue
        if src.startswith(close, k):
            return k + len(close)
        if not multiline and src[k] == '\n':
            break
        k += 1
    raise ScanError('unterminated string literal', j)


def strip(src):
    """Return (text with #Preview invocations removed, number removed)."""
    n = len(src)
    code = [False] * n
    scan_code(src, 0, code)
    ranges = []
    for m in PREVIEW.finditer(src):
        start = m.start()
        if not code[start]:
            continue
        k = m.end()
        while k < n and not (src[k] == '{' and code[k]):
            k += 1
        if k >= n:
            raise ScanError('#Preview has no closure', start)
        depth = 0
        end = None
        while k < n:
            if code[k]:
                if src[k] == '{':
                    depth += 1
                elif src[k] == '}':
                    depth -= 1
                    if depth == 0:
                        end = k + 1
                        break
            k += 1
        if end is None:
            raise ScanError('#Preview closure is never closed', start)
        ranges.append((start, end))
    pieces = []
    pos = 0
    for start, end in ranges:
        pieces.append(src[pos:start])
        pos = end
    pieces.append(src[pos:])
    return ''.join(pieces), len(ranges)


def main(argv):
    if len(argv) != 3:
        sys.stderr.write('usage: strip_previews.py <in.swift> <out.swift>\n')
        return 2
    src_path, dst_path = argv[1], argv[2]
    with open(src_path, 'r', encoding='utf-8', newline='') as f:
        src = f.read()
    try:
        out, _ = strip(src)
    except ScanError as e:
        line = src.count('\n', 0, e.offset) + 1
        sys.stderr.write('strip_previews: %s:%d: %s\n' % (src_path, line, e))
        return 1
    with open(dst_path, 'w', encoding='utf-8', newline='') as f:
        f.write(out)
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
