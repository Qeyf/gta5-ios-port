# Local builds with nektos/act

This workflow runs on your own host and consumes no GitHub Actions minutes.
`act` does not supply macOS or Xcode on Linux. A successful portable check is
not an Apple compilation, GPU test or IPA build.

## Portable checks on Linux or macOS

Install the official `nektos/act` binary, a C/C++ compiler, Python 3, Node.js
and Git. From the repository root:

```sh
act workflow_dispatch -W .github/workflows/local-checks.yml -j portable \
  -P ubuntu-latest=-self-hosted --no-cache-server --action-offline-mode \
  --env-file /dev/null --secret-file /dev/null --var-file /dev/null --input-file /dev/null
```

This compiles and runs the production C/C++ regressions, checks both language
catalogs, and runs Python and diagnostic-relay tests. Docker is unnecessary in
this host mode. The script explicitly lists Apple checks as not run.

## Apple tests and IPA on an Apple Silicon Mac

Requirements: a configured Xcode 27 or later, the iOS SDK, Metal compiler,
`xcodegen`, the portable-check dependencies above, and a real MetalFX/BC-capable
GPU. Use `xcode-select` or `DEVELOPER_DIR` to select the intended Xcode.

Run the Apple graphics and UI compilation checks separately:

```sh
act workflow_dispatch -W .github/workflows/local-checks.yml -j apple \
  -P macos-latest=-self-hosted --no-cache-server --action-offline-mode \
  --env-file /dev/null --secret-file /dev/null --var-file /dev/null --input-file /dev/null
```

The GPU tests execute the actual renderer, BC copies/readbacks and official
MetalFX/MPS kernels with the Metal validation layer. An unsupported GPU returns
77 and blocks this local build; it does not count as a pass. UIKit source and
String Catalogs compile with the selected iOS SDK. To additionally launch the
EN/TR UI smoke test, install an iOS 27 simulator runtime and run:

```sh
bash app/Scripts/verify_ui_launch.sh
```

To run both prerequisites and create the IPA, supply your own build-input
folder. It must contain `data/manifest.json`,
`b/8b0b5899ed/game.wasm`, and the complete indexed shader packs under
`b/8b0b5899ed/shaders/`. Runtime data can remain on the iPhone.

```sh
act workflow_dispatch -W .github/workflows/local-checks.yml -j ipa \
  -P ubuntu-latest=-self-hosted -P macos-latest=-self-hosted \
  --input 'mirror=/absolute/path/to/game-folder' --input build_number=17.1 \
  --no-cache-server --action-offline-mode \
  --env-file /dev/null --secret-file /dev/null --var-file /dev/null --input-file /dev/null
```

The IPA job uses the existing `build_ipa.sh`, verifies the ad-hoc signature and
prints the archive SHA-256. Output: `GtaV Mobile.ipa`. It must be re-signed for
installation. Build 17.1 is the proposed first local 1.3.8 build; increment the
build input for each subsequent package.

For post-build native-engine checks, the build prepares the required toolchain:

```sh
bash app/Scripts/check_runtime.sh
```

The existing private hosted build workflow retains automatic versioned Release
publication. This local recipe stops at a verified IPA; private publication can
follow a successful Mac build. Never invent a hosted run ID for local metadata
or publish an archive from a failed/skipped Apple build.

## Current verification record

On 2026-10-16 the development changes were checked on Linux x86_64 with official
`act` 0.2.89. Portable checks passed. The IPA attempt stopped at the Apple-host
preflight with exit 78: macOS/Xcode unavailable. No 1.3.8 IPA or Release was
created. Real Apple compilation, Metal execution and sustained device FPS
remain unverified.

References:

- https://nektosact.com/usage/runners.html
- https://nektosact.com/installation/index.html
- https://developer.apple.com/xcode/system-requirements
