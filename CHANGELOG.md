# Changelog

## 1.3.0

- Isolate RestedXP data access in a dedicated adapter.
- Resolve labels, icons and progress from the linked objective; avoid ambiguous cross-objective labels.
- Use authoritative active-step data before pooled display frames.
- Include guide identity in stored pin IDs and remove completed-step pins.
- Preserve unchanged intermediate Waypoint UI route waypoints.
- Coalesce change notifications and retain a one-second recovery check; stop polling when disabled.
- Add manual navigation pause/resume, explicit secondary pin and scale options, and detailed diagnostics.
- Preserve other addons' settings on fresh installs unless explicitly configured.
- Limit advertised client support to Forever interface 16001.
- Publish tagged ZIPs as GitHub pre-releases pending live verification.

## 1.2.4

- Prefer live objective progress over static tooltips and pooled widget text.
- Prefer unfinished objectives over travel descriptions at the same location.
- Reject stale arrow objects belonging to other steps or guides.
- Resolve map pins and the primary world marker from the same snapshot.
- Refresh changed labels on the next poll without recreating unchanged pins.
