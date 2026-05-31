package.path = "?.lua;" .. package.path

local lualzw = require("lualzw")

local passed = 0
local failed = 0

local function test(name, fn)
    local ok, err = pcall(fn)
    if ok then
        passed = passed + 1
    else
        failed = failed + 1
        io.stderr:write("FAIL: " .. name .. ": " .. tostring(err) .. "\n")
    end
end

local function assert_roundtrip(codec, input)
    local compressed, err = codec.compress(input)
    assert(compressed, err)
    local decompressed, derr = codec.decompress(compressed)
    assert(decompressed, derr)
    assert(decompressed == input)
end

local function assert_error(fn, expected)
    local ok, err = fn()
    assert(ok == nil, "expected failure")
    assert(err == expected, "got: " .. tostring(err))
end

local function buildRandomInput(count, maxByte)
    math.randomseed(99)
    local parts = {}
    for i = 1, count do
        parts[i] = string.char(math.random(0, maxByte))
    end
    return table.concat(parts)
end

-- round-trips

test("empty string roundtrip", function()
    assert_roundtrip(lualzw, "")
    assert(lualzw.compress("") == "u")
    assert(lualzw.decompress("u") == "")
end)

test("single byte roundtrip", function()
    assert_roundtrip(lualzw, "a")
    assert(lualzw.compress("a") == "ua")
    assert(lualzw.decompress("ua") == "a")
end)

test("two byte roundtrip", function()
    assert_roundtrip(lualzw, "ab")
end)

test("repetitive text roundtrip", function()
    assert_roundtrip(lualzw, ("foo"):rep(100))
    assert_roundtrip(lualzw, ("ymn32h8hm8ekrwjkrn9f"):rep(500))
end)

test("cycling bytes roundtrip", function()
    local parts = {}
    for i = 1, 4096 do
        parts[i] = string.char(i % 256)
    end
    assert_roundtrip(lualzw, table.concat(parts))
end)

test("single repeated byte roundtrip", function()
    assert_roundtrip(lualzw, string.char(100):rep(500))
end)

test("embedded null bytes roundtrip", function()
    assert_roundtrip(lualzw, "before\0after\0")
end)

test("utf-8 multibyte roundtrip as bytes", function()
    assert_roundtrip(lualzw, "äöå")
end)

test("kwkwk-style pattern roundtrip", function()
    assert_roundtrip(lualzw, "ababcabababa")
    assert_roundtrip(lualzw, ("xyzzy"):rep(50))
end)

-- compress errors and limits

test("compress type error", function()
    assert_error(function() return lualzw.compress(123) end, "string expected, got number")
end)

test("compress max_input_size limit", function()
    assert_error(function() return lualzw.compress(("a"):rep(100), 50) end, "input exceeds limit")
end)

test("compress max_input_size type error", function()
    assert_error(function() return lualzw.compress("abc", "nope") end, "number expected for max_input_size, got string")
end)

test("incompressible data passthrough", function()
    math.randomseed(1)
    local parts = {}
    for i = 1, 64 do
        parts[i] = string.char(math.random(0, 255))
    end
    local input = table.concat(parts)
    local compressed = assert(lualzw.compress(input))
    assert(string.sub(compressed, 1, 1) == "u")
    assert(lualzw.decompress(compressed) == input)
end)

