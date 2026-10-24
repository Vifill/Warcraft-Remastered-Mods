# Reverse-engineering notes: Warcraft I: Remastered

All addresses are virtual addresses in `x86\Warcraft.exe`, **game build 1.0.0.2762**, at the
preferred image base `0x400000`. The exe has ASLR (DYNAMICBASE), so code must use
`base + (va - 0x400000)` (`REL()` in `mod/w1r_mods.c`). Under Wine it loads at 0x400000.

Tools used: `llvm-objdump -d` for disassembly (`xcrun llvm-objdump` on Mac), the game's own crash
reports, lldb attached to the running game to read/write memory, and memory snapshots diffed
while scrolling to find the camera.

## Startup self-check
- Modifying `Warcraft.exe` on disk makes the game crash at startup: static init at ~0x45D398
  calls `ClientSdk.dll` ordinal 3 (via IAT 0x67A088) with two hash constants, which returns NULL
  for a modified file. So **never patch the file**; patch memory after startup (the DLL waits
  `patch_delay_ms`, default 8000). No periodic memory check was seen in hours of play.

## Crash reports
- On a crash the game writes `x86\Errors\<date> <id>\Crash.txt` (+ `W1R.dmp`) with the faulting
  instruction, registers and stack. This is the fastest way to locate bugs.
- The game logs to OutputDebugString (`INFO:`/`ERROR:` lines); visible with Wine `+seh` or a debugger.

## Map and units
| VA | What |
|---|---|
| `0x735318` | `u16*` tile flags, 64x64 (index `y*64+x`). `0x100` = unit on tile, `0x8000`/`0x4000` = goal area marks during path search, `0x2000` = visited by line walk |
| `0x735324` | `unit**` unit on each tile |
| `0x735328` | `u16*` per-tile direction trail used by the original search |
| `0x70914C` / `0x709154` | `s8[8]` dx / dy per direction: 0=N 1=NE 2=E 3=SE 4=S 5=SW 6=W 7=NW |

Unit struct (partial): `+0x0A` x (u16), `+0x0C` y (u16), `+0x10` flags (u16), `+0x1B` type,
`+0x1E` owner, `+0x1F` sub-type, `+0x22..+0x35` path buffer (20 direction bytes, `0xFE` = end),
`+0x50` path read index, `+0x52` destination (x,y packed), `+0x58` target unit.

- place unit on tile: `0x4DE150` (sets flag `0x100`, stores unit). remove: `0x4DE7A0` (clears the
  flag at the unit's *current* tile; clears the slot only if it holds that unit).
- `0x4EE3C0(unit)`: nonzero if the unit is moving (its tile counts as passable for friendlies).
- `0x747894`: `u8*` ally row for the current unit; `ally[owner] != 0` means passable.

## Ghost-unit crash (mod: ghost_fix)
- A tile can keep flag `0x100` after its unit is gone (stale after loading a save).
  `0x508C8B` (`movzx ecx,[edx+1Eh]`) then reads NULL+0x1E. 30 places read the tile-unit table,
  so the fix clears the stale flag at the first reader: hook `0x508C8B` (8 bytes
  `0f b6 4a 1e 80 3c 01 00`), if edx==NULL `and word [flags+ecx*2],0xFEFF` and continue at
  `0x508CA3` (tile free), else replay and continue at `0x508C93`.

## Pathfinding (mod: pathfinding=astar)
- `findPath(unit)` = `0x508850`. Original algorithm: plan 20 steps at a time; straight line toward
  goal (`0x508410`), else wall-follow left/right up to 100 steps (`0x508BF0`), keep the shorter.
- Setup before the search: blocking mask `0x74788C` (u16, `tileflags & mask` = blocked),
  start `0x747884`, goal `0x747888`/`0x74788A`, goal area marked by `0x5085D0` (`0x8000` on tiles;
  3x3 around a point or a building footprint plus ring).
- Hook at `0x508972` (8 bytes `8d 45 08 68 ff ff 00 00`): run A*; on success `add esp,8` and jump
  to cleanup `0x508AD2`; on failure replay and continue at `0x50897A` (original search).
- A* details: octile heuristic (10/14), passability identical to the original, writes the first 20
  directions into the unit's buffer. **If the unit already stands in the goal area, return 0** and
  let the original stop it (otherwise units shuffle back and forth at the destination).

## Camera and mouse (mod: middle_mouse_pan)
| VA | What |
|---|---|
| `0x747698` / `0x74769C` | camera x / y in game pixels (int, 16 px per tile) |
| `0x70E8A4` / `0x70E8A6` | camera in tiles (game logic copy) |
| `0x744090` / `0x744094` | view width / height (game pixels) |
| `0x743CC8` / `0x743CCA` | mouse x / y (s16, same units as the camera) |
| `0x4DD560` | clamp camera to the map |
| `0x4F2300` | scroll(): sums arrow-key/edge scrolling into esi/edi each tick |

- Hook at `0x4F2474` (9 bytes `0f bf ce 01 0d <0x747698>`, the address is relocated under ASLR):
  while VK_MBUTTON is held add (last mouse - current mouse) to esi/edi, replay
  `movsx ecx,si; add [cam_x],ecx`, continue at `0x4F247D`.
- SDL event translation is at `0x4E4C30`; the middle button is ignored by the game, so it is free.

## Movies (not modded)
- The remaster plays `movies\logocentered.webm`, `movies\intro.webm` and
  `movies\{orc,human}_briefing.webm` with its own decoder (no Media Foundation needed).
- The original FLCs (`omapNN`, `hmapNN`, intros, finales) are only reachable through the original
  script interpreter (opcode table `0x70B800`, op 0 = play movie, movie table `0x70B570`,
  FLC player `0x4E4F30`). The remaster's campaign flow never calls it. Endings were only ever
  short FLC loops behind text; Warcraft I never had a CGI ending.

## Mac (Wine) notes
- Stock Wine 11.x freezes Battle.net (32-bit) on Apple Silicon: r14 gets clobbered in the WoW64
  syscall thunk (wow64cpu.dll) and the next syscall faults ("nested exception on signal stack").
  The Sikarugir engine (CrossOver-derived) fixes it via Apple's `libd3dshared.dylib`
  (`CX_APPLEGPTK_LIBD3DSHARED_PATH`), shipped in the Sikarugir wrapper template.
- The game needs OpenGL 4.6 -> WineMetalGL 3.2.0, enabled per exe:
  `HKCU\Software\Wine\AppDefaults\Warcraft.exe\DllOverrides` `opengl32=native`, with the i386
  `opengl32.dll` + `winemetalgl.dll` in the game's x86 folder. Same for `Warcraft II.exe`.
- Audio crackle: `SDL_AUDIODRIVER=directsound` in `HKCU\Environment`.
- The mod DLL needs `version=native,builtin` for `Warcraft.exe` (Wine prefers its builtin otherwise).
- Edit `user.reg` only while the wineserver is stopped (it rewrites the file on exit).
  The Blizzard Agent keeps the wineserver alive after Battle.net closes; use the wrapper's
  `WSS-wineserverkill`.
- Never leave lldb attached to the game: it can freeze it (e.g. a black window on quit).
