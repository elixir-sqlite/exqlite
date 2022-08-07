defmodule Exqlite.Flags do
  @moduledoc false

  import Bitwise

  # https://www.sqlite.org/c3ref/c_open_autoproxy.html
  @file_open_flags [
    sqlite_open_readonly: 0x00000001,
    sqlite_open_readwrite: 0x00000002,
    sqlite_open_create: 0x00000004,
    sqlite_open_deleteonclos: 0x00000008,
    sqlite_open_exclusive: 0x00000010,
    sqlite_open_autoproxy: 0x00000020,
    sqlite_open_uri: 0x00000040,
    sqlite_open_memory: 0x00000080,
    sqlite_open_main_db: 0x00000100,
    sqlite_open_temp_db: 0x00000200,
    sqlite_open_transient_db: 0x00000400,
    sqlite_open_main_journal: 0x00000800,
    sqlite_open_temp_journal: 0x00001000,
    sqlite_open_subjournal: 0x00002000,
    sqlite_open_super_journal: 0x00004000,
    sqlite_open_nomutex: 0x00008000,
    sqlite_open_fullmutex: 0x00010000,
    sqlite_open_sharedcache: 0x00020000,
    sqlite_open_privatecache: 0x00040000,
    sqlite_open_wal: 0x00080000,
    sqlite_open_nofollow: 0x01000000,
    sqlite_open_exrescode: 0x02000000
  ]

  def put_file_open_flags(current_flags \\ 0, flags) do
    Enum.reduce(flags, current_flags, &(&2 ||| Keyword.fetch!(@file_open_flags, &1)))
  end
end
