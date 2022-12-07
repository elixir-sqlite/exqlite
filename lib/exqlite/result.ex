defmodule Exqlite.Result do
  @moduledoc """
  The database results.
  """

  @type t :: %__MODULE__{
          command: atom,
          columns: [String.t()] | nil,
          rows: [[term] | term] | nil,
          num_rows: integer()
        }

  defstruct command: nil, columns: [], rows: [], num_rows: 0

  def new(options) do
    %__MODULE__{
      command: Keyword.get(options, :command),
      columns: Keyword.get(options, :columns, []),
      rows: Keyword.get(options, :rows, []),
      num_rows: Keyword.get(options, :num_rows, 0)
    }
  end
end

if Code.ensure_loaded?(Table.Reader) do
  defimpl Table.Reader, for: Exqlite.Result do
    def init(%{columns: columns}) when columns in [nil, []] do
      {:rows, %{columns: []}, []}
    end

    def init(result) do
      {:rows, %{columns: result.columns}, result.rows}
    end
  end
end
