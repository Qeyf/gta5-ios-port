#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
bash app/Scripts/require_apple_host.sh
mkdir -p app/Build/UIVerification/objects app/Build/UIVerification/strings app/Build/UIVerification/resources
(
  cd app/Build/UIVerification/objects
  xcrun --sdk iphoneos swiftc -c -parse-as-library -swift-version 5 \
    -sdk "$(xcrun --sdk iphoneos --show-sdk-path)" -target arm64-apple-ios17.0 \
    -import-objc-header ../../../Source/Native-Bridging-Header.h \
    -Xcc -I../../../Source -Xcc -I../../../App/GameInstaller \
    -emit-localized-strings -emit-localized-strings-path ../strings \
    ../../../App/*.swift ../../../App/GameInstaller/*.swift
)
for catalog in app/App/*.xcstrings; do
  xcrun xcstringstool compile --output-directory app/Build/UIVerification/resources "$catalog"
done
python3 app/Scripts/check_extracted_localizations.py app/Build/UIVerification/strings
