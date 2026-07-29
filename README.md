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

## Install

Copy [`lualzw.lua`](lualzw.lua) onto your `package.path`, or after the `v1.1.0` tag is published:

```sh
luarocks install lualzw
```

## Configuration

Create a custom codec with `configure()`. The default module (`require("lualzw")`) uses `skip = {}` and control prefixes `u` / `c`.

```lua
local lualzw = require("lualzw")

-- Default: original encoding (may embed \0 in dictionary codes)
local legacy = lualzw.configure({ skip = {} })

-- Preferred for null-free input when compressed codes must avoid \0
local nullsafe = lualzw.configure({ skip = { [0] = true } })
```

### Skipping null bytes in codes

The default skip list `{}` matches the original on-the-wire encoding. Dictionary codes are 16-bit byte pairs and **may include `\0`**. That is fine for plain Lua strings, but problematic when compressed data passes through:

- C APIs or bindings that treat `\0` as end-of-string
- Null-terminated storage or logging
- Tools that truncate at the first null

Use `{ skip = { [0] = true } }` so dictionary codes never use `0` as their **second** byte. For **null-free input**, compressed output then contains no `\0`. If the input itself contains null bytes (or compression falls back to passthrough of such input), `\0` can still appear as the first byte of a base code (`char(0, …)`). Both compressor and decompressor need the same `skip` setting; it is not stored in the payload.

Custom control prefixes (both peers must match):

```lua
local custom = lualzw.configure({
    skip = { [0] = true },
    uncompressed = "p",
    compressed = "q",
})
```

See [`configure(options)`](#configureoptions) for full option details.

## Untrusted input

lualzw is a **compression codec**, not encryption or authentication. Treat compressed data from untrusted sources as hostile.

Always call `decompress` with explicit limits:

```lua
local MAX = 64 * 1024
local data, err = lualzw.decompress(payload, MAX, MAX * 2, MAX * 4)
if not data then
    -- reject message
end
```

| Limit | Parameter | Protects against |
| ----- | --------- | ---------------- |
| Output size | `max_output_size` | Decompression bombs (huge expanded output) |
| Input size | `max_input_size` | Large compressed blobs (memory / bandwidth) |
| Dictionary steps | `max_codes` | CPU exhaustion during decode |

Bound `compress` on public endpoints as well:

```lua
local compressed, err = lualzw.compress(plaintext, MAX)
```

## API

Load the module:

```lua
local lualzw = require("lualzw")
print(lualzw._VERSION) -- "1.1.0"
```

Each codec table (default, or from `configure()`) exports:

| Member | Description |
| ------ | ----------- |
| `compress(input[, max_input_size])` | Compress a string |
| `decompress(input[, max_output_size[, max_input_size[, max_codes]]])` | Decompress or passthrough |
| `configure(options)` | Create a new codec; see [`configure(options)`](#configureoptions) |
| `_VERSION` | Semantic version string |
| `uncompressed` | Passthrough prefix byte for this codec |
| `compressed` | Compressed prefix byte for this codec |

### `configure(options)`

Returns a **new codec table** with the same methods as the default module, using the given options. Options are fixed for the lifetime of that codec; they are not stored in compressed output, so both peers must use matching settings.

**Parameters**

| Name | Type | Default | Description |
| ---- | ---- | ------- | ----------- |
| `options` | `table` | `{}` | Configuration (all keys optional) |
| `options.skip` | `table` | `{}` | Byte values that must not appear in dictionary codes (see below) |
| `options.uncompressed` | `string` | `"u"` | One-byte prefix for passthrough output |
| `options.compressed` | `string` | `"c"` | One-byte prefix for LZW output |

**Returns**

A codec table with `compress`, `decompress`, `configure`, `_VERSION`, `uncompressed`, and `compressed`.

**`options.skip`**

Dictionary codes are 16-bit byte pairs. Skipped bytes never appear in those pairs (useful to keep compressed data free of `\0`, etc.).

Two table forms are accepted:

```lua
-- Map form
{ [0] = true, [1] = true }

-- List form (byte values as array entries)
{ 0, 1 }
```

Each skipped byte slightly reduces available dictionary codes. If too many bytes are skipped, `configure()` raises:

```
invalid configuration, no character can be used in compression
```

**`options.uncompressed` / `options.compressed`**

- Each must be a string of **exactly one byte**.
- They must be **different** from each other.
- Invalid values raise `invalid uncompressed control character`, `invalid compressed control character`, or `uncompressed and compressed control characters must differ`.

Changing skip or control settings produces incompatible compressed data. Default `{}` skip matches the original master encoding.

```lua
local codec = lualzw.configure({
    skip = { [0] = true },
    uncompressed = "u",
    compressed = "c",
})
print(codec.uncompressed, codec.compressed) -- u    c
```

### `compress(input[, max_input_size])`

**Returns:** compressed string, or `nil, error`.

- Non-string input → `nil, "string expected, got <type>"`
- Bad limit type → `nil, "number expected for max_input_size, got <type>"`
- Invalid limit (negative, NaN, infinity) → `nil, "invalid max_input_size"`
- Input longer than `max_input_size` → `nil, "input exceeds limit"`
- Input of 0–1 bytes → passthrough (`u` prefix; see wire format)
- Longer input → LZW compress if strictly smaller than input, otherwise passthrough
- Internal failure → `nil, "algorithm error, could not fetch word"`

### `decompress(input[, max_output_size[, max_input_size[, max_codes]]])`

**Returns:** original string, or `nil, error`.

Always pass limits when decoding **untrusted** data (see [Untrusted input](#untrusted-input)).

- Non-string input → `nil, "string expected, got <type>"`
- Invalid limit types → `nil, "number expected for <name>, got <type>"`
- Invalid limits (negative, NaN, infinity) → `nil, "invalid <name>"`
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

Each case runs the default and null-safe (`skip = { [0] = true }`) codecs. LibCompress is compared when installed.

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
| `compress` | Bad limit type | `"number expected for max_input_size, got <type>"` |
| `compress` | Invalid limit | `"invalid max_input_size"` |
| `compress` | Input too large | `"input exceeds limit"` |
| `compress` | Internal | `"algorithm error, could not fetch word"` |
| `decompress` | Wrong type | `"string expected, got <type>"` |
| `decompress` | Bad limit type | `"number expected for <name>, got <type>"` |
| `decompress` | Invalid limit | `"invalid <name>"` |
| `decompress` | Empty / invalid | `"invalid input - not a compressed string"` |
| `decompress` | Corrupt codes | `"could not find last from dict. Invalid input?"` |
| `decompress` | Output limit | `"decompressed output exceeds limit"` |
| `decompress` | Input limit | `"compressed input exceeds limit"` |
| `decompress` | Step limit | `"decompression step limit exceeded"` |
| `configure` | Bad control byte | `"invalid uncompressed control character"` / `"invalid compressed control character"` |
| `configure` | Matching controls | `"uncompressed and compressed control characters must differ"` |
| `configure` | Skip too aggressive | `"invalid configuration, no character can be used in compression"` |
