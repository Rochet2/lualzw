std = "lua51"
include_files = {
    "lualzw.lua",
    "spec/test.lua",
    "benchmark/profiling.lua",
}

globals = {
    "LibCompress",
}

ignore = {
    "113", -- accessing an undefined global (LibCompress in optional benchmark)
    "122", -- unused variable in test helpers
}
