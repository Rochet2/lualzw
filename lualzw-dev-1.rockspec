package = "lualzw"
version = "dev-1"

source = {
    url = "git+https://github.com/Rochet2/lualzw.git",
    branch = "master",
}

description = {
    summary = "A relatively fast LZW compression algorithm in pure Lua",
    detailed = [[
Lossless LZW compression for Lua strings. Supports configurable skipped
bytes in compressed output and optional decompression size limits.
Compatible with Lua 5.1 and later.
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
