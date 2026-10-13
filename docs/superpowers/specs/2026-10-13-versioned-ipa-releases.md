# Versioned GtaV Mobile IPA releases

The user requests an IPA build and a detailed repository Release after every successful build. Device game assets stay on the device; compilation still needs the supported engine, manifest and all 18 shader packs for game build `8b0b5899ed`.

Preserve the public source fork and the existing private-only full-build requirement. The existing `Qeyf/muguet-ios-game-build` repository already holds the user's engine/manifest/index input ZIP. Add a separate GtaV Mobile orchestration workflow there, pinned to the source commit; preserve its existing input release. A reusable source workflow also supports existing private template copies, website uploads and Tailscale.

Use marketing version `1.3.2` and base build `8` in Xcode build settings. Each caller workflow run increments the base by its run number and appends its retry attempt, e.g. `9.1`, `9.2`, `10.1`. Read the packaged Info.plist for publication metadata. Release tags use `v<version>-build.<build>`; keep previous tags and releases. Publish only after input validation, native compilation, signature/resource checks and IPA metadata validation all succeed.

Attach `GtaV Mobile.ipa`, `release-metadata.json`, `SHA256SUMS` and bilingual `release-notes.md`. Include source commit, run link, build/version, bundle identifier, minimum iOS version, languages, file size, SHA-256, toolchain and ad-hoc signing status. Do not claim that compilation verifies gameplay or a physical device.

Input ZIP handling must map recognized files to fixed paths, bound decompression, reject conflicting duplicates and validate pack sizes. An iPhone shader-folder ZIP may repeat an identical index.json from the baseline ZIP. Missing inputs must fail before the macOS build starts.
