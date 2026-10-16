#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
bash app/Scripts/require_apple_host.sh
checks_dir="$PWD/app/Build/AppleGraphicsChecks"
mkdir -p "$checks_dir" app/Build/UIVerification/launch
python3 - <<'PY'
import hashlib,pathlib,urllib.request
p=pathlib.Path('app/Tools/bcdec/bcdec.h')
p.parent.mkdir(parents=True,exist_ok=True)
expected='134520764d96f70a27db814173616c89ad85db95fbd3328417c7a8c77e7ca189'
if not p.is_file() or hashlib.sha256(p.read_bytes()).hexdigest()!=expected:
    with urllib.request.urlopen('https://raw.githubusercontent.com/iOrange/bcdec/80859ed3b7afb1c527a2a99d70c61457bea72d0c/bcdec.h',timeout=30) as r:p.write_bytes(r.read())
assert hashlib.sha256(p.read_bytes()).hexdigest()==expected,'Pinned BC decoder checksum mismatch'
PY
xcrun clang -std=c11 -O2 -mmacosx-version-min=14.0 \
  -c app/Source/BCTextureDecoder.c -o "$checks_dir/bc-decoder.o"
xcrun clang++ -std=c++20 -O1 -fobjc-arc -fblocks -mmacosx-version-min=14.0 \
  -Iapp/Source -Iapp/Source/MetalRenderer app/Tests/native_bc_metal.mm \
  app/Source/MetalRenderer/MRShaders.mm app/Source/MetalRenderer/MRSpatialUpscaler.mm "$checks_dir/bc-decoder.o" \
  -framework Foundation -framework Metal -framework MetalFX -framework MetalPerformanceShaders \
  -framework QuartzCore -framework CoreGraphics -framework ImageIO -framework UniformTypeIdentifiers \
  -o "$checks_dir/native-bc-metal"
xcrun clang++ -std=c++20 -O2 -fobjc-arc -fblocks -mmacosx-version-min=14.0 \
  app/Tests/spatial_scaler_metal.mm app/Source/MetalRenderer/MRSpatialUpscaler.mm \
  -framework Foundation -framework Metal -framework MetalFX -framework MetalPerformanceShaders \
  -o "$checks_dir/spatial-scaler-metal"
skipped=0
for test in native-bc-metal spatial-scaler-metal; do
  status=0
  MTL_DEBUG_LAYER=1 "$checks_dir/$test" > "app/Build/UIVerification/launch/$test.log" 2>&1 || status=$?
  cat "app/Build/UIVerification/launch/$test.log"
  if [[ "$status" == 77 ]]; then skipped=1
  elif [[ "$status" != 0 ]]; then exit "$status"; fi
done
if [[ "$skipped" == 1 ]]; then
  echo 'SKIPPED: at least one real Metal GPU test could not run; this is not a GPU pass.'
  exit 77
fi
echo 'PASS: real BC memory/copy/readback and Apple MetalFX/MPS GPU regressions.'