test("bailout uses passthrough when compression is not smaller", function()
    math.randomseed(42)
    local parts = {}
    for i = 1, 128 do
        parts[i] = string.char(math.random(0, 255))
    end
    local input = table.concat(parts)
    local compressed = assert(lualzw.compress(input))
    assert(string.sub(compressed, 1, 1) == "u")
    assert(#compressed == #input + 1)
end)

test("compressed output is smaller for repetitive data", function()
    local input = ("abc"):rep(200)
    local compressed = assert(lualzw.compress(input))
    assert(string.sub(compressed, 1, 1) == "c")
    assert(#compressed < #input)
end)

-- decompress errors and limits

test("decompress type error", function()
    assert_error(function() return lualzw.decompress({}) end, "string expected, got table")
end)

test("decompress invalid input", function()
    assert_error(function() return lualzw.decompress("") end, "invalid input - not a compressed string")
    assert_error(function() return lualzw.decompress("x") end, "invalid input - not a compressed string")
    assert_error(function() return lualzw.decompress("c") end, "invalid input - not a compressed string")
end)

test("decompress odd-length compressed body", function()
    assert_error(function() return lualzw.decompress("c" .. string.char(0, 1, 2)) end, "invalid input - not a compressed string")
end)

test("decompress corrupt compressed data", function()
    assert_error(
        function() return lualzw.decompress("c" .. string.char(99, 99)) end,
        "could not find last from dict. Invalid input?"
    )
end)

test("decompress max_output_size limit", function()
    local input = ("abc"):rep(1000)
    local compressed = assert(lualzw.compress(input))
    assert_error(function() return lualzw.decompress(compressed, 100) end, "decompressed output exceeds limit")
    assert(lualzw.decompress(compressed, #input) == input)
end)

test("decompress max_output_size exact boundary", function()
    local input = "hello"
    local compressed = assert(lualzw.compress(input))
    assert(lualzw.decompress(compressed, #input) == input)
end)

test("decompress passthrough max_output_size limit", function()
    assert_error(function() return lualzw.decompress("u" .. ("x"):rep(10), 5) end, "decompressed output exceeds limit")
end)

test("decompress max_output_size type error", function()
    assert_error(function() return lualzw.decompress("ua", "nope") end, "number expected for max_output_size, got string")
end)

test("decompress max_input_size limit", function()
    local input = ("abc"):rep(1000)
    local compressed = assert(lualzw.compress(input))
    assert_error(function() return lualzw.decompress(compressed, #input, 10) end, "compressed input exceeds limit")
end)

test("decompress max_input_size type error", function()
    assert_error(function() return lualzw.decompress("ua", nil, "nope") end, "number expected for max_input_size, got string")
end)

test("decompress max_codes limit", function()
    local input = ("abc"):rep(1000)
    local compressed = assert(lualzw.compress(input))
    assert_error(
        function() return lualzw.decompress(compressed, #input, #compressed, 1) end,
        "decompression step limit exceeded"
    )
end)

test("decompress max_codes type error", function()
    assert_error(function() return lualzw.decompress("ua", nil, nil, "nope") end, "number expected for max_codes, got string")
end)

-- configuration and wire formats

test("invalid skip configuration", function()
    local skip = {}
    for i = 0, 254 do
        skip[i] = true
    end
    local ok = pcall(function()
        lualzw.configure({skip = skip})
    end)
    assert(not ok)
end)

test("skip list form in configure", function()
    local codec = lualzw.configure({skip = {0, 1}})
    assert_roundtrip(codec, ("baz"):rep(40))
end)

test("runtime skip configuration roundtrip", function()
    local codec = lualzw.configure({skip = {[0] = true}})
    assert_roundtrip(codec, ("bar"):rep(50))
    local compressed = assert(codec.compress(("bar"):rep(50)))
    assert(not compressed:find("\0", 1, true))
end)

test("configure returns independent codecs", function()
    local nullsafe = lualzw.configure({skip = {[0] = true}})
    local legacy = lualzw.configure({skip = {}})
    assert_roundtrip(nullsafe, ("x"):rep(30))
    assert_roundtrip(legacy, ("y"):rep(30))
    local c1 = assert(nullsafe.compress(("x"):rep(30)))
    local c2 = assert(legacy.compress(("x"):rep(30)))
    assert(c1 ~= c2)
end)

test("null-safe skip configuration roundtrip", function()
    local codec = lualzw.configure({skip = {[0] = true}})
    assert(codec.uncompressed == "u")
    assert(codec.compressed == "c")
    assert_roundtrip(codec, ("network"):rep(100))
    local compressed = assert(codec.compress(("network"):rep(100)))
    assert(string.sub(compressed, 1, 1) == "c")
    assert(not compressed:find("\0", 1, true))
end)

test("custom control characters roundtrip", function()
    local codec = lualzw.configure({uncompressed = "p", compressed = "q"})
    assert(codec.uncompressed == "p")
    assert(codec.compressed == "q")
    assert(codec.compress("") == "p")
    assert(codec.compress("a") == "pa")
    assert_roundtrip(codec, ("custom"):rep(50))
    local compressed = assert(codec.compress(("custom"):rep(50)))
    assert(string.sub(compressed, 1, 1) == "q")
end)

test("invalid matching control characters", function()
    local ok = pcall(function()
        lualzw.configure({uncompressed = "x", compressed = "x"})
    end)
    assert(not ok)
end)

test("version export", function()
    assert(lualzw._VERSION == "1.1.0")
    assert(lualzw.uncompressed == "u")
    assert(lualzw.compressed == "c")
end)

-- benchmark smoke (lualzw-only, no LibCompress required)

test("benchmark smoke default codec", function()
    local input = buildRandomInput(8192, 255)
    local compressed = assert(lualzw.compress(input))
    assert(lualzw.decompress(compressed) == input)
    assert(#compressed <= #input + 1)
end)

test("benchmark smoke null-safe codec", function()
    local codec = lualzw.configure({skip = {[0] = true}})
    local input = ("pattern"):rep(400)
    local compressed = assert(codec.compress(input))
    assert(codec.decompress(compressed) == input)
    assert(#compressed < #input)
end)

if failed > 0 then
    io.stderr:write(string.format("\n%d passed, %d failed\n", passed, failed))
    os.exit(1)
end

print(string.format("%d passed", passed))
