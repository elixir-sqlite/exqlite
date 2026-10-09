#!/bin/sh
# Run NIF tests with AddressSanitizer and UndefinedBehaviorSanitizer.
#
#   sh scripts/test-c-sanitizers.sh [mix test arguments...]
#
# Linux only. The build goes to _build/c-sanitizers. This script does not
# replace the NIF in the normal Mix tree. Do not ship the sanitizer build.
#
# With no arguments, this runs the full test/ suite. test/test_helper.exs
# excludes :sanitizer and :slow_test. This script includes both. Arguments
# replace that default, so a subset that needs those tags must include them.
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

# Compile before LD_PRELOAD. clang must not start under ASan.
# -B is required when flags change: make would otherwise keep objects built
# without SANITIZE. A stamp records the flags and sources. CI restores this
# tree with older mtimes than the checkout, so a match also touches the NIF
# outputs. Otherwise make rebuilds sqlite3.c because the sources look newer.
nif_dir="$MIX_BUILD_PATH/lib/exqlite"
stamp="$nif_dir/sanitizer-stamp"
stamp_inputs=$(mktemp)
{
  printf 'sanitize=%s\n' "$SANITIZE"
  printf 'debug=%s\n' "${DEBUG:-}"
  printf 'allocator=%s\n' "$EXQLITE_DISABLE_ERLANG_ALLOCATOR"
  printf 'use_system=%s\n' "${EXQLITE_USE_SYSTEM:-}"
  printf 'system_cflags=%s\n' "${EXQLITE_SYSTEM_CFLAGS:-}"
  printf 'system_ldflags=%s\n' "${EXQLITE_SYSTEM_LDFLAGS:-}"
  printf 'cc=%s\n' "$CC"
  $CC --version
  $CC -dumpmachine
  erl -noshell -eval 'io:format("~s", [erlang:system_info(system_version)]), halt().'
  printf '\n'
  sha256sum Makefile scripts/test-c-sanitizers.sh c_src/*
} > "$stamp_inputs"
sanitizer_stamp=$(sha256sum "$stamp_inputs" | awk '{print $1}')
rm -f "$stamp_inputs"

if [ -f "$stamp" ] && [ "$(cat "$stamp")" = "$sanitizer_stamp" ] &&
  [ -f "$priv/sqlite3_nif.so" ] && [ -f "$nif_dir/obj/sqlite3.o" ] &&
  [ -f "$nif_dir/obj/sqlite3_nif.o" ]; then
  echo "Sanitizer NIF is up to date."
  touch "$nif_dir/obj/sqlite3.o" "$nif_dir/obj/sqlite3_nif.o" "$priv/sqlite3_nif.so"
  if [ -f "$nif_dir/obj/sqlite3.d" ]; then
    touch "$nif_dir/obj/sqlite3.d"
  fi
  if [ -f "$nif_dir/obj/sqlite3_nif.d" ]; then
    touch "$nif_dir/obj/sqlite3_nif.d"
  fi
else
  make -B MIX_APP_PATH="$nif_dir"
  printf '%s\n' "$sanitizer_stamp" > "$stamp"
fi

# +Mea min turns off BEAM's pooled allocators. ASan tracks malloc and free.
export ERL_FLAGS="${ERL_FLAGS:-} +Mea min"
export LD_PRELOAD="$asan_runtime${LD_PRELOAD:+:$LD_PRELOAD}"
# detect_leaks=0. An uninstrumented BEAM reports leaks at exit.
# Those leaks are not in this NIF.
# halt_on_error=1. The first report aborts the process.
export ASAN_OPTIONS="${ASAN_OPTIONS:-detect_leaks=0}:halt_on_error=1"
export UBSAN_OPTIONS="${UBSAN_OPTIONS:-}:halt_on_error=1:print_stacktrace=1"

if [ "$#" -eq 0 ]; then
  set -- --include sanitizer --include slow_test
fi
mix compile --warnings-as-errors
# mix may be a shell shim. elixir -S mix compiles that shim and fails.
exec mix test --no-compile "$@"
