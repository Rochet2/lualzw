-- Optional benchmarks for lualzw (and LibCompress when available).
-- Run from repository root:
--   lua benchmark/profiling.lua
--   lua benchmark/profiling.lua --quick

package.path = "?.lua;" .. package.path

local lualzw = require("lualzw")
local char = string.char

local quick = arg[1] == "--quick"
local size = quick and 10000 or 1000000
local times = quick and 3 or 10

local LibCompress
local hasLibCompress = pcall(function()
    LibCompress = require("LibCompress")
end)

local function buildRandom(seed, count, maxByte)
    math.randomseed(seed)
    local parts = {}
    for i = 1, count do
        parts[i] = char(math.random(0, maxByte))
    end
    return table.concat(parts)
end

local function buildCycling(count)
    local parts = {}
    for i = 1, count do
        parts[i] = char(i % 256)
    end
    return table.concat(parts)
end

local function profile(name, input, comp, decomp, label)
    local compressT = 0
    local decompressT = 0
    local compressed, decompressed
    local t1, t2, t3
    for _ = 1, times do
        t1 = os.clock()
        compressed = comp(input)
        t2 = os.clock()
        decompressed = decomp(compressed)
        t3 = os.clock()
        compressT = compressT + (t2 - t1)
        decompressT = decompressT + (t3 - t2)
    end
    local ratio = (#compressed / #input) * 100
    print(string.format("[%s] %s", label, name))
    print(string.format(
        "  input=%d compressed=%d ok=%s compress=%.4fs decompress=%.4fs ratio=%.2f%%",
        #input, #compressed, tostring(decompressed == input),
        compressT / times, decompressT / times, ratio
    ))
    if decompressed ~= input then
        error("round-trip failed for " .. name)
    end
    return ratio
end

local cases = {
    {
        name = "random bytes",
        input = function()
            return buildRandom(1, size, 255)
        end,
    },
    {
        name = "random ASCII",
        input = function()
            return buildRandom(2, size, 127)
        end,
    },
    {
        name = "cycling bytes",
        input = function()
            return buildCycling(size)
        end,
    },
    {
        name = "single repeated byte",
        input = function()
            return char(100):rep(size)
        end,
    },
    {
        name = "repeated pattern",
        input = function()
            return ("ymn32h8hm8ekrwjkrn9f"):rep(math.floor(size / 20))
        end,
    },
}

print(string.format(
    "lualzw benchmark (size=%d, iterations=%d, quick=%s, LibCompress=%s)",
    size, times, tostring(quick), tostring(hasLibCompress)
))

local codecs = {
    { label = "default", codec = lualzw },
    { label = "nullsafe", codec = lualzw.configure({ skip = { [0] = true } }) },
}

for _, case in ipairs(cases) do
    local input = case.input()
    print("")
    print("case: " .. case.name .. " (" .. #input .. " bytes)")

    for _, entry in ipairs(codecs) do
        profile(
            case.name,
            input,
            entry.codec.compress,
            entry.codec.decompress,
            "lualzw/" .. entry.label
        )
    end

    if hasLibCompress then
        profile(
            case.name,
            input,
            LibCompress.CompressLZW,
            LibCompress.DecompressLZW,
            "LibCompress"
        )
    end
end

if not hasLibCompress then
    print("")
    print("LibCompress not installed; skipped comparison runs.")
end
