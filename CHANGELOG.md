# Changelog


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
- Bumped SQLite3 amalgamation to version 3.35.2
- Replaced old references of [github.com/warmwaffles](http://github.com/warmwaffles)


## [0.5.0] - 2021-03-17

### Removed
- Removed `Ecto.Adapters.Exqlite`
  Replaced with [Ecto Sqlite3][ecto_sqlite3] library.


[ecto_sqlite3]: <https://github.com/elixir-sqlite/ecto_sqlite3>

[Unreleased]: https://github.com/elixir-sqlite/exqlite/compare/v0.5.3...main
[0.5.3]: https://github.com/elixir-sqlite/exqlite/compare/v0.5.2...v0.5.3
[0.5.2]: https://github.com/elixir-sqlite/exqlite/compare/v0.5.1...v0.5.2
[0.5.1]: https://github.com/elixir-sqlite/exqlite/compare/v0.5.0...v0.5.1
[0.5.0]: https://github.com/elixir-sqlite/exqlite/compare/v0.4.9...v0.5.0
