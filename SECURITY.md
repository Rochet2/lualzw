# Security Policy

## Using lualzw safely

lualzw is a **compression codec**, not encryption or authentication. Treat all compressed input from networks as hostile.

### Required for untrusted input

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
| Output size | `max_output_size` | Decompression bombs ( huge expanded output ) |
| Input size | `max_input_size` | Large compressed blobs ( memory / bandwidth ) |
| Dictionary steps | `max_codes` | CPU exhaustion during decode |

Also bound `compress` on public endpoints:

```lua
local compressed, err = lualzw.compress(plaintext, MAX)
```

### Recommended for client–server IO

Use the network preset so dictionary codes never contain `\0`:

```lua
local lualzw = require("lualzw").network()
```

Both peers must use the same `skip`, `uncompressed`, and `compressed` settings.

### Configuration mismatches

Skip settings and control prefixes are not embedded in the payload. Compressor and decompressor must use matching `configure()` options.

## Known limitations

- The library operates on Lua byte strings, not Unicode code points (see README).
