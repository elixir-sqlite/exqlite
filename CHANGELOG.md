# Changelog

## Unreleased

## v0.19.0

- changed: Dropped support for Elixir v1.13.
- changed: Updated readme documentation.
- changed: Updated locked dependencies.

## v0.18.0

- added: Ability to specify build parameters programatically.
- changed: Updated sqlite3 to `3.44.2`.

## v0.17.0

- changed: Updaetd sqlite3 to `3.44.0`.
- added: `:before_disconnect` hook.

## v0.16.2
- fixed: Precompile support for Windows.

## v0.16.1
- fixed: Precompiled binaries for OTP 26. Windows precompiled binaries should work now.

## v0.16.0
- added: `set_log_hook`.
- removed: `utf8.h` as it is not necessary.

## v0.15.0
- added: `set_update_hook`.
- fixed: sqlite extension alignment problem by utilizing `size_t`.
- changed: Drop support for Elixir `1.12`.
- changed: Drop support for OTP 23.
- changed: Updated sqlite3 to `3.43.2`.

## v0.14.0
- changed: Updated sqlite3 to `3.43.1`.

## v0.13.15
- fixed: allow gnu compiled binaries to be included on the checksum update step.
- fixed: do not bind atoms that are prefixed with `nil` as `NULL`. https://github.com/elixir-sqlite/exqlite/pull/258

## v0.13.14
- fixed: OTP26 and Elixir 1.15 compilation issues.

## v0.13.13
- fixed: Check for `null` sqlite db connection.

## v0.13.12
- changed: Updated sqlite3 to `3.42.0`.

## v0.13.11
- fixed: Wrap include directory with string so it works with the compiler.

## v0.13.10
- added: Ability to specify `:load_extensions` for custom sqlite extensions.
- changed: Updated sqlite3 to `3.41.2`.

## v0.13.9
- fixed: Do not free mutex if it is not set.

## v0.13.8
- fixed: Handle SEGFAULT when trying to open a database that the application does not have permissions to open.

## v0.13.7
- added: precompilation support for musl based libc.
- changed: Updated sqlite to `3.41.1`.

## v0.13.6
- fixed: Error responses from sqlite NIF come back as an atom, the `message` field in `Exqlite.Error` is expected to be a string.

## v0.13.5
- changed: Allow `:force_build` to be specified in application configration to allow projects to force build the application rather than use precompiled binaries.

## v0.13.4
- changed: Updated sqlite3 to `3.41.0`.

## v0.13.3
- added: precompilation support.

## v0.13.2
- fixed: `-O2` flag was not being set when compiling binaries in non windows environment.

## v0.13.1
- added: `SQLITE_ENABLE_DBSTAT_VTAB=1`.
- changed: Allow `EXQLITE_SYSTEM_CFLAGS` to be appended to the `CFLAGS` regardless.

## v0.13.0
- removed: Remove support for Elixir 1.11
- added: Support for custom pragmas to be set.
- changed: Updated sqlite3 to 3.40.1

