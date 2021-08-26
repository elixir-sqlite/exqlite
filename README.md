# Exqlite

[![Build Status](https://github.com/elixir-sqlite/exqlite/workflows/CI/badge.svg)](https://github.com/elixir-sqlite/exqlite/actions)
[![Hex Package](https://img.shields.io/hexpm/v/exqlite.svg)](https://hex.pm/packages/exqlite)
[![Hex Docs](https://img.shields.io/badge/hex-docs-blue.svg)](https://hexdocs.pm/exqlite)

An Elixir SQLite3 library.

If you are looking for the Ecto adapater, take a look at the
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


## Installation

```elixir
defp deps do
  {:exqlite, "~> 0.6.2"}
end
```


## Configuration

```elixir
config :exqlite, default_chunk_size: 100
```

* `default_chunk_size` - The chunk size that is used when multi-stepping when
  not specifying the chunk size explicitly.


## Usage

The `Exqlite.Sqlite3` module usage is fairly straight forward.

```elixir
# We'll just keep it in memory right now
{:ok, conn} = Exqlite.Sqlite3.open(":memory:")

# Create the table
:ok = Exqlite.Sqlite3.execute(conn, "create table test (id integer primary key, stuff text)");

# Prepare a statement
{:ok, statement} = Exqlite.Sqlite3.prepare(conn, "insert into test (stuff) values (?1)")
:ok = Exqlite.Sqlite3.bind(conn, statement, ["Hello world"])

# Step is used to run statements
:done = Exqlite.Sqlite3.step(conn, statement)

# Prepare a select statement
{:ok, statement} = Exqlite.Sqlite3.prepare(conn, "select id, stuff from test");

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


## Contributing

Feel free to check the project out and submit pull requests.

[ecto_sqlite3]: <https://github.com/elixir-sqlite/ecto_sqlite3>
