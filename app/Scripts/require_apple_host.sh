#!/usr/bin/env bash
set -euo pipefail
if [[ "$(uname -s)" != Darwin ]]; then
  echo 'ERROR: Apple SDK/Metal/IPA steps require macOS with Xcode. act does not supply macOS on Linux.' >&2
  exit 78
fi
for tool in xcodebuild xcrun; do
  command -v "$tool" >/dev/null || { echo "ERROR: missing Apple tool: $tool" >&2; exit 78; }
done
if [[ "${1:-}" == --arm64 && "$(uname -m)" != arm64 ]]; then
  echo 'ERROR: this engine build toolchain requires an Apple Silicon Mac.' >&2
  exit 78
fi
xcodebuild -version
xcrun --sdk iphoneos --show-sdk-version
