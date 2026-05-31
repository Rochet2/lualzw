# lualzw

A relatively fast LZW compression algorithm in pure Lua.

## Overview

Lossless compression for byte strings. The more repetition in the data, the better the ratio.

The library uses 16-bit dictionary codes (two bytes per code). The maximum dictionary size per level is 65280 codes.

Input is processed as a sequence of **bytes** (Lua `string` semantics). UTF-8 text round-trips correctly because multibyte sequences are compressed as individual bytes, not as Unicode code points.

While compressing, the algorithm checks whether the result would be strictly smaller than the input. If not, it returns an uncompressed passthrough instead (see [Wire format](#wire-format)).

## Quick start

```lua
local lualzw = require("lualzw")

local input = "foofoofoofoofoofoofoofoofoo"
local compressed = assert(lualzw.compress(input))
local decompressed = assert(lualzw.decompress(compressed))
assert(input == decompressed)
```

## Client–server use

For network IO, **always bound decompression** and prefer the network preset:

```lua
local lualzw = require("lualzw").network()
local MAX = 64 * 1024

-- receive exactly `len` bytes from your framing layer, then:
local data, err = lualzw.decompress(payload, MAX, len, MAX * 4)
if not data then
    error(err)
end
```

See [SECURITY.md](SECURITY.md) for limit guidance.

### `lualzw.network()`

Returns a codec configured for IO with `{ skip = { [0] = true } }` so dictionary codes never contain `\0`.

Both peers must use the same `configure()` / `network()` settings (skip list and control characters).

## Configuration

```lua
local lualzw = require("lualzw")

-- Original encoding (default): may embed \0 in codes
local legacy = lualzw.configure({ skip = {} })

-- Null-safe codes
local nullsafe = lualzw.configure({ skip = { [0] = true } })

-- Custom wire prefixes (both peers must match)
local custom = lualzw.configure({
    skip = { [0] = true },
    uncompressed = "p",
    compressed = "q",
})
```

| Option | Default | Description |
| ------ | ------- | ----------- |
| `skip` | `{}` | Byte values `0`–`255` that must not appear in dictionary codes |
| `uncompressed` | `"u"` | One-byte prefix for passthrough payloads |
| `compressed` | `"c"` | One-byte prefix for LZW payloads |

`uncompressed` and `compressed` must be different single-byte strings. Each codec exposes the resolved values as `.uncompressed` and `.compressed`.

## API

Load the module:

```lua
local lualzw = require("lualzw")
print(lualzw._VERSION) -- "1.1.0"
```

Each codec table (default, or from `configure()` / `network()`) exports:

| Member | Description |
| ------ | ----------- |
| `compress(input[, max_input_size])` | Compress a string |
| `decompress(input[, max_output_size[, max_input_size[, max_codes]]])` | Decompress or passthrough |
| `configure(options)` | Create a new codec with options |
| `network()` | Shorthand for `{ skip = { [0] = true } }` |
| `_VERSION` | Semantic version string |
| `uncompressed` | Passthrough prefix byte for this codec |
| `compressed` | Compressed prefix byte for this codec |

### `compress(input[, max_input_size])`

**Returns:** compressed string, or `nil, error`.

- Non-string input → `nil, "string expected, got <type>"`
- Input longer than `max_input_size` → `nil, "input exceeds limit"`
- Input of 0–1 bytes → passthrough (`u` prefix; see wire format)
- Longer input → LZW compress if strictly smaller than input, otherwise passthrough
- Internal failure → `nil, "algorithm error, could not fetch word"`

### `decompress(input[, max_output_size[, max_input_size[, max_codes]]])`

**Returns:** original string, or `nil, error`.

Always pass limits when decoding **untrusted** data (see [SECURITY.md](SECURITY.md)).

- Non-string input → `nil, "string expected, got <type>"`
- Invalid limit types → `nil, "number expected for <name>, got <type>"`
- `#input` or body larger than `max_input_size` → `nil, "compressed input exceeds limit"`
- Decompressed size exceeds `max_output_size` → `nil, "decompressed output exceeds limit"`
- Dictionary growth exceeds `max_codes` → `nil, "decompression step limit exceeded"`
- Invalid or corrupt payload → `nil, "invalid input - not a compressed string"` or `"could not find last from dict. Invalid input?"`

## Wire format

Each output starts with a one-byte control prefix configured on the codec (defaults shown):

| Prefix | Meaning | Body |
| ------ | ------- | ---- |
| `u` (default) | Uncompressed passthrough | Original bytes |
| `c` (default) | LZW compressed | Pairs of code bytes |

Examples with default controls:

| Input to `compress` | Output |
| ------------------- | ------ |
| `""` | `"u"` |
| `"a"` | `"ua"` |
| Repetitive data | `"c" .. <code pairs>` if smaller than input |
| Incompressible data | `"u" .. input` |

## Tests

```sh
lua spec/test.lua
```

## Benchmarks

Historical timings below were produced with `benchmark/profiling.lua`, which compares lualzw to [LibCompress](https://www.curseforge.com/wow/addons/libcompress). LibCompress is not bundled with this repo.

From the repository root:

```sh
lua benchmark/profiling.lua
```

Use `--quick` for smaller inputs (10 000 bytes, 3 iterations):

```sh
lua benchmark/profiling.lua --quick
```

Each case runs the default and network codecs. LibCompress is compared when installed.

### Published results

Times are in seconds (average of 10 runs). Random inputs usually bail out to passthrough (100% of input size).

**Input:** 1 000 000 random bytes

| algorithm | compress | decompress | result % |
| --------- | -------- | ---------- | -------- |
| lualzw | 0.6622 | 0.0003 | 100 |
| LibCompress | 2.1983 | 0.0024 | 100 |

**Input:** 1 000 000 random ASCII bytes

| algorithm | compress | decompress | result % |
| --------- | -------- | ---------- | -------- |
| lualzw | 0.812 | 0.0022 | 100 |
| LibCompress | 1.782 | 0.0007 | 100 |

**Input:** 1 000 000 repeating cycling bytes

| algorithm | compress | decompress | result % |
| --------- | -------- | ---------- | -------- |
| lualzw | 0.3975 | 0.0262 | 4.5001 |
| LibCompress | 0.3907 | 0.0264 | 6.6997 |

**Input:** 1 000 000 identical bytes

| algorithm | compress | decompress | result % |
| --------- | -------- | ---------- | -------- |
| lualzw | 0.7045 | 0.0026 | 0.2829 |
| LibCompress | 0.6418 | 0.0038 | 0.4241 |

**Input:** `"ymn32h8hm8ekrwjkrn9f"` × 50 000 (1 000 000 bytes)

| algorithm | compress | decompress | result % |
| --------- | -------- | ---------- | -------- |
| lualzw | 0.4788 | 0.0088 | 1.2629 |
| LibCompress | 0.4426 | 0.0093 | 1.8905 |

## Error reference

| Function | Condition | Error |
| -------- | --------- | ----- |
| `compress` | Wrong type | `"string expected, got <type>"` |
| `compress` | Input too large | `"input exceeds limit"` |
| `compress` | Internal | `"algorithm error, could not fetch word"` |
| `decompress` | Wrong type | `"string expected, got <type>"` |
| `decompress` | Bad limit type | `"number expected for <name>, got <type>"` |
| `decompress` | Empty / invalid | `"invalid input - not a compressed string"` |
| `decompress` | Corrupt codes | `"could not find last from dict. Invalid input?"` |
| `decompress` | Output limit | `"decompressed output exceeds limit"` |
| `decompress` | Input limit | `"compressed input exceeds limit"` |
| `decompress` | Step limit | `"decompression step limit exceeded"` |
