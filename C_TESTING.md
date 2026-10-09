# Checking the C NIF

`mix test` covers the Elixir API. These checks cover `c_src/sqlite3_nif.c`. A clean run does not prove SQL, transaction, or SQLite correctness.

## Strict warnings and static analysis

Install Clang and Erlang/OTP (including `erl_nif.h`), then run:

```sh
make c-check
```

This checks `c_src/sqlite3_nif.c` with `-Wall -Wextra -Wformat=2 -Wshadow -Werror`, then runs Clang Static Analyzer. Compiler warnings and analyzer findings both fail the command. The vendored SQLite amalgamation is not checked. `CLANG=clang-18 make c-check` selects a particular Clang. `ERTS_INCLUDE_DIR` overrides the detected OTP headers.

NIF and SQLite callback signatures keep unused parameters, so that warning is disabled. `-DNDEBUG` also compiles out `assert()` uses of those parameters.

The `c-check` CI job runs this on every pull request and push to main. It does not fetch Mix dependencies, and it does not change the normal build.

## ASan and UBSan (Linux)

On Ubuntu/Debian, install `clang`, `libclang-rt-dev`, and `llvm`, plus the usual Elixir/OTP, Make, and C build tools:

```sh
mix deps.get
sh scripts/test-c-sanitizers.sh
```

The runner:

- Force-builds the NIF and bundled SQLite with AddressSanitizer and UndefinedBehaviorSanitizer, debug symbols, and frame pointers. A report fails the run rather than letting undefined behavior continue.
- Uses `_build/c-sanitizers`, so the normal dev and test NIFs stay untouched.
- Preloads the matching Clang ASan runtime before BEAM starts, including during Elixir compilation, when the NIF `on_load` can run.
- Uses LLVM's symbolizer for source locations.
- Passes `+Mea min` to BEAM so its optional pooling allocators stay off. More allocations then go through the system allocator that ASan tracks.
- Disables Exqlite's SQLite Erlang allocator (`EXQLITE_DISABLE_ERLANG_ALLOCATOR=true`) for the same reason.
- Runs the NIF lifecycle tests, the low-level SQLite3 tests, and the busy-handler tests tagged `:sanitizer`. Normal `mix test` skips that tag.

Pass Mix test arguments to select different tests:

```sh
sh scripts/test-c-sanitizers.sh test/exqlite/sqlite3_nif_test.exs --seed 0
```

The `c-sanitizers` CI job uses the same runner. On macOS, use a Linux container or CI. The runner does not guess Darwin's runtime-loading requirements. Do not ship the instrumented NIF.

### What a clean run does not establish

Stock BEAM is not sanitizer-instrumented. NIF resource headers, remaining VM allocators, and paths the tests do not hit still limit coverage. The lifecycle tests exercise process exit, garbage collection, explicit cleanup, cross-process resource ownership, binary and integer boundaries, concurrent use of one connection, and reuse after a failed statement. They are not allocation-failure injection tests, and they are not a leak measurement.

LeakSanitizer is off by default (`detect_leaks=0`). A stock BEAM process reports leaks at exit that are not an Exqlite-only signal. To investigate:

```sh
ASAN_OPTIONS=detect_leaks=1 sh scripts/test-c-sanitizers.sh test/exqlite/sqlite3_nif_test.exs
```

Attribute a finding before you add a suppression. A dedicated leak runner, or Valgrind with an OTP build configured for it, is follow-up work. The current CI jobs do not provide that.
