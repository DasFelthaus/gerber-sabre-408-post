# Gerber Sabre 408 — Post Processor for SAB N.3

A post processor (.cps) for the **Gerber Sabre 408** CNC router running the original **SAB N.3 controller** (bootloader F.2). Works with **Autodesk Fusion**, **HSMWorks**, and **Inventor CAM**.

## The Problem

The Gerber Sabre 408 with the SAB N.3 controller is a capable machine, but its controller only reliably accepts **inch-mode G-code (G20)**. Sending metric G-code (G21) causes register overflow and bounds violations due to the controller's narrow fixed-point arithmetic — metric coordinate values are ~25.4x larger than their inch equivalents, exceeding the controller's internal register capacity.

On top of that, the SAB N.3 supports a very limited subset of RS-274-D. There are no canned drilling cycles, no cutter compensation, no work coordinate systems, and no helical interpolation. The machine is strictly 2.5-axis: Z completes its move before XY begins.

No suitable post processor exists for this combination of machine and controller. Generic Fanuc or Haas posts output commands the SAB N.3 doesn't understand, and the original Gerber software (ART Path) is long discontinued.

## What This Post Processor Does

- **Automatic mm-to-inch conversion** — Program your CAM in metric as usual. The post converts all coordinates, feed rates, and arc parameters to inches automatically. Tool dimensions are kept in mm in comments for easy identification.
- **Strict 2.5D move splitting** — Z and XY moves are never combined on the same line. Retracts move Z first, then XY. Approaches move XY first, then plunge Z. This matches how the SAB N.3 physically executes motion.
- **Expanded drilling cycles** — All drilling operations (G81/G82/G83 equivalents) are expanded into explicit G00/G01 moves since the controller has no canned cycle support. Peck drilling (chip-breaking and deep-drilling) is fully supported.
- **Tapping rejection** — Tapping cycles are rejected with a clear error, since the SAB N.3 cannot synchronize spindle reversal.
- **Arc safety** — Only XY-plane arcs are output. Helical arcs (arc + Z) are automatically linearized to prevent spoilboard damage. Full-circle arcs are also linearized for controller reliability.
- **Feed rate clamping** — Feed rates are clamped to the configured maximum (default matches the machine's 850 ipm / 21590 mm/min positioning limit).
- **Serial compatibility** — Output uses CR+LF line endings, ASCII only, `%` program delimiters, and optional N-word line numbering — all required for reliable RS-232 transfer.

## Files

| File | Description |
|---|---|
| `gerber_sabre_408.cps` | Fusion post processor — install in Fusion's post library |
| `Gerber Sabre 408.mch` | Machine configuration file |
| `BlueElephantCNCTools.tools` | Tool library with common router tooling |

## Installation

1. In your Autodesk CAM software (Fusion, HSMWorks, or Inventor CAM), go to **Manage > Post Library**.
2. Click **Import** and select `gerber_sabre_408.cps`.
3. Optionally import the `.mch` machine configuration via **Manage > Machine Library**.
4. Optionally import the `.tools` tool library via **Manage > Tool Library**.
5. When posting, select "Gerber Sabre 408 - SAB N.3" as your post processor.

## Post Properties

These are configurable in the Post Process dialog:

| Property | Default | Description |
|---|---|---|
| Use line numbers | Yes | Output N-word line numbers |
| Line number start | 10 | Starting line number |
| Line number increment | 10 | Increment between line numbers |
| Linearize arcs | No | Convert all arcs to line segments (safe mode) |
| Show comments | Yes | Output comments in parentheses |
| Show tool info | Yes | Output tool info in header comments |
| Max feedrate | 10000 mm/min | Maximum feedrate (clamped in output) |
| Safe retract height | 12.7 mm | Safe Z height for retracts |
| Use M05 for spindle stop | Yes | Use M05 (if false, uses M03 S0 instead) |
| Split file by tool | No | Create separate NC files per tool |

## First-Run Verification

Before running production jobs, verify these on the physical machine:

1. **Comments** — Send `(TEST COMMENT)` and check if the controller accepts or errors. If it errors, disable comments in post properties.
2. **G20** — Send `% N10 G20 G90 %` and confirm no error.
3. **M05** — If your firmware rejects M05, set "Use M05 for spindle stop" to No (uses M03 S0 instead).
4. **Feed rate units** — Command `G01 X1.0000 F100` and verify the machine moves at ~100 ipm, not 100 mm/min.
5. **Arc direction** — Run a small G02 arc and confirm it cuts clockwise viewed from above.
6. **Coordinate directions** — Jog and confirm +X and +Y move in expected directions.

## Supported G-code

The post outputs only commands confirmed working on the SAB N.3:

| Code | Function |
|---|---|
| G00 | Rapid positioning |
| G01 | Linear interpolation (cutting) |
| G02/G03 | Circular interpolation CW/CCW (XY plane only) |
| G20 | Inch mode (always) |
| G90 | Absolute positioning |
| M03 | Spindle on |
| M05 | Spindle stop |
| M06 | Tool change |

## Machine Specs

| | |
|---|---|
| Work envelope | 54" x 100" (1370 x 2540 mm) |
| Max positioning rate | 850 ipm (21590 mm/min) |
| Communication | RS-232 at 9600/8/E/1 |
| Serial buffer | ~256 KB |

## Community Resources

- **Signs101.com** — Richest Gerber Sabre resource, multiple experienced users
- **CNCzone.com / IndustryArena** — Dedicated Gerber subforum
- **LinuxCNC Forum** — Gerber 408 retrofit discussions

## License

MIT
