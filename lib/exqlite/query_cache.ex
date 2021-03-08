defmodule Exqlite.QueryCache do
  @type t() :: any()
  @type reason() :: atom() | String.t()
  @type options() :: Keyword.t()

  @doc """
  Constructs a new cache.
  """
  @callback new(options) :: t()

  @doc """
  Puts a query into the cache.
  """
  @callback put(t(), Query.t()) :: {:ok, t()} | {:error, reason()}

  @doc """
  Gets a query reference stored.
  """
  @callback get(t(), Query.t()) :: {:ok, Query.t() | nil} | {:error, reason()}

  @doc """
  Deletes a query from the cache.
  """
  @callback delete(t(), Query.t()) :: {:ok, t()} | {:error, reason()}

  @doc """
  Destroys the cache.
  """
  @callback destroy(t()) :: :ok

  @doc """
  Clears the query cache.
  """
  @callback clear(t()) :: {:ok, t()} | {:error, reason()}

  @doc """
  Get the number of queries in the cache.
  """
  @callback size(t()) :: integer()
end


defmodule Exqlite.VoidQueryCache do
  @moduledoc """
  A query cache that does not cache anything.
  """

  @behaviour Exqlite.QueryCache

  @impl true
  def new(_ \\ []), do: :void

  @impl true
  def put(cache, _), do: {:ok, cache}

  @impl true
  def destroy(_cache), do: :ok

  @impl true
  def delete(cache, _), do: {:ok, cache}

  @impl true
  def get(_cache, _), do: {:ok, nil}

  @impl true
  def clear(cache), do: {:ok, cache}

  @impl true
  def size(_cache), do: 0
end


defmodule Exqlite.ETSQueryCache do
  @moduledoc """
  The interface to manage cached prepared queries.
  """

  @behaviour Exqlite.QueryCache

  alias Exqlite.Query

  defstruct [:queries, :timestamps, :limit]

  @type t() :: %__MODULE__{
          queries: ETS.Set.t(),
          timestamps: ETS.Set.t(),
          limit: integer()
        }

  @doc """
  Constructs a new prepared query cache with the specified limit. The cache uses
  a least recently used caching mechanism.
  """
  @impl true
  def new(options \\ []) do
    with limit <- Keyword.get(options, :limit, 50),
         {:ok, queries} <- ETS.Set.new(protection: :public),
         {:ok, timestamps} <- ETS.Set.new(ordered: true, protection: :public) do
      %__MODULE__{
        queries: queries,
        timestamps: timestamps,
        limit: limit
      }
    end
  end

  @impl true
  def put(cache, %Query{name: ""}), do: {:ok, cache}

  @impl true
  def put(cache, %Query{name: nil}), do: {:ok, cache}

  @impl true
  def put(cache, %Query{ref: nil}), do: {:ok, cache}

  @impl true
  def put(cache, %Query{name: query_name, ref: ref, statement: statement} = q) do
    with timestamp <- current_timestamp(),
         {:ok, timestamps} <- ETS.Set.put(cache.timestamps, {timestamp, query_name}),
         {:ok, queries} <- ETS.Set.put(cache.queries, {query_name, timestamp, statement, ref}) do
      clean(%{cache | timestamps: timestamps, queries: queries})
    end
  end

  @impl true
  def destroy(nil), do: :ok

  @doc """
  Completely delete the cache.
  """
  @impl true
  def destroy(cache) do
    with {:ok, _} <- ETS.Set.delete(cache.queries),
         {:ok, _} <- ETS.Set.delete(cache.timestamps) do
      :ok
    end
  end

  @impl true
  def delete(cache, %Query{name: nil}), do: {:ok, cache}

  @impl true
  def delete(cache, %Query{name: ""}), do: {:ok, cache}

  @impl true
  def delete(cache, %Query{name: query_name}) do
    with {:ok, {_, timestamp, _, _}} <- ETS.Set.get(cache.queries, query_name),
         {:ok, timestamps} <- ETS.Set.delete(cache.timestamps, timestamp),
         {:ok, queries} <- ETS.Set.delete(cache.queries, query_name) do
      {:ok, %{cache | timestamps: timestamps, queries: queries}}
    end
  end

  @impl true
  def get(_cache, %Query{name: nil}), do: {:ok, nil}

  @impl true
  def get(_cache, %Query{name: ""}), do: {:ok, nil}

  @doc """
  Gets an existing prepared query if it exists. Otherwise `nil` is returned.
  """
  @impl true
  def get(cache, %Query{name: query_name} = query) do
    with {:ok, {_, timestamp, statement, ref}} <- ETS.Set.get(cache.queries, query_name),
         {:ok, _} <- ETS.Set.delete(cache.timestamps, timestamp),
         timestamp <- current_timestamp(),
         {:ok, _} <- ETS.Set.put(cache.timestamps, {timestamp, query_name}),
         {:ok, _} <- ETS.Set.put(cache.queries, {query_name, timestamp, statement, ref}) do
      {:ok, %{query | ref: ref, statement: statement}}
    else
      {:ok, nil} -> {:ok, nil}
      {:error, reason} -> {:error, reason}
      _ -> {:error, :unknown_error}
    end
  end

  @doc """
  Clears all of the cached prepared statements.
  """
  @impl true
  def clear(cache) do
    with {:ok, queries} <- ETS.Set.delete_all(cache.queries),
         {:ok, timestamps} <- ETS.Set.delete_all(cache.timestamps) do
      {:ok, %{cache | queries: queries, timestamps: timestamps}}
    end
  end

  @impl true
  def size(cache) do
    case ETS.Set.info(cache.queries, true) do
      {:ok, info} -> Keyword.get(info, :size, 0)
      _ -> 0
    end
  end

  ##
  ## Helpers
  ##

  defp current_timestamp(), do: :erlang.unique_integer([:monotonic])

  defp clean(cache) do
    if size(cache) > cache.limit do
      with {:ok, timestamp} <- ETS.Set.first(cache.timestamps),
           {:ok, {_, query_name}} <- ETS.Set.get(cache.timestamps, timestamp),
           {:ok, timestamps} <- ETS.Set.delete(cache.timestamps, timestamp),
           {:ok, queries} <- ETS.Set.delete(cache.queries, query_name) do
        {:ok, %{cache | timestamps: timestamps, queries: queries}}
      else
        {:ok, nil} -> {:ok, cache}
        _ -> {:ok, cache}
      end
    else
      {:ok, cache}
    end
  end
end
