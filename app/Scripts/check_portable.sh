#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."

checks_dir="${PG_PORTABLE_BUILD_DIR:-$PWD/app/Build/PortableChecks}"
mkdir -p "$checks_dir"

python3 app/Tests/localization_resources.py
python3 -m unittest discover -s app/Tests -p '*.py'
node --test diagnostics/worker.test.mjs

for test in cheat_input loading_state engine_configuration native_bc_layout upscaling_dimensions; do
  cc -std=c11 -O2 -Wall -Wextra -Werror -pthread -Iapp/Source \
    "app/Tests/$test.c" -o "$checks_dir/$test"
  "$checks_dir/$test"
done

for test in render_lifecycle frame_upload_cache frame_timing frame_rate; do
  c++ -std=c++17 -O2 -Wall -Wextra -Werror -pthread -Iapp/Source \
    "app/Tests/$test.cpp" -o "$checks_dir/$test"
  "$checks_dir/$test"
done

echo 'PASS: portable production regressions.'
echo 'Apple SDK compilation, Metal GPU execution and IPA creation were NOT run by this script.'
