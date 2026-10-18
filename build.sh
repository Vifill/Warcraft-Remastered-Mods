#!/bin/sh
# Build everything into dist/. Needs: clang (Xcode command line tools), lld (brew install lld),
# swiftc (Xcode command line tools), python3.
set -eu
cd "$(dirname "$0")"
VERSION=$(cat VERSION)
B=build
mkdir -p "$B/obj" dist

CFLAGS="-target i386-pc-windows-msvc -O2 -ffreestanding -fno-builtin -fno-stack-protector
  -mno-stack-arg-probe -fno-asynchronous-unwind-tables -Wall -Wextra -DMOD_VERSION=\"$VERSION\""

echo "== import libraries"
[ -f "$B/lib/kernel32.lib" ] || python3 tools/mkimplib.py "$B/lib"

echo "== mod DLL (VERSION.dll)"
clang $CFLAGS -c mod/w1r_mods.c -o "$B/obj/w1r_mods.obj"
clang -target i386-pc-windows-msvc -c mod/handlers.s -o "$B/obj/handlers.obj"
lld-link /brepro /dll /nodefaultlib /safeseh:no /machine:x86 /entry:DllMain /def:mod/version.def \
  /out:"$B/VERSION.dll" "$B/obj/w1r_mods.obj" "$B/obj/handlers.obj" \
  "$B/lib/kernel32.lib" "$B/lib/user32.lib"
rm -f "$B/VERSION.lib" "$B/VERSION.exp"

if [ -f windows/installer.c ]; then
  echo "== Windows installer"
  python3 tools/embed.py "$B/VERSION.dll" mod_dll > "$B/obj/mod_dll.h"
  clang $CFLAGS -I"$B/obj" -Iwindows -c windows/installer.c -o "$B/obj/installer.obj"
  lld-link /brepro /subsystem:windows /nodefaultlib /safeseh:no /machine:x86 /entry:start \
    /out:"$B/W1R-Mods-Installer.exe" "$B/obj/installer.obj" \
    "$B/lib/kernel32.lib" "$B/lib/user32.lib" "$B/lib/advapi32.lib" "$B/lib/shell32.lib" \
    "$B/lib/gdi32.lib" "$B/lib/ole32.lib"
fi

if [ -f mac/build_app.sh ]; then
  echo "== Mac app"
  sh mac/build_app.sh "$B" "$VERSION"
fi
echo "done"
