defmodule Exqlite.TypeExtension do
  @moduledoc """
  A behaviour that defines the API for extensions providing custom data loaders and dumpers
  for Ecto schemas.
  """

  @doc """
  Takes a value and convers it to data suitable for storage in the database.
  """
  @callback convert(value :: term) :: term
end
