# WaypointUIRestedXPSync

Creates one Waypoint UI stored map pin for each active RestedXP step with a
valid destination. Steps are ordered by guide index, and the first navigable
active step becomes the primary in-world marker. Within a step, prefers RXP's
selected arrow destination, then its active pins and coordinate-bearing
objectives. Neither dependency's files are modified.

Restart WoW to discover the addon. Enable all three addons. RestedXP's selected
active destination is followed even when its arrow frame is hidden. Its destination is
checked four times per second; unchanged destinations are not recreated.

While active, RestedXP takes priority over manual pins and tracked quests.
Use `/wrxs off` for manual navigation, `/wrxs on` to resume, and `/wrxs status`
to diagnose. The enabled setting is saved account-wide.

Version 1.2.0 enables Waypoint UI's Custom Map Pins once. Secondary destinations
appear as map pins, not simultaneous in-world beams; Waypoint UI displays one
primary in-world marker. Each pin uses its own step's label and icon. Steps
without usable coordinates are omitted, and the first step WITH coordinates
is primary. Ending a step or disabling sync removes only pins owned by this
addon. Unchanged pins are not recreated; changed labels refresh on the next poll.

Version 1.2.3 resolves ongoing-objective icons from the pin's own step when
the coordinate element is travel or a plain note. Kill/collect/complete tasks
and objective counters use IncompleteQuest; explicit accept/turn-in icons take
precedence. Waypoint UI's own redirect icon remains under its control and can
replace the destination icon while it displays a routing waypoint.

When there is no active arrow destination, only the sync addon's own navigation is
cleared, without advancing Waypoint UI's queued pins. Prior manual destinations
are not restored. Audio is suppressed for synchronized waypoint changes.

Coordinates must be supported by Blizzard's map waypoint system. Instructions
without a destination cannot have a marker. Corpse/world-only destinations are
converted through RestedXP's HereBeDragons library when possible.

Compatibility: installed RXPGuides 4.11.18 and Waypoint UI 1.7.3 on Forever.
RestedXP's arrowFrame/element fields are internal and may require adaptation
after future RestedXP updates. Live in-game behavior requires verification.

Version 1.2.4 reads live objective text before static tooltips or pooled widgets,
prefers unfinished objectives over travel instructions, and rejects stale arrow
objects from other steps/guides. Stored pins and the world marker use one resolved
snapshot per poll. Metadata changes update on the next 0.25-second poll without
the older one-second label delay; unchanged pins are not recreated.

Version 1.0.1 fixes percentage input to Waypoint UI, tolerates native coordinate
rounding, and restores supertracking without recreating an unchanged marker.

Version 1.1.0 shows the destination's linked objective or rendered guide text,
including progress supplied by RestedXP. Falls back to an unfinished objective
in the same step, destination title, then RestedXP. Removes texture/color/link
markup, shortens long labels, and omits the step number. Label-only refreshes
were originally limited to once per second; version 1.2.4 removes that delay.

Version 1.1.2 uses Waypoint UI's existing artwork directly: AvailableQuest for
accepting quests, CompleteQuest for turn-ins, IncompleteQuest for ongoing
collection/combat/objectives, and Navigation for travel. All follow Waypoint
UI's recoloring style and remain consistent during text updates.

Version 1.1.3 applies the requested fixed icon scale once at login by disabling
Waypoint UI's Use World Scale. Later changes in /wp are respected. Labels are
limited to approximately 52 bytes, shortened at word
boundaries where possible, with trailing objective counts retained. Common
upstairs/downstairs/inside directions are omitted from the marker; the full
instructions remain in RestedXP.

## Development and releases

The repository contains only this sync addon. Install RXPGuides and Waypoint UI
separately; their source, guide content, and artwork are not bundled.

Run `python package.py` to create an installable ZIP in `dist/`.

GitHub Actions packages version tags and manual runs. Publish releases from the
GitHub Releases page and attach the generated ZIP. Validation-only files are
not included in this repository.

CurseForge publishing is not connected yet. It requires a project ID, confirmed
supported game versions, dependency project relations, and an upload token stored
as a repository secret. The current TOC lists local client interface versions;
that does not establish that all those versions have been tested or are accepted
by CurseForge. No redistribution license has been selected yet.