## v0.12.0
- changed: Use `multi_step` for `Repo.stream` calls.
- added: Ability to use URI for a database path. See [sqlite docs](https://sqlite.org/uri.html). Example: `file:/tmp/database.db?mode=ro`.

## v0.11.9
- fixed: `step/2` typespec was specified incorrectly.

## v0.11.8
- changed: Updated sqlite3 to 3.40.0

## v0.11.7
- fixed: Segfault issue when database connections would time out.

## v0.11.6
- changed: Updated sqlite3 to 3.39.4

## v0.11.5
- changed: Updated sqlite3 to 3.39.3

## v0.11.4
- changed: Use `sqlite3_open_v2`.
- changed: Expose `:mode`.
- changed: Removed old macro hack for erlang nifs.

## v0.11.3
- changed: Updated sqlite3 to 3.39.2

## v0.11.2
- changed: Fix incorrect ordering due to `Enum.reverse/1`.

## v0.11.1
- changed: Updated sqlite3 to 3.38.5

## v0.11.0
- added: top level interface for `Exqlite` similar to `Postgrex`'s interface.
- added: optional table protocol support for results.

## v0.10.3
- fixed: Improved `fetch_all/4` call speed.

## v0.10.2
- changed: Updated sqlite3 to 3.38.
- revert: change made to Visual Studio 2022 vcvars64.bat

## v0.10.1
- fix: path to Visual Studio 2022 vcvars64.bat

## v0.10.0
- added: Custom memory allocator for sqlite to leverage erlang's `enif_alloc` functionality. This allows the memory usage to be tracked with the erlang vm usage stats.

## v0.9.3
- fixed: `SIGSEGV` issue when a long running query is timed out.

## v0.9.2
- added: Ability to set `:journal_size_limit` in bytes.
- added: Ability to set `:soft_heap_limit` in bytes.
- added: Ability to set `:hard_heap_limit` in bytes.

## v0.9.1
- added: Documentation about compiling with system install sqlite3.
- fixed: Debug output during `mix compile` process.

## v0.9.0
- added: Allow setting `:key` option `PRAGMA` before all other pragmas to allow for use of encrypted sqlite databases.

## v0.8.7
- added: Ability to compile exqlite using the system sqlite3 installation as opposed to building from source.

## v0.8.6
- changed: Compile SQLite3 with `-DHAVE_USLEEP=1` to allow for more performant concurrent use.

## v0.8.5
- changed: Update SQLite from [3.37.0](https://www.sqlite.org/releaselog/3_37_0.html) to [3.37.2](https://sqlite.org/releaselog/3_37_2.html)

## v0.8.4
- fixed: Improved typespecs.

## v0.8.3
- changed: Compilation output to be less verbose. If more verbosity is desired `V=1 mix compile` will remedy that.
- changed: When the path to the database does not exist, `mkdir_p` is invoked.

## v0.8.2
- fixed: unicode handling when preparing sql statements.

## v0.8.1
- fixed: unicode handling when executing sql statements.

## v0.8.0
- changed: Updated SQLite from [3.36.0](https://www.sqlite.org/releaselog/3_36_0.html) to [3.37.0](https://www.sqlite.org/releaselog/3_37_0.html).

## v0.7.9
- changed: Debug build opt in, instead of opt out. `export DEBUG=yes` before compilation and it will add a `-g` to the compilation process.

## v0.7.3
- added: support for static erlang compilation.

## v0.7.2
- added: support for android compilation.

## v0.7.1
- fixed: segfault on double closing an sqlite connection.

## v0.7.0
- added: `Exqlite.Basic` for a simplified interface to utilizing sqlite3.
- added: ability to load sqlite extension.

## v0.6.4
- changed: Updated SQLite from 3.35.5 to [3.36.0](https://www.sqlite.org/releaselog/3_36_0.html)

## v0.6.3
- fixed: perceived memory leak for prepared statements not being cleaned up in a timely manner. This would be an issue for systems under a heavy load.

## v0.6.2
- changed: Handle only UTC datetime and convert them to iso form without offset.

## v0.6.1
- fixed: compilation issue on windows.

## v0.6.0
- added: `Exqlite.Sqlite3.serialize/2` to serialize the contents of the database to a binary.
- added: `Exqlite.Sqlite3.deserialize/3` to load a previously serialized database from a binary.

## v0.5.11
- changed: add the relevant sql statement to the Error exception message
- changed: update SQLite3 amalgamation to [3.35.5](https://sqlite.org/releaselog/3_35_5.html)
- fixed: issue with update returning nil rows for empty returning result.

## v0.5.10
- fixed: `maybe_set_pragma` was comparing upper case and lower case values when it should not matter.

## v0.5.9
- changed: Setting the pragma for `Exqlite.Connection` is now a two step process to check what the value is and then set it to the desired value if it is not already the desired value.

## v0.5.8
- added: `Exqlite.Error` now has the statement that failed that the error occurred on.

## v0.5.7
- changed: Update SQLite3 amalgamation to [3.35.4](https://sqlite.org/releaselog/3_35_4.html)

## v0.5.6
- fixed: SQLite3 amalgamation in 0.5.5 being incorrectly downgraded to 3.34.1. Amalgamation is now correctly [3.35.3](https://sqlite.org/releaselog/3_35_3.html).

## v0.5.5
- changed: Update SQLite3 amalgamation to version [3.35.3](https://sqlite.org/releaselog/3_35_3.html)

## v0.5.4
- fixed: incorrect passing of `chunk_size` to `fetch_all/4`

## v0.5.3
- fixed: `:invalid_chunk_size` being emitted by the `DBConnection.execute`

## v0.5.2
- added: Guide for Windows users.
- added: `Exqlite.Sqlite3.multi_step/3` to step through results chunks at a time.
- added: `default_chunk_size` configuration.

## v0.5.1
- changed: Bumped SQLite3 amalgamation to version [3.35.2](https://sqlite.org/releaselog/3_35_2.html)
- changed: Replaced old references of [github.com/warmwaffles](http://github.com/warmwaffles)

## v0.5.0
- removed: `Ecto.Adapters.Exqlite`. Replaced with [Ecto Sqlite3][ecto_sqlite3] library.


[ecto_sqlite3]: <https://github.com/elixir-sqlite/ecto_sqlite3>
