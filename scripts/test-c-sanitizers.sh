#!/bin/sh
# Run NIF tests with AddressSanitizer and UndefinedBehaviorSanitizer.
#
#   sh scripts/test-c-sanitizers.sh [mix test arguments...]
#
# Linux only. The build goes to _build/c-sanitizers. This script does not
# replace the NIF in the normal Mix tree. Do not ship the sanitizer build.
#
# With no arguments, this runs sqlite3_nif_test.exs, sqlite3_test.exs, and
# the tests tagged :sanitizer. mix test skips that tag unless you pass
# --include sanitizer.
set -eu

cd "$(dirname "$0")/.."
if [ "$(uname -s)" != Linux ]; then
  echo "This script runs only on Linux. Install Clang, compiler-rt, and LLVM." >&2
  exit 1
fi

export CC="${CLANG:-clang}"
target=$("$CC" -dumpmachine)
asan_runtime=$("$CC" -print-file-name="libclang_rt.asan-${target%%-*}.so")
if [ ! -f "$asan_runtime" ]; then
  echo "ASan runtime not found: $asan_runtime" >&2
  echo "Install libclang-rt-dev." >&2
  exit 1
fi
command -v llvm-symbolizer >/dev/null
export ASAN_SYMBOLIZER_PATH
ASAN_SYMBOLIZER_PATH=$(command -v llvm-symbolizer)

export MIX_ENV=test
export MIX_BUILD_PATH="$PWD/_build/c-sanitizers"
export SANITIZE=address,undefined
export DEBUG=1
# enif_alloc does not call malloc. ASan does not see those allocations.
export EXQLITE_DISABLE_ERLANG_ALLOCATOR=true
priv="$MIX_BUILD_PATH/lib/exqlite/priv"
if [ -L "$priv" ]; then
  echo "Refusing to build through a symlink: $priv" >&2
  exit 1
fi
mkdir -p "$priv"

# make rebuilds only when a source file is newer, so -B applies SANITIZE.
# Compile before LD_PRELOAD. clang must not start under ASan.
make -B MIX_APP_PATH="$MIX_BUILD_PATH/lib/exqlite"

# +Mea min turns off BEAM's pooled allocators. ASan tracks malloc and free.
export ERL_FLAGS="${ERL_FLAGS:-} +Mea min"
export LD_PRELOAD="$asan_runtime${LD_PRELOAD:+:$LD_PRELOAD}"
# detect_leaks=0. An uninstrumented BEAM reports leaks at exit.
# Those leaks are not in this NIF.
# halt_on_error=1. The first report aborts the process.
export ASAN_OPTIONS="${ASAN_OPTIONS:-detect_leaks=0}:halt_on_error=1"
export UBSAN_OPTIONS="${UBSAN_OPTIONS:-}:halt_on_error=1:print_stacktrace=1"

if [ "$#" -eq 0 ]; then
  set -- \
    test/exqlite/sqlite3_nif_test.exs \
    test/exqlite/sqlite3_test.exs \
    test/exqlite/sanitizer_test.exs \
    --include sanitizer
fi
mix compile --warnings-as-errors
# mix may be a shell shim. elixir -S mix compiles that shim and fails.
exec mix test --no-compile "$@"
