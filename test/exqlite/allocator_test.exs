defmodule Exqlite.AllocatorTest do
  use ExUnit.Case

  test "erlang allocator is used by default" do
    assert Application.get_env(:exqlite, :disable_erlang_allocator) == nil
    assert Exqlite.Sqlite3NIF.erlang_allocator_enabled()
  end
end
