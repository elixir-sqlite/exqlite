defmodule Exqlite.QueryCacheTest do
  use ExUnit.Case

  alias Exqlite.ETSQueryCache
  alias Exqlite.Query

  describe ".put/2" do
    test "does not store an unnamed query" do
      cache = ETSQueryCache.new()
      query = %Query{name: nil}

      {:ok, cache} = ETSQueryCache.put(cache, query)

      assert ETSQueryCache.size(cache) == 0
    end

    test "does not store an empty named query" do
      cache = ETSQueryCache.new()
      query = %Query{name: "", ref: make_ref()}

      {:ok, cache} = ETSQueryCache.put(cache, query)

      assert ETSQueryCache.size(cache) == 0
    end

    test "does not store a named query with no ref" do
      cache = ETSQueryCache.new()
      query = %Query{name: "", ref: nil}

      {:ok, cache} = ETSQueryCache.put(cache, query)

      assert ETSQueryCache.size(cache) == 0
    end

    test "stores a named query" do
      cache = ETSQueryCache.new()
      query = %Query{name: "myquery", ref: make_ref()}

      {:ok, cache} = ETSQueryCache.put(cache, query)

      assert ETSQueryCache.size(cache) == 1
    end

    test "stores named query in only one cache" do
      cache1 = ETSQueryCache.new()
      cache2 = ETSQueryCache.new()
      query = %Query{name: "myquery", ref: make_ref()}

      {:ok, cache1} = ETSQueryCache.put(cache1, query)

      assert ETSQueryCache.size(cache1) == 1
      assert ETSQueryCache.size(cache2) == 0
    end
  end

  describe ".get/2" do
    test "returns nil when query is unnamed" do
      cache = ETSQueryCache.new()
      query = %Query{name: nil, ref: make_ref()}
      ETSQueryCache.put(cache, query)

      {:ok, nil} = ETSQueryCache.get(cache, query)
    end

    test "returns nil when query has a blank name" do
      cache = ETSQueryCache.new()
      query = %Query{name: "", ref: make_ref()}
      ETSQueryCache.put(cache, query)

      {:ok, nil} = ETSQueryCache.get(cache, query)
    end

    test "returns the stored named query" do
      cache = ETSQueryCache.new()
      existing = %Query{name: "myquery", ref: make_ref()}
      {:ok, cache} = ETSQueryCache.put(cache, existing)

      {:ok, found} = ETSQueryCache.get(cache, %Query{name: "myquery", ref: nil})

      assert found.ref == existing.ref
    end
  end

  describe ".delete/2" do
    test "returns error for unnamed query" do
      cache = ETSQueryCache.new()
      ETSQueryCache.put(cache, %Query{name: "myquery", ref: make_ref()})

      {:ok, cache} = ETSQueryCache.delete(cache, %Query{name: nil})

      assert ETSQueryCache.size(cache) == 1
    end

    test "returns error for a blank named query" do
      cache = ETSQueryCache.new()
      ETSQueryCache.put(cache, %Query{name: "myquery", ref: make_ref()})

      {:ok, cache} = ETSQueryCache.delete(cache, %Query{name: ""})

      assert ETSQueryCache.size(cache) == 1
    end

    test "deletes the named query" do
      cache = ETSQueryCache.new()
      ETSQueryCache.put(cache, %Query{name: "myquery", ref: make_ref()})

      {:ok, cache} = ETSQueryCache.delete(cache, %Query{name: "myquery"})

      assert ETSQueryCache.size(cache) == 0
    end
  end

  describe ".clear/1" do
    test "clears an empty cache" do
      cache = ETSQueryCache.new()

      {:ok, cache} = ETSQueryCache.clear(cache)

      assert ETSQueryCache.size(cache) == 0
    end

    test "clears a populated cache" do
      cache = ETSQueryCache.new()
      existing = %Query{name: "myquery", ref: make_ref()}
      ETSQueryCache.put(cache, existing)

      {:ok, _} = ETSQueryCache.clear(cache)

      assert ETSQueryCache.size(cache) == 0
    end
  end

  describe ".size/1" do
    test "returns 0 for an empty cache" do
      cache = ETSQueryCache.new()
      assert ETSQueryCache.size(cache) == 0
    end

    test "returns 1" do
      cache = ETSQueryCache.new()
      existing = %Query{name: "myquery", ref: make_ref()}
      ETSQueryCache.put(cache, existing)

      assert ETSQueryCache.size(cache) == 1
    end
  end
end
