#!/bin/sh
# Package build/ into dist/ for a release: deterministic zip of the Mac app, the Windows
# installer and mod DLL, SHA256SUMS.txt and build-info.txt (exact tool versions, so anyone
# can rebuild and compare checksums).
set -eu
cd "$(dirname "$0")/.."
VERSION=$(cat VERSION)
rm -rf dist && mkdir -p dist

# Fixed timestamps, sorted entries and no extra attributes make the zip byte-identical
# across builds of the same source with the same tools.
STAGE=build/stage
rm -rf "$STAGE" && mkdir -p "$STAGE"
cp -R "build/Warcraft I for Mac.app" "$STAGE/"
find "$STAGE" -exec touch -h -t 200001010000 {} +
find "$STAGE" -type f -exec chmod 644 {} + && chmod 755 "$STAGE/Warcraft I for Mac.app/Contents/MacOS/W1RMac"
find "$STAGE" -type d -exec chmod 755 {} +
(cd "$STAGE" && find "Warcraft I for Mac.app" | LC_ALL=C sort | TZ=UTC zip -X -q -D -@ "../../dist/Warcraft-I-for-Mac.zip")
rm -rf "$STAGE"

cp build/W1R-Mods-Installer.exe dist/
cp build/VERSION.dll dist/VERSION.dll

{
  echo "Warcraft I: Remastered mods $VERSION"
  echo "commit: $(git rev-parse HEAD 2>/dev/null || echo unknown)"
  echo "macOS: $(sw_vers -productVersion) ($(uname -m))"
  echo "clang: $(clang --version | head -1)"
  echo "lld: $(lld-link --version | head -1)"
  echo "swiftc: $(swiftc --version 2>&1 | head -1)"
} > dist/build-info.txt

(cd dist && shasum -a 256 Warcraft-I-for-Mac.zip W1R-Mods-Installer.exe VERSION.dll > SHA256SUMS.txt)
cat dist/SHA256SUMS.txt
