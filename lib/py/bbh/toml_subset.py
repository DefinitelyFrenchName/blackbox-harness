"""toml_subset.py — the harness's config reader: a TOML SUBSET, refusing what
tomllib would read differently.

Lineage: VampireSaved's tools/_minitoml.py (a fallback for Python < 3.11 that
learned, at cost, to REFUSE the constructs on which it and tomllib disagree —
a nested row parsed there as a flat orphan key and never applied, while a
>= 3.11 host would have applied it: the same manifest, different bytes,
GitHub #42 of that project). This reader keeps that stance and adds the
values a harness config needs: literal strings for regexes, arrays (of
scalars, or of arrays of scalars), and inline tables of scalars.

Accepted:
    # comment                       (outside strings)
    [table]                         one level; no dots
    key = "basic string"            no backslash, no inner quote
    key = 'literal string'          anything but a single quote (regexes)
    key = 123 | 0x7f | true | false
    key = [ 'a', "b", 3, [ 'x', 'y' ] ]   may span lines until the bracket closes
    key = { a = 'x', b = 2 }        inline table of scalars, one line

Refused (a hard error, so every host reads one config one way):
    dotted table headers and dotted keys, [[arrays of tables]], duplicate
    keys, signed hex, escapes in basic strings, multi-line strings, nested
    inline tables, arrays of inline tables, datetimes, floats.

selftest/test_config.sh asserts that on a host WITH tomllib the two parsers
agree on every accepted example and that every refused example is refused.
"""
import re


class SubsetError(ValueError):
    pass


_INT = re.compile(r"^[+-]?(0x[0-9A-Fa-f_]+|[0-9_]+)$")
_KEY = re.compile(r"^[A-Za-z0-9_-]+$")


def _strip_comment(line):
    in_basic = in_lit = False
    for i, ch in enumerate(line):
        if ch == '"' and not in_lit:
            in_basic = not in_basic
        elif ch == "'" and not in_basic:
            in_lit = not in_lit
        elif ch == "#" and not in_basic and not in_lit:
            return line[:i]
    return line


class _Scanner:
    def __init__(self, text, lineno):
        self.s = text
        self.i = 0
        self.lineno = lineno

    def err(self, msg):
        raise SubsetError(f"line {self.lineno}: {msg}")

    def ws(self):
        while self.i < len(self.s) and self.s[self.i] in " \t\r\n":
            self.i += 1

    def peek(self):
        self.ws()
        return self.s[self.i] if self.i < len(self.s) else ""

    def value(self, depth=0):
        c = self.peek()
        if c == "":
            self.err("expected a value")
        if c == '"':
            return self.basic()
        if c == "'":
            return self.literal()
        if c == "[":
            if depth >= 2:
                self.err("arrays nest at most twice (an array of arrays of scalars)")
            return self.array(depth)
        if c == "{":
            if depth:
                self.err("an inline table may not sit inside an array")
            return self.inline_table()
        return self.scalar()

    def basic(self):
        j = self.s.find('"', self.i + 1)
        if j < 0:
            self.err("unterminated basic string")
        body = self.s[self.i + 1:j]
        if "\\" in body:
            self.err("escapes in a basic string are refused — use a 'literal string'")
        self.i = j + 1
        return body

    def literal(self):
        j = self.s.find("'", self.i + 1)
        if j < 0:
            self.err("unterminated literal string")
        body = self.s[self.i + 1:j]
        self.i = j + 1
        return body

    def scalar(self):
        j = self.i
        while j < len(self.s) and self.s[j] not in ",]} \t\r\n":
            j += 1
        raw = self.s[self.i:j]
        self.i = j
        if raw in ("true", "false"):
            return raw == "true"
        if raw.startswith(("-0x", "+0x")):
            self.err(f"signed hex is not TOML: {raw}")
        if _INT.match(raw):
            return int(raw.replace("_", ""), 0)
        self.err(f"unsupported value syntax: {raw!r}")

    def array(self, depth):
        self.i += 1
        out = []
        while True:
            c = self.peek()
            if c == "":
                self.err("unterminated array")
            if c == "]":
                self.i += 1
                return out
            out.append(self.value(depth + 1))
            c = self.peek()
            if c == ",":
                self.i += 1
            elif c != "]":
                self.err("expected ',' or ']' in array")

    def inline_table(self):
        self.i += 1
        out = {}
        while True:
            c = self.peek()
            if c == "":
                self.err("unterminated inline table")
            if c == "}":
                self.i += 1
                return out
            j = self.i
            while j < len(self.s) and self.s[j] not in "= \t":
                j += 1
            key = self.s[self.i:j]
            self.i = j
            if not _KEY.match(key) or "." in key:
                self.err(f"bad inline-table key {key!r}")
            if key in out:
                self.err(f"duplicate key {key!r} in inline table")
            if self.peek() != "=":
                self.err("expected '=' in inline table")
            self.i += 1
            c = self.peek()
            if c in "[{":
                self.err("inline tables hold scalars only")
            out[key] = self.value(depth=1)
            c = self.peek()
            if c == ",":
                self.i += 1
            elif c != "}":
                self.err("expected ',' or '}' in inline table")


def _bracket_balance(text):
    depth = 0
    in_basic = in_lit = False
    for ch in text:
        if ch == '"' and not in_lit:
            in_basic = not in_basic
        elif ch == "'" and not in_basic:
            in_lit = not in_lit
        elif not in_basic and not in_lit:
            if ch == "[":
                depth += 1
            elif ch == "]":
                depth -= 1
    return depth


def loads(text):
    root = {}
    current = root
    seen = {id(root): set()}
    lines = text.splitlines()
    n = 0
    while n < len(lines):
        lineno = n + 1
        line = _strip_comment(lines[n]).strip()
        n += 1
        if not line:
            continue
        if line.startswith("[["):
            raise SubsetError(f"line {lineno}: [[arrays of tables]] are refused")
        if line.startswith("["):
            if not line.endswith("]"):
                raise SubsetError(f"line {lineno}: malformed table header")
            name = line[1:-1].strip()
            if "." in name or not _KEY.match(name):
                raise SubsetError(f"line {lineno}: table header [{name}] is refused "
                                  f"(dotted or malformed)")
            if name in root:
                raise SubsetError(f"line {lineno}: table [{name}] declared twice")
            current = root.setdefault(name, {})
            seen[id(current)] = set()
            continue
        if "=" not in line:
            raise SubsetError(f"line {lineno}: expected key = value")
        key, raw = line.split("=", 1)
        key = key.strip()
        if "." in key or not _KEY.match(key):
            raise SubsetError(f"line {lineno}: key {key!r} is refused (dotted or malformed)")
        if key in seen[id(current)]:
            raise SubsetError(f"line {lineno}: duplicate key {key!r}")
        # an array may span lines: gather until the brackets balance
        while _bracket_balance(raw) > 0 and n < len(lines):
            raw += "\n" + _strip_comment(lines[n])
            n += 1
        sc = _Scanner(raw.strip(), lineno)
        val = sc.value()
        if sc.peek() != "":
            sc.err(f"trailing text after value: {sc.s[sc.i:].strip()!r}")
        seen[id(current)].add(key)
        current[key] = val
    return root


def load(path):
    with open(path, encoding="utf-8") as f:
        return loads(f.read())
