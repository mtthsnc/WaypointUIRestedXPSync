# WaypointUIRestedXPSync

An independent integration that keeps Waypoint UI destinations synchronized with
RestedXP's active guide steps on World of Warcraft: Forever.

## Installation

Download the addon ZIP from GitHub Releases and extract `WaypointUIRestedXPSync`
into `Interface/AddOns`. Install **RXPGuides** and **Waypoint UI** separately.
Restart WoW when installing a new addon or adding new source files.

Targets Forever interface **16001**. Developed against RXPGuides 4.11.18 and
Waypoint UI 1.7.3. Version 1.3.0 is pending live in-game verification.

## Behavior

The earliest active step with a usable destination becomes the world marker.
Optional secondary map pins represent other active steps; Waypoint UI still
renders one primary in-world marker. Labels and icons resolve from the linked
objective, or the sole unfinished objective when that relationship is unambiguous.
Ambiguous steps retain the destination instruction rather than borrowing another
task's description. Unsupported destinations are omitted and reported by debug.

RestedXP updates schedule a combined refresh after 0.1 seconds. A one-second
fallback catches missed changes. Disabled sync cancels its fallback timer.
Intermediate Waypoint UI route waypoints are preserved when the destination is
unchanged. Enabling sync defaults to taking navigation priority.

## Commands

- `/wrxs on` or `/wrxs off`: enable or disable synchronization.
- `/wrxs status`: show current synchronization state.
- `/wrxs debug`: show client/dependency versions, guide, selected steps, label and
  coordinate sources, rejected destinations, and the last error.
- `/wrxs mode always`: let RestedXP take navigation priority.
- `/wrxs mode manual`: pause when a different manual waypoint is detected.
- `/wrxs resume`: explicitly resume following RestedXP after a manual pause.
- `/wrxs pins on` or `/wrxs pins off`: enable or disable secondary map pins.
  Turning them on also enables Waypoint UI's Custom Map Pins setting.
- `/wrxs scale fixed` or `/wrxs scale distance`: explicitly set Waypoint UI's
  global distance-scaling preference. This affects its other waypoints too.

Fresh installs do not alter Waypoint UI preferences automatically. Existing
preferences from earlier sync versions are preserved. Disabling secondary sync
pins does not disable Waypoint UI's global Custom Map Pins feature.

## Compatibility and support

The integration reads RestedXP internal guide data through `RestedXP.lua` and uses
Waypoint UI's public navigation API from `Sync.lua`. Dependency updates may require
adapter changes. Missing required Waypoint UI methods pause synchronization with
a diagnostic instead of repeatedly raising Lua errors. Report issues with the
output of `/wrxs debug` and reproduction steps, without sharing purchased guide files.

[Issues](https://github.com/mtthsnc/WaypointUIRestedXPSync/issues)

## Releases

Run `python package.py` to build the ZIP in `dist/`; no third-party Python packages
are needed. The ZIP contains only runtime files and addon documentation.
Update the TOC version and changelog together before creating `vX.Y.Z` tags.
Tags build one ZIP and publish it as a GitHub pre-release by default. Once tested
in-game, promote that pre-release to a stable release. Manual workflow runs build
an artifact without publishing. Validation-only files are not stored here.

CurseForge setup remains pending: choose a license, create the project, confirm
Forever game-version IDs, and configure required dependency relations. Do not
publish another addon's code, paid guide content, or artwork in this ZIP. The
in-game icons are referenced from the separately installed Waypoint UI addon.
