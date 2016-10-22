-- Contains some of the profiling code

local lualzw = require("lualzw")
local LibCompress = require("LibCompress")
local char = string.char

local function profile(input, comp, decomp)
    local compressT = 0
    local decompressT = 0
    local timesT = 10
    local x, dec
    local t1,t2,t3
    for i = 1, timesT do
        t1 = os.clock()
        compressed = comp(input)
        t2 = os.clock()
        decompressed = decomp(compressed)
        t3 = os.clock()
        compressT = compressT + t2-t1
        decompressT = decompressT + t3-t2
    end
    print(#input, #compressed, #decompressed, input == decompressed)
    print(compressT/timesT, decompressT/timesT, #compressed/#input*100)
end

math.randomseed(1)
local input1 = {}
local input2 = {}
local input3 = {}
local input4 = {}
for i = 1, 1000000 do
    input1[i] = char(math.random(0, 255))
    input2[i] = char(math.random(0, 127))
    input3[i] = char(i%256)
    input4[i] = char(100)
end
input1 = table.concat(input1)
input2 = table.concat(input2)
input3 = table.concat(input3)
input4 = table.concat(input4)

profile(input1, LibCompress.CompressLZW, LibCompress.DecompressLZW)
profile(input1, lualzw.compress, lualzw.decompress)

profile(input2, LibCompress.CompressLZW, LibCompress.DecompressLZW)
profile(input2, lualzw.compress, lualzw.decompress)

profile(input3, LibCompress.CompressLZW, LibCompress.DecompressLZW)
profile(input3, lualzw.compress, lualzw.decompress)

profile(input4, LibCompress.CompressLZW, LibCompress.DecompressLZW)
profile(input4, lualzw.compress, lualzw.decompress)

profile(("ymn32h8hm8ekrwjkrn9f"):rep(50000), LibCompress.CompressLZW, LibCompress.DecompressLZW)
profile(("ymn32h8hm8ekrwjkrn9f"):rep(50000), lualzw.compress, lualzw.decompress)
