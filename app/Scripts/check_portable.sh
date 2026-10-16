#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."

checks_dir="${PG_PORTABLE_BUILD_DIR:-$PWD/app/Build/PortableChecks}"
mkdir -p "$checks_dir"

python3 app/Tests/localization_resources.py
python3 -m unittest discover -s app/Tests -p '*.py'
node --test diagnostics/worker.test.mjs

python3 app/Scripts/fetch_bcdec.py
cc -std=c11 -O2 -Wall -Wextra -Werror -Wno-unused-function \
  -c app/Source/BCTextureDecoder.c -o "$checks_dir/bc-decoder.o"
for test in bc45_precision bc_textures; do
  cc -std=c11 -D_POSIX_C_SOURCE=200809L -O2 -Wall -Wextra -Werror \
    "app/Tests/$test.c" "$checks_dir/bc-decoder.o" -o "$checks_dir/$test"
  "$checks_dir/$test"
done

for test in cheat_input loading_state engine_configuration native_bc_layout upscaling_dimensions; do
  cc -std=c11 -O2 -Wall -Wextra -Werror -pthread -Iapp/Source \
    "app/Tests/$test.c" -o "$checks_dir/$test"
  "$checks_dir/$test"
done

for test in render_lifecycle frame_upload_cache frame_timing frame_rate pipeline_inputs pipeline_warmup bc_sample_comparison; do
  c++ -std=c++17 -O2 -Wall -Wextra -Werror -pthread -Iapp/Source \
    "app/Tests/$test.cpp" -o "$checks_dir/$test"
  "$checks_dir/$test"
done

echo 'PASS: portable production regressions.'
echo 'Apple SDK compilation, Metal GPU execution and IPA creation were NOT run by this script.'
