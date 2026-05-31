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

local function assert_roundtrip(input)
    local compressed, err = lualzw.compress(input)
    assert(compressed, err)
    local decompressed, derr = lualzw.decompress(compressed)
    assert(decompressed, derr)
    assert(decompressed == input)
end

test("empty string roundtrip", function()
    assert_roundtrip("")
    assert(lualzw.compress("") == "u")
    assert(lualzw.decompress("u") == "")
end)

test("single byte roundtrip", function()
    assert_roundtrip("a")
    assert(lualzw.compress("a") == "ua")
    assert(lualzw.decompress("ua") == "a")
end)

test("repetitive text roundtrip", function()
    assert_roundtrip(("foo"):rep(100))
    assert_roundtrip(("ymn32h8hm8ekrwjkrn9f"):rep(500))
end)

test("random-ish bytes roundtrip", function()
    local parts = {}
    for i = 1, 4096 do
        parts[i] = string.char(i % 256)
    end
    assert_roundtrip(table.concat(parts))
end)

test("compress type error", function()
    local ok, err = lualzw.compress(123)
    assert(ok == nil)
    assert(err == "string expected, got number")
end)

test("decompress type error", function()
    local ok, err = lualzw.decompress({})
    assert(ok == nil)
    assert(err == "string expected, got table")
end)

test("decompress invalid input", function()
    local ok, err = lualzw.decompress("")
    assert(ok == nil)
    assert(err == "invalid input - not a compressed string")

    ok, err = lualzw.decompress("x")
    assert(ok == nil)
    assert(err == "invalid input - not a compressed string")

    ok, err = lualzw.decompress("c")
    assert(ok == nil)
    assert(err == "invalid input - not a compressed string")
end)

test("decompress corrupt compressed data", function()
    local ok, err = lualzw.decompress("c" .. string.char(99, 99))
    assert(ok == nil)
    assert(err == "could not find last from dict. Invalid input?")
end)

test("decompress max_output_size limit", function()
    local input = ("abc"):rep(1000)
    local compressed = assert(lualzw.compress(input))

    local ok, err = lualzw.decompress(compressed, 100)
    assert(ok == nil)
    assert(err == "decompressed output exceeds limit")

    local out = assert(lualzw.decompress(compressed, #input))
    assert(out == input)
end)

test("decompress passthrough max_output_size limit", function()
    local ok, err = lualzw.decompress("u" .. ("x"):rep(10), 5)
    assert(ok == nil)
    assert(err == "decompressed output exceeds limit")
end)

test("decompress max_output_size type error", function()
    local ok, err = lualzw.decompress("ua", "nope")
    assert(ok == nil)
    assert(err == "number expected for max_output_size, got string")
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

if failed > 0 then
    io.stderr:write(string.format("\n%d passed, %d failed\n", passed, failed))
    os.exit(1)
end

print(string.format("%d passed", passed))
