#!/bin/bash
# Launch the production Swift shell, without materializing the game engine.
# Removing the scene manifest/delegate must make this fail on an iOS 27 runtime.
set -euo pipefail

app_root=$(cd "$(dirname "$0")/.." && pwd)
output="$app_root/Build/UIVerification/launch"
mkdir -p "$output"

if ! command -v xcrun >/dev/null || [ "$(uname -m)" != arm64 ]; then
  echo 'UI launch verification requires an Apple Silicon Mac with Xcode 27.' >&2
  exit 1
fi

scratch=$(mktemp -d "${TMPDIR:-/tmp}/gtav-ui-smoke.XXXXXX")
simulator_id=''
data_container=''
cleanup() {
  local status=$?
  trap - EXIT INT TERM
  set +e
  if [ -n "$data_container" ] && [ -f "$data_container/Documents/native-port.log" ]; then
    cp "$data_container/Documents/native-port.log" "$output/last-native-port.log"
  fi
  if [ -n "$simulator_id" ]; then
    xcrun simctl shutdown "$simulator_id" >/dev/null 2>&1
    xcrun simctl delete "$simulator_id" >/dev/null 2>&1
  fi
  rm -rf "$scratch"
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

sdk=$(xcrun --sdk iphonesimulator --show-sdk-path)
sdk_version=$(xcrun --sdk iphonesimulator --show-sdk-version)
if [ "${sdk_version%%.*}" -lt 27 ]; then
  echo 'The simulator UI smoke test requires the iOS 27 SDK or later.' >&2
  exit 1
fi
xcodebuild -version > "$output/toolchain.log"
printf 'Simulator SDK: %s\n' "$sdk_version" >> "$output/toolchain.log"

bundle_id='io.github.qeyf.gtavmobile'
module_name='GtaVMobileUISmoke'
app_bundle="$scratch/GtaV Mobile.app"
archive_dir="$app_root/Vendor/libarchive.xcframework/ios-arm64-simulator"
mkdir -p "$app_bundle"

# Compile the real archive shim; only engine-facing C functions are replaced.
xcrun --sdk iphonesimulator clang -std=c11 -target arm64-apple-ios17.0-simulator \
  -isysroot "$sdk" -I"$archive_dir/Headers" \
  -c "$app_root/App/GameInstaller/GameInstallerShim.c" -o "$scratch/installer.o" \
  > "$output/build.log" 2>&1
xcrun --sdk iphonesimulator clang -std=c11 -target arm64-apple-ios17.0-simulator \
  -isysroot "$sdk" -DPG_UI_SMOKE_TEST=1 -I"$app_root/Source" \
  -c "$app_root/Tests/UISmokeBridge.c" -o "$scratch/engine-stubs.o" \
  >> "$output/build.log" 2>&1
xcrun --sdk iphonesimulator swiftc -emit-executable -parse-as-library \
  -swift-version 5 -module-name "$module_name" -sdk "$sdk" \
  -target arm64-apple-ios17.0-simulator \
  -import-objc-header "$app_root/Source/Native-Bridging-Header.h" \
  -Xcc -I"$app_root/Source" -Xcc -I"$app_root/App/GameInstaller" \
  "$app_root"/App/*.swift "$app_root"/App/GameInstaller/*.swift \
  "$scratch/installer.o" "$scratch/engine-stubs.o" "$archive_dir/libarchive.a" \
  -framework UIKit -framework Metal -framework MetalKit -framework QuartzCore \
  -framework GameController -framework AVFAudio -framework CoreMotion \
  -framework WebKit -framework UniformTypeIdentifiers -lz -lbz2 -liconv \
  -o "$app_bundle/$module_name" >> "$output/build.log" 2>&1

# Use the shipped plist, including its scene manifest, with build variables resolved.
python3 - "$app_root" "$app_bundle" "$bundle_id" "$module_name" "$sdk_version" <<'PY'
import pathlib, plistlib, re, sys
root, bundle = map(pathlib.Path, sys.argv[1:3])
project = (root / 'project.yml').read_text()
values = {
    'DEVELOPMENT_LANGUAGE': 'en',
    'EXECUTABLE_NAME': sys.argv[4],
    'PRODUCT_MODULE_NAME': sys.argv[4],
    'PRODUCT_BUNDLE_IDENTIFIER': sys.argv[3],
    'PRODUCT_NAME': 'GtaV Mobile',
}
for key in ('MARKETING_VERSION', 'CURRENT_PROJECT_VERSION'):
    match = re.search(r'^\s*' + key + r':\s*"([0-9.]+)"\s*$', project, re.M)
    if not match:
        raise SystemExit(f'Cannot resolve {key} from project.yml')
    values[key] = match.group(1)
def resolve(value):
    if isinstance(value, dict):
        return {key: resolve(item) for key, item in value.items()}
    if isinstance(value, list):
        return [resolve(item) for item in value]
    if isinstance(value, str):
        for key, item in values.items():
            value = value.replace(f'$({key})', item)
        if '$(' in value:
            raise SystemExit(f'Unresolved Info.plist build variable: {value}')
    return value
with (root / 'App/Info.plist').open('rb') as source:
    info = resolve(plistlib.load(source))
info.update(MinimumOSVersion='17.0', CFBundleSupportedPlatforms=['iPhoneSimulator'],
            DTPlatformName='iphonesimulator', DTSDKName='iphonesimulator' + sys.argv[5])
with (bundle / 'Info.plist').open('wb') as destination:
    plistlib.dump(info, destination)
PY

for catalog in "$app_root"/App/*.xcstrings; do
  xcrun xcstringstool compile --output-directory "$app_bundle" "$catalog" \
    >> "$output/build.log" 2>&1
done
for language in en tr; do
  test -s "$app_bundle/$language.lproj/Main.strings"
  test -s "$app_bundle/$language.lproj/Cheats.strings"
done
xcrun actool "$app_root/App/Assets.xcassets" --compile "$app_bundle" \
  --platform iphonesimulator --minimum-deployment-target 17.0 \
  --target-device iphone --target-device ipad --app-icon AppIcon \
  --output-partial-info-plist "$scratch/assets-info.plist" \
  >> "$output/build.log" 2>&1
python3 - "$app_bundle/Info.plist" "$scratch/assets-info.plist" <<'PY'
import pathlib, plistlib, sys
path = pathlib.Path(sys.argv[1])
info = plistlib.loads(path.read_bytes())
info.update(plistlib.loads(pathlib.Path(sys.argv[2]).read_bytes()))
path.write_bytes(plistlib.dumps(info))
PY
cp "$app_root"/Resources/ControlIcons/*.png "$app_bundle/"
codesign --force --sign - "$app_bundle" >> "$output/build.log" 2>&1

# Read installed inventory. Never launch or erase a pre-existing simulator.
xcrun simctl list --json > "$output/simulators.json"
IFS=$'\t' read -r runtime_id device_type_id < <(python3 - "$output/simulators.json" <<'PY'
import json, pathlib, re, sys
inventory = json.loads(pathlib.Path(sys.argv[1]).read_text())
def version(text):
    return tuple(int(piece) for piece in re.findall(r'\d+', text))
runtimes = [item for item in inventory['runtimes']
            if item.get('isAvailable') and item.get('name', '').startswith('iOS ')
            and version(item['version'])[0] == 27]
if not runtimes:
    raise SystemExit('No installed, available iOS 27 simulator runtime. Install one on the CI runner.')
runtime = max(runtimes, key=lambda item: version(item['version']))
types = {item['identifier']: item for item in inventory['devicetypes']}
supported = {item['identifier'] for item in runtime.get('supportedDeviceTypes', [])}
if not supported:
    supported = {item['deviceTypeIdentifier']
                 for item in inventory.get('devices', {}).get(runtime['identifier'], [])
                 if item.get('isAvailable') and 'deviceTypeIdentifier' in item}
if not supported:
    parts = (version(runtime['version']) + (0, 0))[:3]
    encoded = (parts[0] << 16) | (parts[1] << 8) | parts[2]
    supported = {key for key, item in types.items()
                 if item.get('minRuntimeVersion', 0) <= encoded <= item.get('maxRuntimeVersion', 0xffffffff)}
phones = [types[key] for key in supported if key in types and types[key]['name'].startswith('iPhone ')]
if not phones:
    raise SystemExit('No installed iPhone device type supports the selected iOS 27 runtime.')
phone = max(phones, key=lambda item: (version(item['name']), 'Pro' in item['name'], item['name']))
print(runtime['identifier'] + '\t' + phone['identifier'])
PY
)
test -n "$runtime_id"
test -n "$device_type_id"
simulator_id=$(xcrun simctl create "GtaV UI smoke $(uuidgen)" "$device_type_id" "$runtime_id")
printf 'Runtime: %s\nDevice type: %s\n' "$runtime_id" "$device_type_id" >> "$output/toolchain.log"
xcrun simctl boot "$simulator_id"
xcrun simctl bootstatus "$simulator_id" -b > "$output/boot.log" 2>&1
xcrun simctl install "$simulator_id" "$app_bundle"
data_container=$(xcrun simctl get_app_container "$simulator_id" "$bundle_id" data)

launch_and_check() {
  local name=$1 language=$2 launch_output app_pid attempt status
  shift 2
  launch_output=$(xcrun simctl launch --terminate-running-process "$simulator_id" \
    "$bundle_id" -AppleLanguages "($language)" "$@")
  printf '%s\n' "$launch_output" > "$output/$name-launch.log"
  app_pid=${launch_output##*: }
  if ! [[ "$app_pid" =~ ^[0-9]+$ ]]; then
    echo 'simctl launch did not return an app PID.' >&2
    return 1
  fi
  for attempt in {1..10}; do
    sleep 1
    if ! kill -0 "$app_pid" 2>/dev/null; then
      echo "The app exited during $name launch verification." >&2
      return 1
    fi
    status=$(ps -p "$app_pid" -o stat=)
    if [ -z "$status" ] || [[ "$status" == *Z* ]]; then
      echo "The app crashed during $name launch verification." >&2
      return 1
    fi
  done
  python3 - "$data_container/Documents/native-port.log" <<'PY'
import pathlib, sys
path = pathlib.Path(sys.argv[1])
log = path.read_text() if path.exists() else ''
if 'Native UIKit + Metal host.' not in log or 'Metal device:' not in log:
    raise SystemExit('The real NativePortViewController did not finish creating the app shell.')
PY
  cp "$data_container/Documents/native-port.log" "$output/$name-native-port.log"
  xcrun simctl io "$simulator_id" screenshot "$output/$name.png" \
    >> "$output/$name-launch.log" 2>&1
  echo "Verified $name: app remains running and the real UIKit shell rendered."
}

launch_and_check en-home en
launch_and_check tr-home tr
launch_and_check en-settings en --open-settings
launch_and_check tr-cheats tr --open-cheats
