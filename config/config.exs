import Config

if config_env() == :test do
  disable_erlang_allocator =
    case System.get_env("EXQLITE_DISABLE_ERLANG_ALLOCATOR") do
      nil -> false
      value -> String.downcase(value) in ~w(true 1)
    end

  config :exqlite, disable_erlang_allocator: disable_erlang_allocator
end
