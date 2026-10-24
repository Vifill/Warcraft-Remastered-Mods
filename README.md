# Warcraft I & II: Remastered — Mac support and mods

Play **Warcraft I: Remastered** and **Warcraft II: Remastered** on Apple Silicon Macs, plus optional mods for both games on Mac and Windows:

| Mod | Warcraft I | Warcraft II | What it does |
|---|---|---|---|
| **Middle-mouse panning** | ✓ | ✓ | Hold the middle mouse button (scroll wheel) and drag to move the map. |
| **Smarter pathfinding** | ✓ | ✓ | Units plan routes with A* instead of the original "walk straight, then hug the wall" logic, so they stop getting stuck behind forests and walls. Falls back to the original when a target can't be reached. |
| **Crash fix** | ✓ | | Fixes a crash a few seconds after loading some saves (map tiles that still claim a unit that no longer exists). |

Unofficial, made by fans. Not affiliated with or endorsed by Blizzard Entertainment. You need your own Battle.net account and your own copies of the games.

## Mac

Requires an Apple Silicon Mac on macOS 14 or later, and about 3 GB of free space.

1. Download **Warcraft-for-Mac.zip** from [Releases](../../releases) and unzip it.
2. Move **Warcraft I & II for Mac** to Applications and open it. The app isn't notarized by Apple, so the
   first time macOS refuses to open it: click **Done**, then open **System Settings → Privacy & Security**,
   scroll down and click **Open Anyway** next to the app's name. macOS only asks once.
3. Pick your mods and click **Install**. It downloads free Wine and graphics support (about 300 MB, checksums verified) and starts the Battle.net installer.
4. In Battle.net: sign in, install **Warcraft I: Remastered** and/or **Warcraft II: Remastered**, and click **Play**.

Next time, open **Warcraft I & II for Mac** and click **Play**. Changes to the mod checkboxes apply the next time the game starts.

**Saved games** are kept in `~/Library/Application Support/Warcraft1Mac Saves`, outside the Wine environment,
so uninstalling and reinstalling keeps them. If the app finds Warcraft saves with more progress in another Wine
setup (CrossOver, Whisky, Sikarugir or Wineskin wrappers, `~/.wine`), it offers to import them; **More → Import
saved games…** picks a folder by hand. Imports back up what they replace.

**How it works:** the app sets up a free Wine environment built from CrossOver's open-source code ([Sikarugir](https://github.com/Sikarugir-App)), which runs 32-bit Windows programs like Battle.net and the games correctly on Apple Silicon. It adds [WineMetalGL](https://github.com/metalsharp/WineMetalGL) because both games need OpenGL 4.6, which macOS doesn't provide, sets `SDL_AUDIODRIVER=directsound` to avoid crackling audio, and installs the mods. Everything lives in `~/Library/Application Support/Warcraft1Mac`; **More → Uninstall** removes it.

## Windows

1. Download **W1R-Mods-Installer.exe** from [Releases](../../releases).
2. Run it and pick **Warcraft I** or **Warcraft II**. It finds the game (or click **Browse…**); pick your mods and click **Install**.
3. Start the game from Battle.net as usual.

Run the installer again to change mods or to **Uninstall**. If the game is in Program Files and installing fails, run the installer as administrator. Windows may warn that the installer is from an unknown publisher: it isn't code-signed.

### Install by hand (no installer)

If you'd rather not run the installer, copy the files yourself. It's two files, and you can read the settings file before you use it:

