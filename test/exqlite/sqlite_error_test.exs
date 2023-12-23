defmodule Exqlite.SQLiteErrorTest do
  use ExUnit.Case, async: true
  alias Exqlite.SQLiteError

  describe "message/1" do
    test "with :statement" do
      assert "a: b" == Exception.message(%SQLiteError{message: "a", statement: "b"})
    end

    test "without :statement" do
      assert "a" == Exception.message(%SQLiteError{message: "a"})
    end
  end
end
