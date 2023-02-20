# Changelog

## Unlreleased

## v0.13.3 - 2023-02-19
- added: precompilation support. [#234](https://github.com/elixir-sqlite/exqlite/pull/234)

## v0.13.2 - 2023-01-26
- fixed: `-O2` flag was not being set when compiling binaries in non windows environment.

## v0.13.1 - 2023-01-26
- added: `SQLITE_ENABLE_DBSTAT_VTAB=1`.
- changed: Allow `EXQLITE_SYSTEM_CFLAGS` to be appended to the `CFLAGS` regardless.

## v0.13.0 - 2023-01-11
- removed: Remove support for Elixir 1.11
- added: Support for custom pragmas to be set. [#229](https://github.com/elixir-sqlite/exqlite/pull/229)
- changed: Updated sqlite3 to 3.40.1

## v0.12.0 - 2022-12-07
- changed: Use `multi_step` for `Repo.stream` calls. [#223](https://github.com/elixir-sqlite/exqlite/pull/223)
- added: Ability to use URI for a database path. See [sqlite docs](https://sqlite.org/uri.html). Example: `file:/tmp/database.db?mode=ro`. [#225](https://github.com/elixir-sqlite/exqlite/pull/225)

## v0.11.9 - 2022-12-01
- fixed: `step/2` typespec was specified incorrectly. [#224](https://github.com/elixir-sqlite/exqlite/pull/224)

## v0.11.8 - 2022-11-17
- changed: Updated sqlite3 to 3.40.0

## v0.11.7 - 2022-10-27
- fixed: Segfault issue when database connections would time out. [#218](https://github.com/elixir-sqlite/exqlite/pull/218)

## v0.11.6 - 2022-09-29
- changed: Updated sqlite3 to 3.39.4

## v0.11.5 - 2022-09-28
- changed: Updated sqlite3 to 3.39.3

## v0.11.4 - 2022-08-24
- changed: Use `sqlite3_open_v2`. [#211](https://github.com/elixir-sqlite/exqlite/pull/211)
- changed: Expose `:mode`. [#212](https://github.com/elixir-sqlite/exqlite/pull/212)
- changed: Removed old macro hack for erlang nifs. [#213](https://github.com/elixir-sqlite/exqlite/pull/213)

## v0.11.3 - 2022-08-04
- changed: Updated sqlite3 to 3.39.2

## v0.11.2 - 2022-05-13
- changed: Fix incorrect ordering due to `Enum.reverse/1`. [#205](https://github.com/elixir-sqlite/exqlite/pull/205)

## v0.11.1 - 2022-05-13
- changed: Updated sqlite3 to 3.38.5

## v0.11.0 - 2022-05-05
- added: top level interface for `Exqlite` similar to `Postgrex`'s interface.
- added: optional table protocol support for results.

## v0.10.3 - 2022-04-10
- fixed: Improved `fetch_all/4` call speed. [#200](https://github.com/elixir-sqlite/exqlite/pull/200) [#201](https://github.com/elixir-sqlite/exqlite/pull/201)

## v0.10.2 - 2022-03-10
- changed: Updated sqlite3 to 3.38.
- revert: change made to Visual Studio 2022 vcvars64.bat [#194](https://github.com/elixir-sqlite/exqlite/pull/194)

## v0.10.1 - 2022-03-01
- fix: path to Visual Studio 2022 vcvars64.bat [#194](https://github.com/elixir-sqlite/exqlite/pull/194)

## v0.10.0 - 2022-02-24
- added: Custom memory allocator for sqlite to leverage erlang's `enif_alloc` functionality. This allows the memory usage to be tracked with the erlang vm usage stats. [#193](https://github.com/elixir-sqlite/exqlite/pull/193)

## v0.9.3 - 2022-02-02
- fixed: `SIGSEGV` issue when a long running query is timed out. [#191](https://github.com/elixir-sqlite/exqlite/pull/191)

## v0.9.2 - 2022-01-27
- added: Ability to set `:journal_size_limit` in bytes. [#189](https://github.com/elixir-sqlite/exqlite/pull/189)
- added: Ability to set `:soft_heap_limit` in bytes. [#189](https://github.com/elixir-sqlite/exqlite/pull/189)
- added: Ability to set `:hard_heap_limit` in bytes. [#189](https://github.com/elixir-sqlite/exqlite/pull/189)

## v0.9.1 - 2022-01-21
- added: Documentation about compiling with system install sqlite3.
- fixed: Debug output during `mix compile` process.

## v0.9.0 - 2022-01-21
- added: Allow setting `:key` option `PRAGMA` before all other pragmas to allow for use of encrypted sqlite databases. [#187](https://github.com/elixir-sqlite/exqlite/pull/187)

## v0.8.7 - 2022-01-21
- added: Ability to compile exqlite using the system sqlite3 installation as opposed to building from source. [#186](https://github.com/elixir-sqlite/exqlite/pull/186)

## v0.8.6 - 2022-01-19
- changed: Compile SQLite3 with `-DHAVE_USLEEP=1` to allow for more performant concurrent use.

## v0.8.5 - 2022-01-14
- changed: Update SQLite from [3.37.0](https://www.sqlite.org/releaselog/3_37_0.html) to [3.37.2](https://sqlite.org/releaselog/3_37_2.html)

## v0.8.4 - 2021-12-08
- fixed: Improved typespecs. [#177](https://github.com/elixir-sqlite/exqlite/pull/177)

## v0.8.3 - 2021-12-07
- changed: Compilation output to be less verbose. If more verbosity is desired `V=1 mix compile` will remedy that. [#181](https://github.com/elixir-sqlite/exqlite/pull/181)
- changed: When the path to the database does not exist, `mkdir_p` is invoked. [#180](https://github.com/elixir-sqlite/exqlite/pull/180)

## v0.8.2 - 2021-12-03
- fixed: unicode handling when preparing sql statements.

## v0.8.1 - 2021-12-03
- fixed: unicode handling when executing sql statements. [#179](https://github.com/elixir-sqlite/exqlite/pull/179)

## v0.8.0 - 2021-11-30
- changed: Updated SQLite from [3.36.0](https://www.sqlite.org/releaselog/3_36_0.html) to [3.37.0](https://www.sqlite.org/releaselog/3_37_0.html).

## v0.7.9 - 2021-10-25
- changed: Debug build opt in, instead of opt out. `export DEBUG=yes` before compilation and it will add a `-g` to the compilation process.

## v0.7.3 - 2021-10-08
- added: support for static erlang compilation. [#167](https://github.com/elixir-sqlite/exqlite/pull/167)

## v0.7.2 - 2021-09-13
- added: support for android compilation. [#164](https://github.com/elixir-sqlite/exqlite/pull/164)

## v0.7.1 - 2021-09-09
- fixed: segfault on double closing an sqlite connection. [#162](https://github.com/elixir-sqlite/exqlite/pull/162)

## v0.7.0 - 2021-09-08
- added: `Exqlite.Basic` for a simplified interface to utilizing sqlite3. [#160](https://github.com/elixir-sqlite/exqlite/pull/160)
- added: ability to load sqlite extension. [#160](https://github.com/elixir-sqlite/exqlite/pull/160)

## v0.6.4 - 2021-09-04
- changed: Updated SQLite from 3.35.5 to [3.36.0](https://www.sqlite.org/releaselog/3_36_0.html)

## v0.6.3 - 2021-08-26
- fixed: perceived memory leak for prepared statements not being cleaned up in a timely manner. This would be an issue for systems under a heavy load. [#155](https://github.com/elixir-sqlite/exqlite/pull/155)

## v0.6.2 - 2021-08-25
- changed: Handle only UTC datetime and convert them to iso form without offset [#157](https://github.com/elixir-sqlite/exqlite/pull/157)

## v0.6.1 - 2021-05-17
- fixed: compilation issue on windows [#151](https://github.com/elixir-sqlite/exqlite/pull/151)

## v0.6.0 - 2021-05-5
- added: `Exqlite.Sqlite3.serialize/2` to serialize the contents of the database to a binary.
- added: `Exqlite.Sqlite3.deserialize/3` to load a previously serialized database from a binary.

## v0.5.11 - 2021-05-02
- changed: add the relevant sql statement to the Error exception message
- changed: update SQLite3 amalgamation to [3.35.5](https://sqlite.org/releaselog/3_35_5.html)
- fixed: issue with update returning nil rows for empty returning result [#146](https://github.com/elixir-sqlite/exqlite/pull/146)

## v0.5.10 - 2021-04-06
- fixed: `maybe_set_pragma` was comparing upper case and lower case values when it should not matter.

## v0.5.9 - 2021-04-06
- changed: Setting the pragma for `Exqlite.Connection` is now a two step process to check what the value is and then set it to the desired value if it is not already the desired value.

## v0.5.8 - 2021-04-04
- added: `Exqlite.Error` now has the statement that failed that the error occurred on.

## v0.5.7 - 2021-04-04
- changed: Update SQLite3 amalgamation to [3.35.4](https://sqlite.org/releaselog/3_35_4.html)

## v0.5.6 - 2021-04-02
- fixed: SQLite3 amalgamation in 0.5.5 being incorrectly downgraded to 3.34.1. Amalgamation is now correctly [3.35.3](https://sqlite.org/releaselog/3_35_3.html).

## v0.5.5 - 2021-03-29
- changed: Update SQLite3 amalgamation to version [3.35.3](https://sqlite.org/releaselog/3_35_3.html)

## v0.5.4 - 2021-03-23
- fixed: incorrect passing of `chunk_size` to `fetch_all/4`

## v0.5.3 - 2021-03-23
- fixed: `:invalid_chunk_size` being emitted by the `DBConnection.execute`

## v0.5.2 - 2021-03-23
- added: Guide for Windows users.
- added: `Exqlite.Sqlite3.multi_step/3` to step through results chunks at a time.
- added: `default_chunk_size` configuration.

## v0.5.1 - 2021-03-19
- changed: Bumped SQLite3 amalgamation to version [3.35.2](https://sqlite.org/releaselog/3_35_2.html)
- changed: Replaced old references of [github.com/warmwaffles](http://github.com/warmwaffles)

## v0.5.0 - 2021-03-17
- removed: `Ecto.Adapters.Exqlite`. Replaced with [Ecto Sqlite3][ecto_sqlite3] library.


[ecto_sqlite3]: <https://github.com/elixir-sqlite/ecto_sqlite3>
