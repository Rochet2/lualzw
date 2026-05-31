# lualzw
A relatively fast LZW compression algorithm in pure lua

# encoding and decoding
Lossless compression for any text. The more repetition in the text, the better.

16 bit encoding is used. So each 8 bit character is encoded as 16 bit.
This means that the dictionary size is 65280.

Any special characters like `äöå` that are represented with multiple characters are supported. The special characters are split up into single characters that are then encoded and decoded. 

While compressing, the algorithm checks if the result size gets over the input. If it does, then the input is not compressed and the algorithm returns the input prematurely as the compressed result (see [Wire format](#wire-format)).

## Skipped bytes in compressed output

Dictionary codes are 16-bit pairs of bytes. By default, those code bytes may include `\0` (null). That matches the original encoding and gives the smallest dictionary overhead, but compressed strings can be truncated by null-terminated APIs (C strings, some database bindings, etc.).

You can exclude specific byte values from appearing anywhere in compressed output by editing the `skippedcharacters` table near the top of `lualzw.lua`. Compressor and decompressor must use the same setting.

### Skipping null bytes (`\0`)

To ensure compressed output never contains embedded null bytes, set:

```lua
local skippedcharacters = {
    [0] = true,
}
```

Both ends of your pipeline must use this configuration before compressing or decompressing. Data compressed with the default `{}` setting cannot be decoded correctly after you enable null skipping, and vice versa.

Null bytes that were already in the **input** string are still preserved when you decompress. Avoid nulls in input unless you control both ends.

### Other configurations

Default (original encoding):

```lua
local skippedcharacters = {
}
```

Skip multiple code bytes (neither `\0` nor `\1` will appear in codes):

```lua
local skippedcharacters = {
    [0] = true,
    [1] = true,
}
```

| Configuration | Effect |
|---------------|--------|
| `{}` (default) | Original encoding; codes may contain `\0` |
| `{ [0] = true }` | No `\0` in compressed output |
| `{ [0] = true, [1] = true }` | No `\0` or `\1` in compressed output |

Each skipped byte slightly reduces the number of available dictionary codes.

## API

Load the module:

```lua
local lualzw = require("lualzw")
```

The module returns a table with two functions: `compress` and `decompress`.

### `lualzw.compress(input)`

Compresses a string using LZW.

**Parameters**

| Name | Type | Description |
|------|------|-------------|
| `input` | `string` | Data to compress |

**Returns**

On success, returns the compressed string (one value).

On failure, returns `nil` and an error message (two values).

**Behavior**

- Input must be a string. Otherwise returns `nil, "string expected, got <type>"`.
- Input of 0 or 1 byte is never LZW-compressed; returns `"u" .. input` (see [Wire format](#wire-format)).
- For longer input, compresses with LZW. If the compressed size would not be smaller than the input, returns `"u" .. input` instead (not an error).
- On rare internal failure: `nil, "algorithm error, could not fetch word"`.

```lua
local compressed, err = lualzw.compress("hello hello hello")
if not compressed then
    error(err)
end
```

### `lualzw.decompress(input[, max_output_size])`

Decompresses a string previously produced by `compress`, or returns passthrough data unchanged.

**Parameters**

| Name | Type | Description |
|------|------|-------------|
| `input` | `string` | Compressed or passthrough string |
| `max_output_size` | `number` (optional) | Maximum allowed decompressed length in bytes |

**Returns**

On success, returns the original string (one value).

On failure, returns `nil` and an error message (two values).

**Behavior**

- Input must be a string. Otherwise returns `nil, "string expected, got <type>"`.
- If `max_output_size` is provided, it must be a non-negative number.
- Empty string: `nil, "invalid input - not a compressed string"`.
- Strings starting with `u`: returns everything after the prefix (passthrough from `compress`).
- Strings starting with `c`: LZW-decompresses the remainder.
- Any other prefix, truncated compressed data, or corrupt codes: `nil` and an error message.
- If decompressed output would exceed `max_output_size`: `nil, "decompressed output exceeds limit"`.

```lua
local original, err = lualzw.decompress(compressed, 1024 * 1024)
if not original then
    error(err)
end
```

### Wire format

Every value returned by `compress` starts with a one-byte prefix:

| Prefix | Meaning | Body |
|--------|---------|------|
| `u` | Uncompressed passthrough | Original input bytes |
| `c` | LZW compressed | Pairs of code bytes (16-bit codes) |

Examples:

| Input to `compress` | Output |
|---------------------|--------|
| `""` | `"u"` |
| `"a"` | `"ua"` |
| Long repetitive text | `"c" .. <code pairs>` (if smaller than input) |
| Incompressible data | `"u" .. input` |

`decompress` accepts any string in this format and round-trips with `compress`:

```lua
assert(lualzw.decompress(lualzw.compress(input)) == input)
```

### Configuration

There is no runtime options table. Edit `skippedcharacters` at the top of `lualzw.lua` before loading the module (see [Skipped bytes](#skipped-bytes-in-compressed-output)). Both `compress` and `decompress` use the same setting.

If too many bytes are marked as skipped, the module fails at load time with:

```
invalid configuration, no character can be used in compression
```

### Error messages

| Function | Condition | Second return value |
|----------|-----------|---------------------|
| `compress` | Wrong argument type | `"string expected, got <type>"` |
| `compress` | Internal error | `"algorithm error, could not fetch word"` |
| `decompress` | Wrong argument type | `"string expected, got <type>"` |
| `decompress` | Invalid `max_output_size` type | `"number expected for max_output_size, got <type>"` |
| `decompress` | Empty input | `"invalid input - not a compressed string"` |
| `decompress` | Missing or wrong prefix | `"invalid input - not a compressed string"` |
| `decompress` | Corrupt compressed body | `"could not find last from dict. Invalid input?"` |
| `decompress` | Output exceeds `max_output_size` | `"decompressed output exceeds limit"` |

Use multiple assignment to detect errors:

```lua
local result, err = lualzw.compress(data)
if not result then
    -- handle err
end
```

## Usage
```lua
local lualzw = require("lualzw")

local input = "foofoofoofoofoofoofoofoofoo"
local compressed = assert(lualzw.compress(input))
local decompressed = assert(lualzw.decompress(compressed))
assert(input == decompressed)
```

## Tests

From the repository root (requires Lua 5.1 or later):

```sh
lua spec/test.lua
```

Install via LuaRocks for local development:

```sh
luarocks make lualzw-dev-1.rockspec
```

CI runs the same test suite on Lua 5.1–5.4 and LuaJIT.

## Speed

Times are in seconds. Both algorithms use the same generated input. Values are an average of 10 runs from `profiling.lua`.

### Reproducing benchmarks

`profiling.lua` compares lualzw to [LibCompress](https://www.curseforge.com/wow/addons/libcompress) (the WoW addon library used in the original benchmarks). LibCompress is not bundled with this repo.

1. Install Lua 5.1 or later.
2. Clone this repository and [LibCompress](https://www.curseforge.com/wow/addons/libcompress/files) (or copy `LibCompress.lua` onto your path).
3. Set `LUA_PATH` so both libraries can be required. Example on Unix:

```sh
export LUA_PATH="./?.lua;/path/to/LibCompress/?.lua;;"
lua profiling.lua
```

On Windows (PowerShell):

```powershell
$env:LUA_PATH = ".\\?.lua;C:\\path\\to\\LibCompress\\?.lua;;"
lua profiling.lua
```

Each block of output prints: input size, compressed size, decompressed size, round-trip OK, then average compress time, average decompress time, and compressed size as a percentage of input.

Note that compressing random generated inputs results usually in bigger result than original. In these cases the algorithms do not compress and return input instead and thus compression result is 100% of input.

lualzw is at an advantage in cases where compression cannot be done as it stops prematurely and LibCompress does not.
Also lualzw is at an advantage in cases where compression can be done as it has a larger dictionary in use.

Input: 1000000 random generated bytes converted into string

algorithm|compress|decompress|result % of input
---------|--------|----------|-------------
lualzw|0.6622|0.0003|100
LibCompress|2.1983|0.0024|100

Input: 1000000 random generated bytes in ASCII range converted into string

algorithm|compress|decompress|result % of input
---------|--------|----------|-------------
lualzw|0.812|0.0022|100
LibCompress|1.782|0.0007|100

Input: 1000000 random generated repeating bytes converted into string

algorithm|compress|decompress|result % of input
---------|--------|----------|-------------
lualzw|0.3975|0.0262|4.5001
LibCompress|0.3907|0.0264|6.6997

Input: 1000000 of same character

algorithm|compress|decompress|result % of input
---------|--------|----------|-------------
lualzw|0.7045|0.0026|0.2829
LibCompress|0.6418|0.0038|0.4241

Input: "ymn32h8hm8ekrwjkrn9f" repeated 50000 times. In total 1000000 bytes

algorithm|compress|decompress|result % of input
---------|--------|----------|-------------
lualzw|0.4788|0.0088|1.2629
LibCompress|0.4426|0.0093|1.8905
