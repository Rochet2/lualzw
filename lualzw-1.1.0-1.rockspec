package = "lualzw"
version = "1.1.0-1"

source = {
    url = "git+https://github.com/Rochet2/lualzw.git",
    tag = "v1.1.0",
}

description = {
    summary = "A relatively fast LZW compression algorithm in pure Lua",
    detailed = [[
Lossless LZW compression for Lua strings with runtime configuration,
optional size limits for safe network use, and wire format v2 for
self-describing payloads. Compatible with Lua 5.1 and later.
    ]],
    homepage = "https://github.com/Rochet2/lualzw",
    license = "MIT",
}

dependencies = {
    "lua >= 5.1",
}

build = {
    type = "builtin",
    modules = {
        lualzw = "lualzw.lua",
    },
}
