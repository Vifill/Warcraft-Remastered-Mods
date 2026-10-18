# Warcraft I: Remastered — Mac support and mods

Play **Warcraft I: Remastered** on Apple Silicon Macs, plus three optional mods for Mac and Windows:

| Mod | What it does |
|---|---|
| **Crash fix** | Fixes a crash a few seconds after loading some saves (map tiles that still claim a unit that no longer exists). |
| **Middle-mouse panning** | Hold the middle mouse button (scroll wheel) and drag to move the map. |
| **Smarter pathfinding** | Units plan routes with A* instead of the original "walk straight, then hug the wall" logic, so they stop getting stuck behind forests and walls. Falls back to the original when a target can't be reached. |

Unofficial, made by fans. Not affiliated with or endorsed by Blizzard Entertainment. You need your own Battle.net account and a copy of Warcraft I: Remastered.

## Mac

Requires an Apple Silicon Mac on macOS 14 or later, and about 3 GB of free space.

1. Download **Warcraft-I-for-Mac.zip** from [Releases](../../releases) and unzip it.
2. Move **Warcraft I for Mac** to Applications. The first time, **right-click it → Open → Open** (the app isn't notarized by Apple, so macOS asks once).
3. Pick your mods and click **Install**. It downloads free Wine and graphics support (about 300 MB, checksums verified) and starts the Battle.net installer.
4. In Battle.net: sign in, install **Warcraft I: Remastered**, and click **Play**.

Next time, open **Warcraft I for Mac** and click **Play**. Changes to the mod checkboxes apply the next time the game starts.

**How it works:** the app sets up a free Wine environment built from CrossOver's open-source code ([Sikarugir](https://github.com/Sikarugir-App)), which runs 32-bit Windows programs like Battle.net and the game correctly on Apple Silicon. It adds [WineMetalGL](https://github.com/metalsharp/WineMetalGL) because the game needs OpenGL 4.6, which macOS doesn't provide, sets `SDL_AUDIODRIVER=directsound` to avoid crackling audio, and installs the mods. Everything lives in `~/Library/Application Support/Warcraft1Mac`; **More → Uninstall** removes it.

## Windows

1. Download **W1R-Mods-Installer.exe** from [Releases](../../releases).
2. Run it. It finds the game (or click **Browse…**), pick your mods, click **Install**.
3. Start the game from Battle.net as usual.

Run the installer again to change mods or to **Uninstall**. If the game is in Program Files and installing fails, run the installer as administrator.

## Settings

Mods are configured in `w1r_mods.ini` next to `Warcraft.exe` (the apps write it for you):

```ini
[mods]
enabled=1
ghost_fix=1
middle_mouse_pan=1
pan_speed_percent=100   ; 10-500
pathfinding=astar       ; or "original"
patch_delay_ms=8000
```

`w1r_mods.log` in the same folder shows which mods switched on.

## How the mods work

The mods are a small stand-in `VERSION.dll` placed next to `Warcraft.exe`. It forwards all real `VERSION.dll` calls to Windows, and a few seconds after the game starts (after its own startup self-check) it patches the running game in memory. **No game files are changed.** Each patch site is checked byte for byte first; if the game was updated and the code no longer matches, that mod stays off and the game runs normally.

Written for game build **1.0.0.2762**.

## Verify your download

Releases are built by [GitHub Actions](.github/workflows/release.yml) from the tagged source, not on anyone's computer.

**1. Check the checksum.** Each release has `SHA256SUMS.txt`. In the folder with your downloads:

```sh
shasum -a 256 -c SHA256SUMS.txt --ignore-missing
```

On Windows (PowerShell): `Get-FileHash W1R-Mods-Installer.exe` and compare with `SHA256SUMS.txt`.

**2. Check where it was built.** GitHub signs a build attestation for every release file, proving it was built by this repository's workflow from a specific commit. With the [GitHub CLI](https://cli.github.com):

```sh
gh attestation verify Warcraft-I-for-Mac.zip --repo Vifill/warcraft1-remastered-mods
```

**3. Rebuild it yourself (optional).** Builds are reproducible: the same source and tool versions give byte-identical files. `build-info.txt` in each release lists the commit and tool versions used. Check out that commit and run:

```sh
./build.sh && sh tools/package.sh
```

`dist/SHA256SUMS.txt` should match the release. (The Mac app also depends on the exact Xcode version; the Windows files only on clang and lld.)

## Troubleshooting

- **Mods don't switch on:** check `w1r_mods.log`. "unexpected bytes" means a different game build.
- **Mac: black window / "Failed to initialize OpenGL 4.6":** use **More → Uninstall**, then Install again.
- **Mac: nothing happens on Play:** make sure Battle.net finished installing; **More → Run the Battle.net installer again**.

## Building

Needs Xcode command line tools, `lld` (`brew install lld`) and Python 3:

```sh
./build.sh            # build/VERSION.dll, build/W1R-Mods-Installer.exe, build/Warcraft I for Mac.app
sh tools/package.sh   # dist/ with the release zip, checksums and build-info.txt
```

To publish a release, bump `VERSION`, update `RELEASE_NOTES.md`, then push a tag (`git tag v1.0.0 && git push --tags`). The workflow builds, attests and publishes it.

## Credits

- [Wine](https://www.winehq.org) and [CrossOver](https://www.codeweavers.com/crossover)'s open-source Wine, packaged by [Sikarugir](https://github.com/Sikarugir-App) and [Gcenx](https://github.com/Gcenx)
- [WineMetalGL](https://github.com/metalsharp/WineMetalGL) by metalsharp
- Warcraft is a trademark of Blizzard Entertainment, Inc.

## License

MIT for the code in this repository (see `LICENSE`). Wine, Sikarugir and WineMetalGL are downloaded from their own releases under their own licenses.
