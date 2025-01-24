# Exqlite

[![Build Status](https://github.com/elixir-sqlite/exqlite/workflows/CI/badge.svg)](https://github.com/elixir-sqlite/exqlite/actions)
[![Hex Package](https://img.shields.io/hexpm/v/exqlite.svg)](https://hex.pm/packages/exqlite)
[![Hex Docs](https://img.shields.io/badge/hex-docs-blue.svg)](https://hexdocs.pm/exqlite)

An Elixir SQLite3 library.

If you are looking for the Ecto adapter, take a look at the
[Ecto SQLite3 library][ecto_sqlite3].

Documentation: https://hexdocs.pm/exqlite
Package: https://hex.pm/packages/exqlite


## Caveats

* Prepared statements are not cached.
* Prepared statements are not immutable. You must be careful when manipulating
  statements and binding values to statements. Do not try to manipulate the
  statements concurrently. Keep it isolated to one process.
* Simultaneous writing is not supported by SQLite3 and will not be supported
  here.
* All native calls are run through the Dirty NIF scheduler.
* Datetimes are stored without offsets. This is due to how SQLite3 handles date
  and times. If you would like to store a timezone, you will need to create a
  second column somewhere storing the timezone name and shifting it when you
  get it from the database. This is more reliable than storing the offset as
  `+03:00` as it does not respect daylight savings time.
* When storing `BLOB` values, you have to use `{:blob, the_binary}`, otherwise
  it will be interpreted as a string.

## Installation

```elixir
defp deps do
  [
    {:exqlite, "~> 0.27"}
  ]
end
```


## Configuration

### Runtime Configuration

```elixir
config :exqlite, default_chunk_size: 100
```

* `default_chunk_size` - The chunk size that is used when multi-stepping when
  not specifying the chunk size explicitly.
  
### Compile-time Configuration

In `config/config.exs`,

```elixir
config :exqlite, force_build: false
```

* `force_build` - Set `true` to opt out of using precompiled artefacts.
  This option only affects the default configuration. For advanced configuation,
  this library will always compile natively.

## Advanced Configuration

### Defining Extra Compile Flags

You can enable certain features by doing the following:

```bash
export EXQLITE_SYSTEM_CFLAGS=-DSQLITE_ENABLE_DBSTAT_VTAB=1
```

Or you can pass extra environment variables using the Elixir config:

```elixir
config :exqlite,
  force_build: true,
  make_env: %{
    "EXQLITE_SYSTEM_CFLAGS" => "-DSQLITE_ENABLE_DBSTAT_VTAB=1",
    "V" => "1"
  }
```

### Listing Flags Used For Compilation

If you `export V=1` the flags used for compilation will be output to stdout.

### Using System Installed Libraries

This will vary depending on the operating system.

```bash
# tell exqlite that we wish to use some other sqlite installation. this will prevent sqlite3.c and friends from compiling
export EXQLITE_USE_SYSTEM=1

# Tell exqlite where to find the `sqlite3.h` file
export EXQLITE_SYSTEM_CFLAGS=-I/usr/include

# tell exqlite which sqlite implementation to use
export EXQLITE_SYSTEM_LDFLAGS=-L/lib -lsqlite3
```

After exporting those variables you can then invoke `mix deps.compile`. Note if you
re-export those values, you will need to recompile the `exqlite` dependency in order to
pickup those changes.

### Database Encryption

As of version 0.9, `exqlite` supports loading database engines at runtime rather than compiling `sqlite3.c` itself.
This can be used to support database level encryption via alternate engines such as [SQLCipher](https://www.zetetic.net/sqlcipher/design)
or the [Official SEE extension](https://www.sqlite.org/see/doc/trunk/www/readme.wiki). Once you have either of those projects installed
on your system, use the following environment variables during compilation:

```bash
# tell exqlite that we wish to use some other sqlite installation. this will prevent sqlite3.c and friends from compiling
export EXQLITE_USE_SYSTEM=1

# Tell exqlite where to find the `sqlite3.h` file
export EXQLITE_SYSTEM_CFLAGS=-I/usr/local/include/sqlcipher

# tell exqlite which sqlite implementation to use
export EXQLITE_SYSTEM_LDFLAGS=-L/usr/local/lib -lsqlcipher
```

Once you have `exqlite` configured, you can use the `:key` option in the database config to enable encryption:

```elixir
config :exqlite, key: "super-secret'
```

## Usage

The `Exqlite.Sqlite3` module usage is fairly straight forward.

```elixir
# We'll just keep it in memory right now
{:ok, conn} = Exqlite.Sqlite3.open(":memory:")

# Create the table
:ok = Exqlite.Sqlite3.execute(conn, "create table test (id integer primary key, stuff text)")

# Prepare a statement
{:ok, statement} = Exqlite.Sqlite3.prepare(conn, "insert into test (stuff) values (?1)")
:ok = Exqlite.Sqlite3.bind(statement, ["Hello world"])

# Step is used to run statements
:done = Exqlite.Sqlite3.step(conn, statement)

# Prepare a select statement
{:ok, statement} = Exqlite.Sqlite3.prepare(conn, "select id, stuff from test")

# Get the results
{:row, [1, "Hello world"]} = Exqlite.Sqlite3.step(conn, statement)

# No more results
:done = Exqlite.Sqlite3.step(conn, statement)

# Release the statement.
#
# It is recommended you release the statement after using it to reclaim the memory
# asap, instead of letting the garbage collector eventually releasing the statement.
#
# If you are operating at a high load issuing thousands of statements, it would be
# possible to run out of memory or cause a lot of pressure on memory.
:ok = Exqlite.Sqlite3.release(conn, statement)
```

### Using SQLite3 native extensions

Exqlite supports loading [run-time loadable SQLite3 extensions](https://www.sqlite.org/loadext.html).
A selection of precompiled extensions for popular CPU types / architectures is
available by installing the [ExSqlean](https://github.com/mindreframer/ex_sqlean)
package. This package wraps [SQLean: all the missing SQLite functions](https://github.com/nalgeon/sqlean).

```elixir
alias Exqlite.Basic
{:ok, conn} = Basic.open("db.sqlite3")
:ok = Basic.enable_load_extension(conn)

# load the regexp extension - https://github.com/nalgeon/sqlean/blob/main/docs/re.md
Basic.load_extension(conn, ExSqlean.path_for("re"))

# run some queries to test the new `regexp_like` function
{:ok, [[1]], ["value"]} = Basic.exec(conn, "select regexp_like('the year is 2021', ?) as value", ["2021"]) |> Basic.rows()
{:ok, [[0]], ["value"]} = Basic.exec(conn, "select regexp_like('the year is 2021', ?) as value", ["2020"]) |> Basic.rows()

# prevent loading further extensions
:ok = Basic.disable_load_extension(conn)
{:error, %Exqlite.Error{message: "not authorized"}, _} = Basic.load_extension(conn, ExSqlean.path_for("re"))

# close connection
Basic.close(conn)
```

It is also possible to load extensions using the `Connection` configuration. For example:

```elixir
arch_dir =
  System.cmd("uname", ["-sm"])
  |> elem(0)
  |> String.trim()
  |> String.replace(" ", "-")
  |> String.downcase() # => "darwin-arm64"

config :myapp, arch_dir: arch_dir

# global
config :exqlite, load_extensions: [ "./priv/sqlite/\#{arch_dir}/rotate" ]

# per connection in a Phoenix app
config :myapp, Myapp.Repo,
  database: "path/to/db",
  load_extensions: [
    "./priv/sqlite/\#{arch_dir}/vector0",
    "./priv/sqlite/\#{arch_dir}/vss0"
  ]
```

See [Exqlite.Connection.connect/1](https://hexdocs.pm/exqlite/Exqlite.Connection.html#connect/1)
for more information. When using extensions for SQLite3, they must be compiled
for the environment you are targeting.

## Why SQLite3

I needed an Ecto3 adapter to store time series data for a personal project. I
didn't want to go through the hassle of trying to setup a postgres database or
mysql database when I was just wanting to explore data ingestion and some map
reduce problems.

I also noticed that other SQLite3 implementations didn't really fit my needs. At
some point I also wanted to use this with a nerves project on an embedded device
that would be resiliant to power outages and still maintain some state that
`ets` can not afford.


## Under The Hood

We are using the Dirty NIF scheduler to execute the sqlite calls. The rationale
behind this is that maintaining each sqlite's connection command pool is
complicated and error prone.


## Compiling NIF for Windows

When compiling on Windows, you will need the [Build Tools](https://visualstudio.microsoft.com/downloads/#build-tools-for-visual-studio-2022) or equivalent toolchain. Please make sure you have the correct environment variables, including path to compiler and linker and architecture that matches `erl.exe` (likely x64).

You may also need to invoke `vcvarsall.bat amd64` _before_ running `mix`.

A guide is available at [guides/windows.md](./guides/windows.md)

## Contributing

Feel free to check the project out and submit pull requests.

[ecto_sqlite3]: <https://github.com/elixir-sqlite/ecto_sqlite3>
