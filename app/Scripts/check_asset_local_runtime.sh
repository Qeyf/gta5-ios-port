#!/bin/bash
set -euo pipefail
set -x
cd "$(dirname "$0")/.."
scratch=$(mktemp -d "${TMPDIR:-/tmp}/gtav-asset-check.XXXXXX")
server_pid=''
cleanup() {
  if [ -n "$server_pid" ]; then kill "$server_pid" 2>/dev/null || true; wait "$server_pid" 2>/dev/null || true; fi
  rm -rf "$scratch"
}
trap cleanup EXIT
mkdir -p "$scratch/data" "$scratch/headers"
# The asset host needs only the public WASM runtime types; no game code or
# proprietary data is materialized by this test.
python3 - "$scratch/headers" <<'PY'
import pathlib, sys, urllib.request
root = pathlib.Path(sys.argv[1])
base = 'https://raw.githubusercontent.com/WebAssembly/wabt/1.0.42/wasm2c/'
for name in ('wasm-rt.h', 'wasm-rt-impl.h', 'wasm-rt-exceptions.h'):
    with urllib.request.urlopen(base + name, timeout=30) as response:
        (root / name).write_bytes(response.read())
(root / 'game.h').write_text('''#pragma once
#include "wasm-rt.h"
typedef uint32_t u32;
typedef uint64_t u64;
typedef struct { unsigned unused; } w2c_game;
struct w2c_env;
wasm_rt_shared_memory_t *w2c_env_memory(struct w2c_env *);
''')
PY
xcrun clang -std=c11 -O2 -fobjc-arc -fblocks -I Source -I "$scratch/headers" \
  Tests/asset_pipeline.m -framework Foundation -o "$scratch/asset-pipeline"
python3 Tests/asset_range_server.py "$scratch" "$scratch/port" &
server_pid=$!
for attempt in {1..300}; do
  [ -s "$scratch/port" ] && break
  kill -0 "$server_pid" 2>/dev/null || { echo 'Loopback asset fixture exited before becoming ready.' >&2; exit 1; }
  sleep 0.1
done
test -s "$scratch/port"
port=$(cat "$scratch/port")
PG_LOCAL_MIRROR="$scratch" PG_ASSET_TEST_SERVER="http://127.0.0.1:$port" "$scratch/asset-pipeline"
PG_LOCAL_MIRROR="$scratch" PG_ASSET_TEST_SERVER="http://127.0.0.1:$port" "$scratch/asset-pipeline" --balanced-asset-qos
