# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.1.0] - 2026-05-31

### Added

- Runtime configuration via `lualzw.configure({ skip = ..., uncompressed = ..., compressed = ... })`
- Configurable passthrough / compressed control prefixes (default `u` / `c`)
- Optional limits: `compress(input, max_input_size)` and `decompress(input, max_output_size, max_input_size, max_codes)`
- Module version export: `lualzw._VERSION`, `lualzw.uncompressed`, `lualzw.compressed`
- Automated test suite (`spec/test.lua`)
- LuaRocks rockspec, GitHub Actions CI, Luacheck linting
- `CHANGELOG.md`, `.editorconfig`

### Changed

- Configurable skipped bytes replace the old `zeros` / `skip` branches (default `{}` preserves original encoding)
- Bailout returns passthrough when compressed size would not be strictly smaller than input
- Decompression validates odd-length compressed bodies and unknown first codes
- `profiling.lua` moved to `benchmark/profiling.lua`
- README rewritten with API, network, and wire-format documentation

### Fixed

- `profiling.lua` no longer assigns globals for compressed/decompressed results

## [1.0.0] - 2016

- Initial release: LZW compress/decompress with `c` / `u` wire prefixes

[1.1.0]: https://github.com/Rochet2/lualzw/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/Rochet2/lualzw/releases/tag/v1.0.0
