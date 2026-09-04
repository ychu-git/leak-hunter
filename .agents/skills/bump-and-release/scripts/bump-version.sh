#!/usr/bin/env bash
set -euo pipefail

# bump-version.sh: Synchronize version across package.json, package-lock.json, Cargo.toml, and Cargo.lock.
# Usage:
#   bump-version.sh patch
#   bump-version.sh minor
#   bump-version.sh major
#   bump-version.sh 0.5.4

PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || (cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd))"
cd "$PROJECT_ROOT"

if [ $# -lt 1 ]; then
  echo "Usage: $0 <patch|minor|major|x.y.z>"
  exit 1
fi

BUMP_ARG="$1"
# Normalize "patch version" -> "patch"
case "$BUMP_ARG" in
  "patch version") BUMP_ARG="patch" ;;
  "minor version") BUMP_ARG="minor" ;;
  "major version") BUMP_ARG="major" ;;
esac

OLD_VERSION="$(node -p "require('./package.json').version")"
echo "==> Current version: ${OLD_VERSION}"

# 1. Update package.json and package-lock.json using npm version
NEW_TAG="$(npm version "$BUMP_ARG" --no-git-tag-version)"
NEW_VERSION="${NEW_TAG#v}"
echo "==> Bumped to: ${NEW_VERSION}"

# 2. Update Cargo.toml
node -e '
const fs = require("fs");
const file = "Cargo.toml";
const content = fs.readFileSync(file, "utf8");
const newVer = process.argv[1];
const updated = content.replace(
  /(\[package\][\s\S]*?^version\s*=\s*)"[^"]+"/m,
  `$1"${newVer}"`
);
fs.writeFileSync(file, updated, "utf8");
' "$NEW_VERSION"

# 3. Update Cargo.lock via cargo check
cargo check --quiet

# 4. Verify synchronization across all files
CARGO_TOML_VER="$(node -e '
const fs = require("fs");
const match = fs.readFileSync("Cargo.toml", "utf8").match(/\[package\][\s\S]*?^version\s*=\s*"([^"]+)"/m);
console.log(match ? match[1] : "");
')"
CARGO_LOCK_VER="$(node -e '
const fs = require("fs");
const match = fs.readFileSync("Cargo.lock", "utf8").match(/\[\[package\]\]\s+name\s*=\s*"leak-hunter"\s+version\s*=\s*"([^"]+)"/m);
console.log(match ? match[1] : "");
')"
PKG_JSON_VER="$(node -p "require('./package.json').version")"
PKG_LOCK_VER="$(node -p "require('./package-lock.json').version")"

echo "==> Verification:"
echo "    Cargo.toml:        ${CARGO_TOML_VER}"
echo "    Cargo.lock:        ${CARGO_LOCK_VER}"
echo "    package.json:      ${PKG_JSON_VER}"
echo "    package-lock.json: ${PKG_LOCK_VER}"

if [ "$CARGO_TOML_VER" != "$NEW_VERSION" ] || \
   [ "$CARGO_LOCK_VER" != "$NEW_VERSION" ] || \
   [ "$PKG_JSON_VER" != "$NEW_VERSION" ] || \
   [ "$PKG_LOCK_VER" != "$NEW_VERSION" ]; then
  echo "ERROR: Version mismatch detected!"
  exit 1
fi

echo "==> Successfully synchronized version to ${NEW_VERSION}."
echo ""
echo "Next steps for release:"
echo "  1. Add '## [${NEW_VERSION}] - $(date +%Y-%m-%d)' section to CHANGELOG.md"
echo "  2. Run 'make check' and 'npm pack --dry-run'"
echo "  3. Commit changes: git commit -m 'chore(release): 準備 ${NEW_VERSION} 發布'"
echo "  4. Tag release: git tag v${NEW_VERSION}"
echo "  5. Push: git push origin main && git push origin v${NEW_VERSION}"
