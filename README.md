# AutoCurseur

[![CI](https://github.com/Jbbouille/autocurseur/actions/workflows/ci.yml/badge.svg)](https://github.com/Jbbouille/autocurseur/actions/workflows/ci.yml)

**English** · [Français](README.fr.md)

A tiny Windows tray utility written in Zig: the whole mouse pointer turns **black over light backgrounds** and **white over dark ones**. Shake the mouse and the pointer grows and turns red so you can find it.

Native code, about 80 KB, no dynamic memory allocation, about 0.2 % of one CPU core.

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

The registry only holds your settings: the startup option, and the choices made in the menu (`HKCU\Software\AutoCurseur`, created only when you change one). When paused or closed, Windows reloads your usual cursors. No admin rights are needed and nothing is installed: the shapes come from the "Windows Black" scheme that ships with Windows.

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

**With text underneath**, the background decides, not the letter under the pointer. The tests check this on images drawn in memory:

| Content | Luminance read | Pointer |
|---|---|---|
| Black text on a white page | 181 to 255 | black everywhere, never switches |
| Very large bold heading | 139 to 255 | black everywhere, thanks to the hysteresis |
| Dark code editor | 30 to 50 | white everywhere |
| Fine black/white checkerboard, mid gray | about 128 | never changes |

Each pointer has an outline of the opposite color, so it stays visible even on top of a letter.

The pointer **size** is the size of the arrow Windows is displaying at that moment. At 250 % display scaling, Windows uses 64 px, not 32 × 2.5 = 80.

## Shake to find the pointer

As on macOS, quickly moving the mouse back and forth makes the pointer twice as large and red, with a white outline. It goes back to normal 0.6 s after you stop.

- **Detection**: only while the mouse moves, its position is read about every 30 ms. Four quick reversals within one second trigger it, each swing at least twice the pointer size (128 px at 250 %), horizontally or vertically. Aiming at a target and correcting an overshoot, selecting text, or sweeping slowly back and forth does not trigger it.
- **Shape**: the red cursors are made from the black set, loaded at double size (64 → 128 px at 250 %). That size exists in the Windows files, so the outline stays sharp.
- **Cost**: about 4 ns of computation per position read. The 17 red cursors are prepared once (about 9 ms) and are not loaded at all when the option is off.

## Resource usage

Measured by the performance and system tests, on a laptop with a 250 % display:

| | |
|---|---|
| Executable | about 80 KB in ReleaseFast (about 65 KB with `-Doptimize=small`) |
| Private memory | about 1.9 MB |
| CPU, mouse still | about 0.15 % of one core |
| CPU, mouse moving | about 0.1 % (3/s), 0.2 % (5/s), 0.3 % (10/s), 0.7 % (20/s) of one core |
| One screen read | about 0.3 ms of CPU |
| Switching all 17 cursors black ↔ white | about 1.3 ms |
| 1.5 s of shaking (screen reads included) | about 16 ms of CPU |

**No dynamic allocation**: all buffers are fixed-size global arrays, about 330 KB, sized for cursors up to 256 px. A test rejects any trace of an allocator in the application code. Only Windows objects (cursors, bitmaps, window, icon) are created by the system.

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

This runs 107 tests without touching your session's pointer:

- **unit** (`src/*.zig`): decision and hysteresis, luminance, inversion of color and monochrome pixels, red tint, shake detection (real shakes, overshoot corrections, slow back-and-forth, millisecond counter wrap-around), geometry of the area read, sizes, timer pacing (reads-per-second budgets), texts in both languages, menu identifiers, icon, no allocation and static memory budget;
- **integration** (`tests/integration.zig`):
  - the 17 real Windows cursor files, at 7 sizes;
  - exact and reversible inversion, hotspot kept;
  - red set: every cursor twice as large, the arrow identical to the black one with only its black pixels turned red, an outline with no gap;
  - no leaked Windows objects after 20 reloads;
  - text and themes drawn in memory;
  - a boundary scanned pixel by pixel, checkerboard, vivid colors;
- **performance** (`tests/perf.zig`, compiled in the same mode as the released exe, ReleaseFast by default): each measurement is printed and compared with a limit about 10 times higher than the measured value.

```powershell
zig build test-system
```

These 10 system tests really change the pointer for about 30 seconds, move the mouse, then restore everything. Quit AutoCurseur before running them. They check:

- applying then restoring the cursors, and their size;
- cursors of another size left by an earlier run, which must not be reused;
- the reads-per-second, language and shake settings sent through the menu, then saved; your registry settings are put back afterwards;
- 200 switches in a row;
- a real shake of the mouse: the displayed arrow becomes the red one at double size, then goes back to normal; a plain sweep across the screen triggers nothing, nor does a shake with the option off;
- the real executable: usage over 10 s, memory, single instance, clean exit and original pointer back.

## Continuous integration

On every push and pull request, [GitHub Actions](.github/workflows/ci.yml) installs Zig on a Windows machine. It runs `zig build test` and `zig build test-system`, builds the exe in ReleaseFast and makes it available as an artifact.

To publish a version, push a `v*` tag (for example `git tag v0.1.0` then `git push origin v0.1.0`). Once the tests pass, the pipeline creates the GitHub release with the tested exe, then submits the new version to winget (see [packaging/winget](packaging/winget/README.md)).

## Layout

```
src/core.zig      pure logic, no Windows (decision, luminance, inversion, red tint, shake, timer)
src/cursors.zig   loading and building the black, white and red sets, applying them to the system
src/sampler.zig   reading the screen under the mouse
src/icon.zig      notification area icon
src/i18n.zig      menu texts in English and French
src/settings.zig  saved settings (HKCU\Software\AutoCurseur)
src/main.zig      hidden window, menu, timers: ties everything together
src/win32.zig     declarations of the Windows API functions used
src/lib.zig       entry point of the unit tests
tests/            integration, performance, system
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
| `core.zig` | `SHAKE_TURNS`, `SHAKE_WINDOW_MS` | 4, 1000 | reversals needed, and the time they must fit in |
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
