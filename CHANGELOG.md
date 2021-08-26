# Changelog

## [Unreleased](unreleased)
### Fixed
- Fixed perceived memory leak for prepared statements not being cleaned up in a timely manner. This would be an issue for systems under a heavy load. [#155](https://github.com/elixir-sqlite/exqlite/pull/155)

## [0.6.2] - 2021-08-25
### Changed
- Handle only UTC datetime and convert them to iso form without offset [#157](https://github.com/elixir-sqlite/exqlite/pull/157)


## [0.6.1] - 2021-05-17
### Fixed
- Fixed compilation issue on windows [#151](https://github.com/elixir-sqlite/exqlite/pull/151)


## [0.6.0] - 2021-05-5
### Added
- `Exqlite.Sqlite3.serialize/2` to serialize the contents of the database to a binary.
- `Exqlite.Sqlite3.deserialize/3` to load a previously serialized database from a binary.


## [0.5.11] - 2021-05-02
### Changed
- add the relevant sql statement to the Error exception message
- update SQLite3 amalgamation to [3.35.5](https://sqlite.org/releaselog/3_35_5.html)

### Fixed
- fix issue with update returning nil rows for empty returning result [#146](https://github.com/elixir-sqlite/exqlite/pull/146)


## [0.5.10] - 2021-04-06
### Fixed
- `maybe_set_pragma` was comparing upper case and lower case values when it
  should not matter.


## [0.5.9] - 2021-04-06
### Changed
- Setting the pragma for `Exqlite.Connection` is now a two step process to check
  what the value is and then set it to the desired value if it is not already
  the desired value.


## [0.5.8] - 2021-04-04
### Added
- `Exqlite.Error` now has the statement that failed that the error occurred on.


## [0.5.7] - 2021-04-04
### Changed
- Update SQLite3 amalgamation to [3.35.4](https://sqlite.org/releaselog/3_35_4.html)


## [0.5.6] - 2021-04-02
### Fixed
- Fix SQLite3 amalgamation in 0.5.5 being incorrectly downgraded to 3.34.1. Amalgamation is now correctly [3.35.3](https://sqlite.org/releaselog/3_35_3.html).


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
[unreleased]: https://github.com/elixir-sqlite/exqlite/compare/v0.6.1...HEAD
[0.6.1]: https://github.com/elixir-sqlite/exqlite/compare/v0.6.1...v0.6.0
[0.6.0]: https://github.com/elixir-sqlite/exqlite/compare/v0.5.11...v0.6.0
[0.5.11]: https://github.com/elixir-sqlite/exqlite/compare/v0.5.10...v0.5.11
[0.5.10]: https://github.com/elixir-sqlite/exqlite/compare/v0.5.9...v0.5.10
[0.5.9]: https://github.com/elixir-sqlite/exqlite/compare/v0.5.8...v0.5.9
[0.5.8]: https://github.com/elixir-sqlite/exqlite/compare/v0.5.7...v0.5.8
[0.5.7]: https://github.com/elixir-sqlite/exqlite/compare/v0.5.6...v0.5.7
[0.5.6]: https://github.com/elixir-sqlite/exqlite/compare/v0.5.5...v0.5.6
[0.5.5]: https://github.com/elixir-sqlite/exqlite/compare/v0.5.4...v0.5.5
[0.5.4]: https://github.com/elixir-sqlite/exqlite/compare/v0.5.3...v0.5.4
[0.5.3]: https://github.com/elixir-sqlite/exqlite/compare/v0.5.2...v0.5.3
[0.5.2]: https://github.com/elixir-sqlite/exqlite/compare/v0.5.1...v0.5.2
[0.5.1]: https://github.com/elixir-sqlite/exqlite/compare/v0.5.0...v0.5.1
[0.5.0]: https://github.com/elixir-sqlite/exqlite/compare/v0.4.9...v0.5.0
