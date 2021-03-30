# Changelog


## [0.5.5] - 2021-03-29

### Changed
- Bump SQLite3 amalgamation to version [3.35.3](https://sqlite.org/releaselog/3_35_3.html)


## [0.5.4] - 2021-03-23

### Fixed
- Fix incorrect passing of `chunk_size` to `fetch_all/4`


## [0.5.3] - 2021-03-23

### Fixed
- `:invalid_chunk_size` being emitted by the `DBConnection.execute`


## [0.5.2] - 2021-03-23

### Added
- Guide for Windows users.
- `Exqlite.Sqlite3.multi_step/3` to step through results chunks at a time.
- `default_chunk_size` configuration.


## [0.5.1] - 2021-03-19

### Changed
- Bumped SQLite3 amalgamation to version [3.35.2](https://sqlite.org/releaselog/3_35_2.html)
- Replaced old references of [github.com/warmwaffles](http://github.com/warmwaffles)


## [0.5.0] - 2021-03-17

### Removed
- Removed `Ecto.Adapters.Exqlite`
  Replaced with [Ecto Sqlite3][ecto_sqlite3] library.


[ecto_sqlite3]: <https://github.com/elixir-sqlite/ecto_sqlite3>

[Unreleased]: https://github.com/elixir-sqlite/exqlite/compare/v0.5.5...main
[0.5.5]: https://github.com/elixir-sqlite/exqlite/compare/v0.5.4...v0.5.5
[0.5.4]: https://github.com/elixir-sqlite/exqlite/compare/v0.5.3...v0.5.4
[0.5.3]: https://github.com/elixir-sqlite/exqlite/compare/v0.5.2...v0.5.3
[0.5.2]: https://github.com/elixir-sqlite/exqlite/compare/v0.5.1...v0.5.2
[0.5.1]: https://github.com/elixir-sqlite/exqlite/compare/v0.5.0...v0.5.1
[0.5.0]: https://github.com/elixir-sqlite/exqlite/compare/v0.4.9...v0.5.0
