# AutoCurseur

[![CI](https://github.com/Jbbouille/autocurseur/actions/workflows/ci.yml/badge.svg)](https://github.com/Jbbouille/autocurseur/actions/workflows/ci.yml)

**English** · [Français](README.fr.md)

A tiny Windows tray utility written in Zig: the whole mouse pointer turns **black over light backgrounds** and **white over dark ones**. Shake the mouse and the pointer grows and turns red so you can find it.

Native code, about 100 KB, no dynamic memory allocation, about 0.2 % of one CPU core.

## Why

Windows has an "inverted" pointer, but it inverts each pixel separately. Over a colored background the pointer takes on odd colors. In Chrome or Edge with hardware acceleration it sometimes stays white over a white page, because the inversion is computed against a screen layer that is not the page.

AutoCurseur uses opaque cursors that are really black or really white, and picks one by looking at what is under the mouse.

## Usage

Download `AutoCurseur.exe` from the [releases](https://github.com/Jbbouille/autocurseur/releases) (or build it, see below) and run it. The exe is not signed, so Windows SmartScreen may warn the first time: click *More info*, then *Run anyway*.

A round half-black, half-white icon appears in the notification area:

- **right-click**:
  - *Active*;
  - *Checks per second (while the mouse moves)*: 3, 5, 10 (default) or 20;
  - *Language*: automatic (follows Windows), English or Français;
  - *Shake to find the pointer (bigger, in red)*: on by default;
  - *Start with Windows*;
  - *Quit*;
- **double-click**: pause or resume.

The registry only holds your settings: the startup option, and the choices made in the menu (`HKCU\Software\AutoCurseur`, created only when you change one). When paused or closed, Windows reloads your usual cursors. No admin rights are needed and nothing is installed: the shapes come from the cursors that ship with Windows (see *Pointer style* below). AutoCurseur writes their missing black, white and red versions once into `%LOCALAPPDATA%\AutoCurseur\cursors` (34 files, about 4 MB; see *Several screens* below).

**It is not a Windows service**, just a small program in your session, like a taskbar icon. It only works while it runs:

- **to stop it**: right-click the icon, then *Quit*. Your usual cursors come back immediately;
- **to start it automatically**: check *Start with Windows*. It then starts at every sign-in;
- **if it is killed** (Task Manager): the last black or white cursors stay until the next sign-in or the next launch of AutoCurseur, which first puts back the Windows ones.

A service would not work anyway: it runs outside your session and can neither see your screen nor change your pointer.

## How the color is chosen

1. It reads the mouse position, which costs almost nothing: 10 times per second by default, or 3, 5 or 20 times depending on the menu setting. Once the mouse has been still for 1 s, it only checks every 250 ms (every 333 ms at the 3/s setting).
2. It copies a square of the screen that covers the body of the pointer. The square is three quarters of the pointer size, so 48 px for a 64 px pointer. It starts slightly above and left of the tip and extends mostly down and to the right.
3. It computes the **average luminance** of the square, from 0 to 255, weighted like the eye: 30 % red, 59 % green, 11 % blue.
4. It decides with **hysteresis**:
   - from 150 up, the pointer turns black;
   - at 105 or below, it turns white;
   - in between, it does not change. This avoids flicker over mid grays and along a boundary.
5. It changes the color of **the pointer on screen only**. Windows has 17 pointers (arrow, text selection, link hand, resize arrows…); AutoCurseur remembers the color of each one, and Windows notifies it whenever the pointer shape changes: the new shape gets the right color right away (well under a hundredth of a second). The checks above also look at the displayed pointer, in case a notification is lost.

**With text underneath**, the background decides, not the letter under the pointer. The tests check this on images drawn in memory:

| Content | Luminance read | Pointer |
|---|---|---|
| Black text on a white page | 181 to 255 | black everywhere, never switches |
| Very large bold heading | 139 to 255 | black everywhere, thanks to the hysteresis |
| Dark code editor | 30 to 50 | white everywhere |
| Fine black/white checkerboard, mid gray | about 128 | never changes |

Each pointer has an outline of the opposite color, so it stays visible even on top of a letter.

## Pointer style

The pointers have the shape of Windows' usual white pointers ("Windows Aero", with soft edges). In black, AutoCurseur uses their exact negative: only black, white and gray pixels are inverted, so the red of *unavailable* stays red. Three kinds of pointers keep the shapes of the "Windows Black" scheme that ships with Windows:

- text selection and precision: the white style has no file for them (Windows then uses pointers that invert the screen, exactly what AutoCurseur avoids);
- the two busy pointers, animated in the white style: AutoCurseur shows them still.

The "Windows Black" arrow, used until version 0.1.0, had a longer tail and stair-stepped edges, and when it gave way to the text selection pointer it left a visible trace on screen. The white style arrow, in black, leaves none.

The pointer **size** is the size of the arrow Windows is displaying at that moment. At 250 % display scaling, Windows uses 64 px, not 32 × 2.5 = 80.

## Several screens

When two screens have different display scaling (for example 150 % and 250 %), Windows wants a different pointer size on each one (48 and 64 px). A cursor built in memory has only one size: Windows stretches it on the other screen, and the outline becomes irregular.

So AutoCurseur writes its cursors as real `.cur` files, in `%LOCALAPPDATA%\AutoCurseur\cursors`, keeping every size of the Windows files (32, 48, 64, 96 and 128 px): the black negative of the white style pointers, the white version of the four "Windows Black" ones, and the red version of all of them. The other versions are Windows' own files, used as they are. Files left by an earlier version are deleted when the new ones are written. Windows then picks, screen by screen, the image drawn at the right size, exactly as it does for its own cursors. The files are written only when they are missing or out of date.

## Enlarged pointer (Accessibility)

When the pointer size is raised in *Settings → Accessibility → Mouse pointer and touch*, Windows 11 stops using its classic images: it draws its cursors from vector drawings (`C:\Windows\Cursors\*.svg`), once at 240 × 240 px, and shrinks them to the displayed size. AutoCurseur does the same, so its pointer has exactly the same modern shape:

- the 17 drawings are rendered with Direct2D at 240 × 240, black body and white outline, then flipped (the drawings are stored upside down), white and red versions made from them;
- compared with the images Windows produces itself (`%LOCALAPPDATA%\Microsoft\Windows\Cursors\*_eoa.cur`): 8 cursors out of 17 are identical to the pixel, the others differ by a few edge pixels (under 0.4 %), and all hotspots are the same;
- this happens only once the pointer is enlarged (about 0.3 s, once per session); Direct2D is loaded only for that and unloaded right after (0.4 MB kept);
- at size 1, Windows uses its classic images, and so does AutoCurseur; without these drawings (Windows 10), AutoCurseur keeps the classic images at every size.

When the size slider moves, Windows reloads its own cursors after its notification, without sending another one. AutoCurseur waits until things calm down and puts its cursors back 0.5 s, 1.5 s and 3 s after the last notification.

At very large sizes, the red cursor no longer doubles beyond 255 px on screen: past that, Windows draws the pointer itself and loading a red set takes it up to a second. A pointer that is already huge only turns red.

Very large sizes are costly for Windows itself. Loading a cursor from its file then takes it about 5 ms, because it prepares a giant version of it (384 px at 150 %, 640 px at 250 %), even for its own cursors. Reloading all 17 cursors at each color change would cost about 90 ms; since AutoCurseur only reloads the one on screen (see *How the color is chosen*), a change costs about 10 ms (measured: 40 changes in 20 s of back-and-forth between a dark and a light area cost 0.6 s of CPU instead of 3.8 s). Past 255 px on screen, Windows also draws the pointer into the screen image itself, and screen reads can become much slower (up to 300 to 500 ms in some of our measurements, 17 ms in others). That is why AutoCurseur reads the screen on a separate thread: its main thread (menu, timers, shake detection, Windows messages) never waits for a read. The reading thread sleeps until asked, and if a read is still running, only the latest requested position is kept. It costs 36 KB of memory and 12 µs per request (0.012 % of one core at 10 reads per second).

## Shake to find the pointer

As on macOS, quickly moving the mouse back and forth makes the pointer twice as large and red, with a white outline. It goes back to normal 0.6 s after you stop.

- **Detection**: only while the mouse moves, its position is read about every 30 ms. It takes two and a half back-and-forths in a row (five reversals) within one second, each swing at least three times the pointer size (144 px for a 48 px pointer), horizontally or vertically; a shorter swing restarts the count. Aiming at a target and correcting an overshoot, selecting text, a brisk but short back-and-forth, or sweeping slowly back and forth does not trigger it.
- **Shape**: the red cursors are made from the black set and shown at double size (48 → 96 px at 150 %, 64 → 128 px at 250 %). Those sizes exist in the files, so the outline stays sharp. With an enlarged pointer, the red cursor stays under 255 px on screen (see above).
- **Cost**: about 4 ns of computation per position read. The red files are written once (about 30 µs each) and not at all when the option is off.

## Resource usage

Measured by the performance and system tests, on a laptop with a 250 % display:

| | |
|---|---|
| Executable | about 98 KB in ReleaseFast |
| Private memory | about 2 MB |
| Files written once | 34 classic cursors, about 4 MB, checked in about 13 ms at startup; with an enlarged pointer, 51 vector cursors (5 MB) drawn in about 0.3 s |
| CPU, mouse still | about 0.15 % of one core |
| CPU, mouse moving | about 0.1 % (3/s), 0.2 % (5/s), 0.3 % (10/s), 0.7 % (20/s) of one core |
| One screen read | about 0.3 ms of CPU |
| Black ↔ white change (only the pointer on screen, read from its file) | about 0.8 ms (about 10 ms with the largest pointer) |
| Recoloring a pointer shape that appears (link hand…) | under 1 ms after Windows' notification |
| 2 s of shaking (screen reads included) | about 20 to 40 ms of CPU |
| Longest wait for an answer from AutoCurseur while the mouse moves | under 16 ms (screen reads on a separate thread) |

**No dynamic allocation**: all buffers are fixed-size global arrays, about 470 KB (mostly the 144 KB and 236 KB buffers used to read and write cursor files; the largest file written, a red 240 × 240 cursor, takes 233 KB). Direct2D, when used, makes its own allocations and is unloaded right after. A test rejects any trace of an allocator in the application code. Only Windows objects (cursors, bitmaps, window, icon) are created by the system.

## Building

You need [Zig](https://ziglang.org) 0.17.

```powershell
zig build
```

The executable is written to `zig-out\bin\AutoCurseur.exe`, compiled in **ReleaseFast**. For a smaller exe, use `zig build -Doptimize=small`. For the *Start with Windows* option, run it from where it will stay, since that path is what gets registered.

## Tests

```powershell
zig build test
```

This runs 147 tests without touching your session's pointer:

- **unit** (`src/*.zig`): decision and hysteresis, luminance, inversion of color and monochrome pixels, red tint, shake detection (real shakes, overshoot corrections, brisk but short or slow back-and-forths, a short swing breaking the series, millisecond counter wrap-around), geometry of the area read, sizes, timer pacing (reads-per-second budgets), texts in both languages, menu identifiers, icon, no allocation and static memory budget;
  - `.cur` files (`src/curfile.zig`): reading, rejecting PNG, compressed or truncated images, inverted and red versions, double inversion giving back the original, 4-byte alignment, buffer too small, single-image 1-bit and 32-bit files;
  - vector cursors (`src/svgcur.zig`): color substitution, 1-bit conversion (any touched pixel visible), unpremultiplied colors, hotspots;
- **integration** (`tests/integration.zig`):
  - the 17 real Windows cursor files, at 7 sizes;
  - exact and reversible inversion, hotspot kept;
  - the written files: every size from 32 to 128 px kept, written once, not rewritten when up to date, rewritten when damaged;
  - red set: every cursor twice as large, the arrow identical to the black one with only its black pixels turned red (soft edges included), an outline with no gap;
  - files left by an earlier version deleted when the new ones are written;
  - no leaked Windows objects after 20 reloads;
  - recognizing the displayed pointer: each of the 17 system cursors by its handle, never a cursor loaded by a program;
  - the screen reading thread: answers a request, keeps only the latest of 50 requests in a row, stops cleanly, reads on the spot once stopped;
  - vector cursors: the 17 drawn at 240 px, same shape and hotspots as the images Windows produces itself, white = exact inverse of black, red with soft edges, loadable at every size, not redrawn when up to date, Direct2D unloaded afterwards;
  - text and themes drawn in memory;
  - a boundary scanned pixel by pixel, checkerboard, vivid colors;
- **performance** (`tests/perf.zig`, compiled in the same mode as the released exe, ReleaseFast by default): each measurement is printed and compared with a limit about 10 times higher than the measured value.

```powershell
zig build test-system
```

These 18 system tests really change the pointer for about a minute, move the mouse, then restore everything. Quit AutoCurseur before running them (`zig build check-system` only compiles them). They check:

- applying then restoring the cursors, and their size;
- cursors of another size left by an earlier run, which must not be reused;
- the reads-per-second, language and shake settings sent through the menu, then saved; your registry settings are put back afterwards;
- 200 switches in a row;
- on a test window (light or dark background, arrow or link hand, always on top): only the pointer on screen changes color, each other shape when it appears, none stays red after a shake; changing the displayed pointer only stays fast even with an enlarged pointer; with the real executable, a hand that appears is recolored in under 100 ms while the hidden arrow waits its turn;
- with screens at different display scaling: on each screen, the pointer Windows actually displays (captured with the desktop duplication API by `tests/tools/ptrcap.c`) has the size Windows gives its own cursors there, and is pixel for pixel the image of that size from our files, for the black, white and red sets; skipped with a single scaling;
- the pointer size notification (`0x2029`), followed by Windows putting its own cursors back 300 ms later: AutoCurseur stays responsive and puts its cursors back; a burst of 10 notifications does not block it;
- with an enlarged pointer: on each screen, our cursors have the size and shape of Windows' own; skipped at size 1, and when the pointer is too large for Windows to report its shape;
- a real shake of the mouse: the displayed arrow becomes the red one at double size, then goes back to normal; a plain sweep across the screen, a brisk back-and-forth of three pointer sizes, or a shake with the option off trigger nothing;
- while the mouse crosses the whole screen, AutoCurseur answers a question every 50 ms without delay;
- the real executable: black then white then black again as the test window background changes, usage over 10 s, memory, single instance, clean exit and original pointer back.

## Continuous integration

On every push and pull request, [GitHub Actions](.github/workflows/ci.yml) installs Zig on a Windows machine. It runs `zig build test` and `zig build test-system`, builds the exe in ReleaseFast and makes it available as an artifact.

To publish a version, push a `v*` tag (for example `git tag v0.1.0` then `git push origin v0.1.0`). Once the tests pass, the pipeline creates the GitHub release with the tested exe, then submits the new version to winget (see [packaging/winget](packaging/winget/README.md)).

## Layout

```
src/core.zig      pure logic, no Windows (decision, luminance, inversion, red tint, shake, timer)
src/cursors.zig   writing the files of the black, white and red sets, recoloring the pointer on screen
src/curfile.zig   reading and writing .cur files (inverted and red versions, every size kept)
src/svgcur.zig    vector cursors drawn with Direct2D, like Windows 11 for an enlarged pointer
src/sampler.zig   reading the screen under the mouse, on a separate thread
src/icon.zig      notification area icon
src/i18n.zig      menu texts in English and French
src/settings.zig  saved settings (HKCU\Software\AutoCurseur)
src/main.zig      hidden window, menu, timers: ties everything together
src/win32.zig     declarations of the Windows API functions used
src/lib.zig       entry point of the unit tests
tests/            integration, performance, system
tests/tools/      capture of the displayed pointer, for the system tests
packaging/winget/ winget manifests
```

## Settings

| Where | Name | Default | Role |
|---|---|---|---|
| `core.zig` | `Thresholds.to_black` | 150 | luminance from which the pointer turns black |
| `core.zig` | `Thresholds.to_white` | 105 | luminance below which it turns white again |
| menu | checks per second | 10 | 3, 5, 10 or 20 while the mouse moves (`core.RATES`) |
| menu | language | automatic | follows the Windows display language: French for any French variant, English otherwise |
| menu | shake to find | on | bigger red pointer when the mouse is shaken |
| `core.zig` | `SHAKE_TURNS`, `SHAKE_WINDOW_MS` | 5, 1000 | consecutive wide reversals needed, and the time they must fit in |
| `core.zig` | `SHAKE_SEG_FACTOR` | 3 | minimum swing, in pointer sizes |
| `core.zig` | `SHAKE_HOLD_MS` | 600 | how long the pointer stays big after the last reversal |
| `core.zig` | `STILL_MS` | 1000 | time without movement before slow mode |
| `core.zig` | `IDLE_MS` | 250 | period in slow mode (never more often than while moving) |
| `core.zig` | `MAX_CUR` | 256 | maximum cursor size, which sizes the static buffers |

The menu choices are stored as `DWORD` values in `HKCU\Software\AutoCurseur`: `LecturesParSeconde`, `Langue` (0 automatic, 1 English, 2 French) and `SecouerPourRetrouver` (0 or 1).

## Limitations

- Windows 10 or 11 only.
- Animated cursors (busy) are replaced by their static version from the "Windows Black" scheme.
- Screen capture cannot see protected (DRM) videos, which appear black: the pointer will be white over them.
- The executable is not signed (see SmartScreen above).

## License

[MIT](LICENSE).

## Alternatives

- The Windows "inverted" pointer (Settings → Accessibility → Mouse pointer and touch): nothing to install, but per-pixel inversion, with the drawbacks described above.
- [DynamicCursor](https://github.com/ItsProfessional/DynamicCursor): a PowerShell script, archived since 2023. It compares 5 pixels without hysteresis, captures the whole screen in a continuous loop, modifies the registry and requires admin rights.
