---
name: bump-and-release
description: >-
  Use when the user wants to bump the version (patch, minor, major, or specific version) and release leak-hunter, or runs "/bump-and-release [patch|minor|major] [version]". Coordinates synchronizing version numbers across Cargo.toml, Cargo.lock, package.json, package-lock.json, drafting CHANGELOG.md entries from unreleased commits, running all local verification suites (make check, release build, npm pack dry run), creating the conventional release commit, and publishing git tags for cargo-dist and npm GitHub Actions workflows.
---

# Bump and Release Skill for leak-hunter

This skill guides the agent through the end-to-end version bump and release procedure for `leak-hunter`.

## Core Invariants and Architecture

`leak-hunter` is a hybrid distribution consisting of:
1. **Rust core crate** (`Cargo.toml`, `Cargo.lock`)
2. **npm wrapper package** (`package.json`, `package-lock.json`)
3. **CI/CD distribution pipelines**:
   - Tag push (`vx.y.z`) triggers [release.yml](file:///.github/workflows/release.yml) (`cargo-dist 0.30.0`), which builds binaries across 4 targets (macOS arm64, macOS x64, Linux x64, Windows x64) and creates the GitHub Release with notes extracted from [CHANGELOG.md](file:///CHANGELOG.md).
   - Publishing the GitHub Release triggers [npm-publish.yml](file:///.github/workflows/npm-publish.yml), which uses [npm/prepublish-check.cjs](file:///npm/prepublish-check.cjs) to verify all 4 archives and checksums exist on GitHub before publishing to npm with provenance.

> [!CAUTION]
> **Strict Version Invariant**: [tests/npm_package.rs](file:///tests/npm_package.rs) strictly asserts that `CARGO_PKG_VERSION == package.json version == Cargo.toml version`. All version declarations must be kept in lockstep.
>
> **Never Publish Locally**: Do **not** run `npm publish` locally. `prepublishOnly` will fail because GitHub Release assets are not available yet. Publishing to npm is handled exclusively by GitHub Actions.

---

## Supported Inputs

The user may invoke this workflow using commands such as:
- `/bump-and-release patch version` or `/bump-and-release patch`
- `/bump-and-release minor version` or `/bump-and-release minor`
- `/bump-and-release major version` or `/bump-and-release major`
- `/bump-and-release 0.5.4` or `/bump-and-release v0.5.4`

Parse the argument to identify the bump type (`patch`, `minor`, `major`) or explicit semver target.

---

## Workflow Steps

### Step 1: Pre-flight Inspection

1. **Verify working directory is clean**:
   ```bash
   git status
   ```
   Ensure there are no uncommitted unrelated changes before starting.
2. **Check current branch**:
   Confirm on `main` branch.
3. **Identify unreleased commits**:
   ```bash
   PREV_TAG="$(git describe --tags --abbrev=0 2>/dev/null || echo 'v0.0.0')"
   git log "${PREV_TAG}..HEAD" --oneline
   ```
   Verify that there are commits to release. If none exist, notify the user.

---

### Step 2: Version Synchronization (4 Manifest & Lock Files)

Use the bundled helper script to safely bump and synchronize `package.json`, `package-lock.json`, `Cargo.toml`, and `Cargo.lock`:

```bash
./.agents/skills/bump-and-release/scripts/bump-version.sh <patch|minor|major|x.y.z>
```

The script automatically:
1. Increments version in `package.json` and `package-lock.json` via `npm version ... --no-git-tag-version`.
2. Updates `version = "..."` under `[package]` in `Cargo.toml`.
3. Runs `cargo check --quiet` to update `Cargo.lock`.
4. Verifies all 4 files contain the exact same new version.

---

### Step 3: Update CHANGELOG.md

1. Read the unreleased commits between the previous tag and `HEAD`:
   ```bash
   git log "${PREV_TAG}..HEAD" --oneline
   ```
2. Open [CHANGELOG.md](file:///CHANGELOG.md) and prepend a new section above the previous version section following [Keep a Changelog 1.1.0](https://keepachangelog.com/en/1.1.0/):
   ```markdown
   ## [X.Y.Z] - YYYY-MM-DD

   ### Fixed

   - Description of fix 1...
   - Description of fix 2...

   ### Added (if any)

   - Description of new feature...
   ```
3. Use concise English bullet points describing user-facing behavior, detections, or platform changes.

---

### Step 4: Mandatory Local Verification

Run the full local validation suite to guarantee zero breakage before committing:

```bash
# 1. Check code formatting, run Rust unit & integration tests, and npm tests
make check

# 2. Verify release build succeeds
cargo build --release

# 3. Check npm package tarball contents
npm pack --dry-run
```

All 3 commands must exit with code 0.

---

### Step 5: Create Release Commit

Stage the 5 synchronized files:
```bash
git add Cargo.toml Cargo.lock package.json package-lock.json CHANGELOG.md
```

Follow the project commit rules in [AGENTS.md](file:///AGENTS.md):
- Conventional Commits 1.0.0 format: `chore(release): 準備 <NEW_VERSION> 發布`
- Body in Traditional Chinese (`zh-tw`), separated by real newlines.
- Detail what was synchronized, summary of changelog entries, and verification results.

Example commit command:
```bash
git commit -m "chore(release): 準備 ${NEW_VERSION} 發布" -m "同步 Rust crate、npm package 與兩份 lockfile 的版本為 ${NEW_VERSION}，確保 cargo-dist、GitHub Release 與 npm wrapper 使用相同版本。

在 changelog 記錄本次變更內容摘要。

驗證：make check、cargo build --release、npm pack --dry-run。"
```

---

### Step 6: Create Git Tag and Push

1. Create a lightweight git tag matching the cargo-dist release tag pattern (`vX.Y.Z`):
   ```bash
   git tag "v${NEW_VERSION}"
   ```
2. Push commits and the tag to GitHub:
   ```bash
   git push origin main
   git push origin "v${NEW_VERSION}"
   ```

---

### Step 7: Post-Release CI/CD Verification

Inform the user about the automated downstream pipelines:
1. **GitHub Actions `Release` workflow** will start automatically upon pushing `v${NEW_VERSION}`:
   - `cargo-dist` builds binaries on GitHub runners:
     - `aarch64-apple-darwin` (macOS 15 Apple Silicon)
     - `x86_64-apple-darwin` (macOS 15 Intel)
     - `x86_64-unknown-linux-gnu` (Linux x64)
     - `x86_64-pc-windows-msvc` (Windows x64)
   - Generates checksums (`.sha256`) and installers (`.sh`, `.ps1`).
   - Automatically parses `CHANGELOG.md` for section `## [X.Y.Z]` and creates the official GitHub Release.
2. **GitHub Actions `Publish npm` workflow**:
   - Triggers as soon as the GitHub Release is published.
   - Waits for release assets via `npm/prepublish-check.cjs`.
   - Publishes `leak-hunter@${NEW_VERSION}` to npm with OIDC Trusted Publishing and provenance.
