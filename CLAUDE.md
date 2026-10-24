# Warcraft I: Remastered — Mac support and mods

Fan project: run Warcraft I: Remastered on Apple Silicon Macs via Wine, and mod the game
(Mac and Windows). Private repo `Vifill/warcraft1-remastered-mods`. See `README.md` for users and
**`docs/NOTES.md` for every game address, data structure and finding** — read it before modding.

## Layout
- `mod/` — the mods: a stand-in `VERSION.dll` (C + asm). It forwards all 17 real VERSION.dll
  exports, then ~8 s after launch patches the running game in memory (never on disk: the game
  checks its own exe). Each patch site is verified byte for byte; mismatch = that mod is skipped.
  Settings `w1r_mods.ini`, log `w1r_mods.log`, both next to `Warcraft.exe`.
- `windows/installer.c` — Win32 installer exe (embeds the DLL, checkboxes, finds the game).
- `mac/W1RMac.swift` — SwiftUI app: downloads Sikarugir Wine engine + wrapper + WineMetalGL
  (pinned SHA-256), builds the bottle, sets registry overrides, runs the Battle.net installer,
  keeps saves outside the bottle (`~/Library/Application Support/Warcraft1Mac Saves`, linked in),
  offers to import saves from other Wine setups. `mac/sync_mods.sh` copies mod files into the
  game folder while Wine runs. `--list-saves` prints save diagnostics.
- `tools/` — `mkimplib.py` (Windows import libs without the SDK), `embed.py`, `package.sh`.
- `.github/workflows/release.yml` — on a `v*` tag: build on macos-15, package, SHA256SUMS,
  build-provenance attestation (works once the repo is public), publish the release.

## Building
- Mac: Xcode command line tools, `brew install lld`, python3. `./build.sh` then
  `sh tools/package.sh`. Builds are reproducible (`/brepro`, deterministic zip).
- Windows: the code is plain C/asm for clang + lld-link (i386-pc-windows-msvc, no CRT, no SDK);
  `build.sh` needs a POSIX shell (Git Bash) and LLVM for Windows (`clang`, `lld-link`) + python.
  The Mac app part only builds on a Mac. In Git Bash set `MSYS2_ARG_CONV_EXCL='*'` (else lld-link
  `/flags` are turned into paths) and put `C:Program Fileslvmbin` on path.

## Conventions
- Game addresses are VAs at base 0x400000; always go through `REL()` (ASLR on Windows).
- Hooks: 5-byte `jmp` to a handler in `mod/handlers.s`, which replays the replaced instructions
  and jumps back via a pointer set in `w1r_mods.c`. Add the expected original bytes for every site.
- No C runtime: avoid things that emit memset/memcpy calls; keep `/brepro`.
- Commit messages: plain, no attribution lines.

## Status (2026-10-24)
Done and tested in game (Mac): ghost-unit crash fix, middle-mouse panning, A* pathfinding (incl.
arrival fix), mod DLL, Windows installer UI (under Wine), Mac app full install, save migration.

Open:
1. Test the GitHub-built zip as a new user would (quarantined download). macOS 15+ removed
   "right-click → Open" for unsigned apps: users must click **Open Anyway** in System Settings →
   Privacy & Security. Update the README Mac steps accordingly.
2. Test the GitHub-built `VERSION.dll` in game (log should show all three mods `installed`).
3. Warcraft II: works on Mac with the same WineMetalGL override for `Warcraft II.exe` (set by hand
   on the dev Mac; confirm it starts). Add WC2 support to the Mac app (overrides + DLL copy +
   sync_mods for the WC2 folder).
4. Warcraft II mods: middle_mouse_pan done and tested (Windows), see the W2 part of NOTES.md.
   Next candidates: tile grid, pathfinder. It is 32-bit, imports VERSION.dll and ClientSdk.dll,
   has ASLR; W1 addresses do not apply. On Windows, x64dbg /
   Cheat Engine make finding them easy.
5. Release: bump `VERSION`, update `RELEASE_NOTES.md`, `git tag v1.0.0 && git push --tags`.
   Repo is private; making it public enables attestations.