1. From [Releases](../../releases) download **VERSION.dll** and the settings file for your game: **w1r_mods.ini** (Warcraft I) or **w2r_mods.ini** (Warcraft II). Optionally check them against `SHA256SUMS.txt` (see [Verify your download](#verify-your-download)).
2. In Battle.net, click the gear next to **Play** → **Show in Explorer**, and open the **x86** folder (it contains `Warcraft.exe` or `Warcraft II.exe`).
3. Copy both files into that folder. Edit the `.ini` to switch mods on or off.

To uninstall, delete `VERSION.dll` (and the `.ini` / `.log`) from the x86 folder.

Either way the game loads the same `VERSION.dll`; installing by hand only skips the installer program. To avoid running any prebuilt file at all, [build it yourself](#building) from the source.

## Settings

Mods are configured in a settings file next to the game's exe (the installer and the Mac app write it for you): `w1r_mods.ini` for Warcraft I, `w2r_mods.ini` for Warcraft II.

```ini
[mods]
enabled=1
ghost_fix=1             ; Warcraft I only
middle_mouse_pan=1
pan_speed_percent=100   ; 10-500
pathfinding=astar       ; or "original"
patch_delay_ms=8000
```

`w1r_mods.log` / `w2r_mods.log` in the same folder shows which mods switched on.

## How the mods work

The mods are a small stand-in `VERSION.dll` placed next to the game's exe (`Warcraft.exe` or `Warcraft II.exe`; one DLL serves both games). It forwards all real `VERSION.dll` calls to Windows, and a few seconds after the game starts (after its own startup self-check) it patches the running game in memory. **No game files are changed.** Each patch site is checked byte for byte first; if the game was updated and the code no longer matches, that mod stays off and the game runs normally.

Written for Warcraft I: Remastered build **1.0.0.2762** and Warcraft II: Remastered build **1.0.2.2818**.

## Verify your download

Releases are built by [GitHub Actions](.github/workflows/release.yml) from the tagged source, not on anyone's computer.

**1. Check the checksum.** Each release has `SHA256SUMS.txt`. In the folder with your downloads:

```sh
shasum -a 256 -c SHA256SUMS.txt --ignore-missing
```

On Windows (PowerShell): `Get-FileHash W1R-Mods-Installer.exe` and compare with `SHA256SUMS.txt`.

**2. Check where it was built.** GitHub signs a build attestation for every release file, proving it was built by this repository's workflow from a specific commit. With the [GitHub CLI](https://cli.github.com):

```sh
gh attestation verify Warcraft-for-Mac.zip --repo Vifill/Warcraft-Remastered-Mods
```

**3. Rebuild it yourself (optional).** Builds are reproducible: the same source and tool versions give byte-identical files. `build-info.txt` in each release lists the commit and tool versions used. Check out that commit and run:

```sh
./build.sh && sh tools/package.sh
```

`dist/SHA256SUMS.txt` should match the release. (The Mac app also depends on the exact Xcode version; the Windows files only on clang and lld.)

## Troubleshooting

- **Mods don't switch on:** check `w1r_mods.log` (Warcraft I) or `w2r_mods.log` (Warcraft II). "unexpected bytes" means a different game build.
- **Mac: black window / "Failed to initialize OpenGL 4.6":** use **More → Uninstall**, then Install again.
- **Mac: nothing happens on Play:** make sure Battle.net finished installing; **More → Run the Battle.net installer again**.

## Building

Needs Xcode command line tools, `lld` (`brew install lld`) and Python 3:

```sh
./build.sh            # build/VERSION.dll, build/W1R-Mods-Installer.exe, build/Warcraft I & II for Mac.app
sh tools/package.sh   # dist/ with the release zip, checksums and build-info.txt
```

To publish a release, bump `VERSION`, update `RELEASE_NOTES.md`, then push a tag (`git tag v1.0.0 && git push --tags`). The workflow builds, attests and publishes it.

## Credits

- [Wine](https://www.winehq.org) and [CrossOver](https://www.codeweavers.com/crossover)'s open-source Wine, packaged by [Sikarugir](https://github.com/Sikarugir-App) and [Gcenx](https://github.com/Gcenx)
- [WineMetalGL](https://github.com/metalsharp/WineMetalGL) by metalsharp
- Warcraft is a trademark of Blizzard Entertainment, Inc.

## License

MIT for the code in this repository (see `LICENSE`). Wine, Sikarugir and WineMetalGL are downloaded from their own releases under their own licenses.
