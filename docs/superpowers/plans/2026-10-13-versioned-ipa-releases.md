# Versioned IPA Releases Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox syntax for tracking.

**Goal:** Produce and publish each successful GtaV Mobile IPA with unique version metadata and retained release history.

**Architecture:** Validate private inputs on Linux, then compile the exact source commit on an Apple Silicon runner. A reusable source workflow publishes verified IPA releases in its private caller repository; the existing private input repository invokes it.

**Tech Stack:** Python standard library, unittest, XcodeGen, Xcode, GitHub Actions and gh.

**Spec:** `docs/superpowers/specs/2026-10-13-versioned-ipa-releases.md`

## Global Constraints

- App `GtaV Mobile`, bundle `io.github.qeyf.gtavmobile`, iOS 17+, English/Turkish native UI.
- Version `1.3.2`, base build `8`; publish packaged values.
- Full builds and proprietary input artifacts remain private; retain existing releases.
- Missing shader packs block compilation; no placeholder IPA or gameplay claims.
- No new Python dependencies or engine execution in metadata tests.

## Review Focus

- Retry builds receive different tags and retain their source commit.
- Corrupt/truncated shader packages fail before macOS tool installation.
- A normal iPhone shaders ZIP repeats index.json without conflicting data.
- A second app, missing executable or unresolved plist placeholder blocks publication.
- Caller/source repositories differ; token, run URL and release target belong to the caller, source metadata belongs to the checkout.

### Task 1: Packaged release metadata

**Files:** `app/Scripts/create_release_metadata.py`, `app/Tests/release_metadata.py`.
**Interface:** CLI `--ipa --output --commit --run-id --run-url --signing adhoc`, optional toolchain and `--github-output`; emits tag/title/version/build plus JSON, checksums and bilingual notes.

- [x] Write and observe failing synthetic IPA tests for valid metadata and invalid package/identity/version/hash inputs.
- [x] Implement the stdlib CLI; derive metadata from the packaged plist and reject invalid inputs without modifying output.
- [x] Run `python3 app/Tests/release_metadata.py`; 15 tests pass, including separate source/caller provenance.

### Task 2: Private archive staging

**Files:** `app/Scripts/stage_release_inputs.py`, `app/Tests/release_inputs.py`, `app/Scripts/check_game_files.py`.
**Interface:** CLI `--archive --out`, optional `--shaders-archive`; constructs a minimal mirror for the existing strict game checker.

- [x] Observe failing ZIP fixtures for safe mapping, duplicate/conflicting entries, size bounds and truncated packs.
- [x] Implement fixed-path, bounded validation-before-publication and pack-size validation without native rename bindings.
- [x] Run `python3 app/Tests/release_inputs.py`; 24 tests pass. The real pinned index references 18 packs totaling 71,761,794 bytes.

### Task 3: Build/release orchestration and integration

**Files:** `.github/workflows/build-ipa.yml`, `.github/workflows/verify-ui.yml`, `build_ipa.sh`, `app/project.yml`, `app/App/Info.plist`, README files and changelog; private caller `.github/workflows/gtav-mobile-build.yml`.
**Interface:** Reusable workflow accepts input mode/archive checksums/source repository/ref. Linux preflight emits exact source SHA and validated inputs; macOS consumes those artifacts, passes build override to Xcode and publishes metadata only after actual build checks.

- [x] Set Xcode version substitutions and optional `GTV_BUILD_NUMBER` override, preserving normal Mac defaults.
- [x] Replace mutable latest-ipa releases with unique verified tags and complete release assets; retain original input-artifact provenance on failed-job retries.
- [x] Run Python fixtures, shell syntax and actionlint; 42 tests pass and fresh whole-branch/final input reviews report no remaining Important/Critical findings.
- [ ] Publish source changes and run real macOS Swift/catalog verification.
- [ ] Install the source-pinned private caller and dispatch its preflight. If all user inputs exist, monitor the full build and verify the published IPA; otherwise report exact missing inputs and keep the same workflow ready.
