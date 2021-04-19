defmodule Exqlite.ErrorTest do
  use ExUnit.Case
  alias Exqlite.Error

  describe "message/1" do
    test "with :statement" do
      assert "a\nb" == Exception.message(%Error{message: "a", statement: "b"})
    end

    test "without :statement" do
      assert "a" == Exception.message(%Error{message: "a"})
    end
  end
end
