-- Unit test for lua-placeholders-namespace.parse_filename.
--
-- Run from the package root:
--     lua test/unit/parse-filename.lua
-- or via the Makefile:
--     make test-parse-filename
--
-- parse_filename's job is to derive a namespace name from a path.
-- An earlier regex picked the wrong segment for paths whose parent
-- directory contained a dot (e.g. ~/texmf.d/grapefruit/klant.yaml
-- resolved to 'texmf').  This test pins down the behaviour against a
-- variety of path shapes so a regression cannot slip back in.

-- Run-from-package-root or run-from-its-own-directory both work.
package.path = './scripts/?.lua;../../scripts/?.lua;' .. package.path

local namespace = require('lua-placeholders-namespace')

local cases = {
    { input    = '/home/harrie/texmf.d/grapefruit-inc/klant.yaml',
      expected = 'klant',
      note     = 'dotted parent directory must not consume the basename' },
    { input    = '/home/harrie/texmf.d/grapefruit-inc/bedrijf.yaml',
      expected = 'bedrijf' },
    { input    = '/usr/local/texlive/2026/texmf-dist/tex/lualatex/lp/example.yaml',
      expected = 'example' },
    { input    = 'klant.yaml',
      expected = 'klant',
      note     = 'bare filename, no directory component' },
    { input    = './klant.yaml',
      expected = 'klant' },
    { input    = 'grapefruit-inc/klant.yaml',
      expected = 'klant',
      note     = 'relative path with hyphenated directory' },
    { input    = 'klant-spec.yaml',
      expected = 'klant-spec',
      note     = 'hyphen in basename must be kept' },
    { input    = 'C:/Users/harrie/texmf/klant.yaml',
      expected = 'klant',
      note     = 'Windows path using forward slashes (kpse-normalised form)' },
    { input    = '/abs/path/multi.dot.name.yaml',
      expected = 'multi.dot.name',
      note     = 'multiple dots in basename: only the last is the extension' },
}

local pass, fail = 0, 0
for _, c in ipairs(cases) do
    local name = namespace.parse_filename(c.input)
    if name == c.expected then
        pass = pass + 1
        print(string.format('ok    %s', c.input))
    else
        fail = fail + 1
        local label = c.note and (' (' .. c.note .. ')') or ''
        print(string.format('FAIL  %s%s', c.input, label))
        print(string.format('      expected %q, got %q', c.expected, tostring(name)))
    end
end

print(string.format('\n%d/%d passing', pass, pass + fail))
os.exit(fail == 0 and 0 or 1)