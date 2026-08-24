defmodule Exqlite.AllocatorTest do
  use ExUnit.Case

  test "erlang allocator respects configuration" do
    disabled = Application.get_env(:exqlite, :disable_erlang_allocator, false)

    assert is_boolean(disabled)
    assert Exqlite.Sqlite3NIF.erlang_allocator_enabled() == not disabled
  end
end
