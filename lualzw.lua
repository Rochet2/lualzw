--[[
MIT License

Copyright (c) 2016 Rochet2

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
]]

local char = string.char
local type = type
local sub = string.sub
local tconcat = table.concat

-- Byte values that must not appear in compressed output (0-255).
-- Default matches the original encoding (codes may contain \0).
-- Add [0] = true to avoid null bytes in compressed output.
-- Each skipped byte reduces the number of available dictionary codes.
local skippedcharacters = {
}

local function findNextNotSkipped(i)
    repeat
        if not skippedcharacters[i] then
            return i
        end
        i = i+1
    until false
end

local basedictcompress = {}
local basedictdecompress = {}

local firstNotSkipped = findNextNotSkipped(0)
local secondNotSkipped = findNextNotSkipped(firstNotSkipped+1)
if firstNotSkipped > 255 or secondNotSkipped > 255 or firstNotSkipped == secondNotSkipped then
    error("invalid configuration, no character can be used in compression")
end
for i = 0, 255 do
    local ic, iic = char(i), char(i, firstNotSkipped)
    basedictcompress[ic] = iic
    basedictdecompress[iic] = ic
end

local function dictBump(dict, a, b)
    if a >= 256 then
        a, b = firstNotSkipped, findNextNotSkipped(b+1)
        if b >= 256 then
            dict = {}
            b = secondNotSkipped
        end
    end
    local code = char(a, b)
    a = findNextNotSkipped(a+1)
    return dict, a, b, code
end

local function compress(input)
    if type(input) ~= "string" then
        return nil, "string expected, got "..type(input)
    end
    local len = #input
    if len <= 1 then
        return "u"..input
    end

    local dict = {}
    local a, b = firstNotSkipped, secondNotSkipped
    local code

    local result = {"c"}
    local resultlen = 1
    local n = 2
    local word = ""
    for i = 1, len do
        local c = sub(input, i, i)
        local wc = word..c
        if not (basedictcompress[wc] or dict[wc]) then
            local write = basedictcompress[word] or dict[word]
            if not write then
                return nil, "algorithm error, could not fetch word"
            end
            result[n] = write
            resultlen = resultlen + 2
            n = n+1
            if len < resultlen then
                return "u"..input
            end
            dict, a, b, code = dictBump(dict, a, b)
            dict[wc] = code
            word = c
        else
            word = wc
        end
    end
    result[n] = basedictcompress[word] or dict[word]
    resultlen = resultlen + 2
    n = n+1
    if len < resultlen then
        return "u"..input
    end
    return tconcat(result)
end

local function decompress(input, max_output_size)
    if type(input) ~= "string" then
        return nil, "string expected, got "..type(input)
    end

    if max_output_size ~= nil then
        if type(max_output_size) ~= "number" or max_output_size < 0 then
            return nil, "number expected for max_output_size, got "..type(max_output_size)
        end
    end

    if #input < 1 then
        return nil, "invalid input - not a compressed string"
    end

    local control = sub(input, 1, 1)
    if control == "u" then
        local out = sub(input, 2)
        if max_output_size and #out > max_output_size then
            return nil, "decompressed output exceeds limit"
        end
        return out
    elseif control ~= "c" then
        return nil, "invalid input - not a compressed string"
    end
    input = sub(input, 2)
    local len = #input

    if len < 2 or len % 2 == 1 then
        return nil, "invalid input - not a compressed string"
    end

    local dict = {}
    local a, b = firstNotSkipped, secondNotSkipped
    local dictCode

    local result = {}
    local n = 1
    local outputlen = 0
    local last = sub(input, 1, 2)
    local firstStr = basedictdecompress[last] or dict[last]
    if not firstStr then
        return nil, "could not find last from dict. Invalid input?"
    end
    result[n] = firstStr
    outputlen = outputlen + #firstStr
    if max_output_size and outputlen > max_output_size then
        return nil, "decompressed output exceeds limit"
    end
    n = n+1
    for i = 3, len, 2 do
        local inputCode = sub(input, i, i+1)
        local lastStr = basedictdecompress[last] or dict[last]
        if not lastStr then
            return nil, "could not find last from dict. Invalid input?"
        end
        local toAdd = basedictdecompress[inputCode] or dict[inputCode]
        if toAdd then
            outputlen = outputlen + #toAdd
            if max_output_size and outputlen > max_output_size then
                return nil, "decompressed output exceeds limit"
            end
            result[n] = toAdd
            n = n+1
            dict, a, b, dictCode = dictBump(dict, a, b)
            dict[dictCode] = lastStr..sub(toAdd, 1, 1)
        else
            local tmp = lastStr..sub(lastStr, 1, 1)
            outputlen = outputlen + #tmp
            if max_output_size and outputlen > max_output_size then
                return nil, "decompressed output exceeds limit"
            end
            result[n] = tmp
            n = n+1
            dict, a, b, dictCode = dictBump(dict, a, b)
            dict[dictCode] = tmp
        end
        last = inputCode
    end
    return tconcat(result)
end

return {
    compress = compress,
    decompress = decompress,
}
