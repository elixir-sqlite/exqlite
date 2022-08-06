defmodule Mix.Tasks.DownloadSqlite do
  @moduledoc false

  use Mix.Task

  @shortdoc "Downloads the SQLite amalgamation version specified in mix.exs"
  def run(_args) do
    version = Exqlite.MixProject.sqlite_version() |> tarball_version()
    System.cmd("sh", ["-c", "VERSION=#{version} bin/download_sqlite.sh"])
  end

  defp tarball_version(semantic_version) do
    [major, minor, patch] = String.split(semantic_version, ".")
    minor = String.pad_leading(minor, 2, "0")
    patch = String.pad_leading(patch, 2, "0")

    major <> minor <> patch <> "00"
  end
end
