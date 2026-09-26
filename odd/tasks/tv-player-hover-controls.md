# Show TV player controls on mouse hover

## Objective
Make the existing TV player controls discoverable in the Windows desktop player when the pointer hovers over the player.

## Problem and why
The TV player starts with controls hidden and its video surface has no mouse-hover or click handler to reveal them. The root `Focus` currently reveals the toolbar with left/right and the full controls with Enter/Space, so a mouse user can see video (or a black surface) without any controls.

## Scope and constraints
- On pointer hover within the TV player, reveal the full playback controls; keep them available while the pointer remains over the player and hide them after it leaves.
- Preserve keyboard/remote focus behavior, buffering indicator, screensaver behavior, and mobile/other player screens.
- Avoid changing loading/error presentation or playback state logic in this task.
- Do not push or create a PR.

## Delivery and checks
- Route: delegated direct implementation.
- Trigger evidence: the writer task spans the TV player behavior and focused regression coverage (2 non-trivial files); the existing flow and handlers were mapped with CodeGraph first.
- TDD: strict; source: existing project preference; runner: `flutter test`.
- Forecast: under 100 authored changed lines, excluding this task record.
- Checks: observe a focused test RED before source changes; GREEN after; run `flutter analyze` on touched Dart and applicable focused tests.

## Acceptance criteria
- Hovering over the TV player reveals the full controls without requiring a click or keyboard input.
- Leaving the player hides the hover-revealed controls; keyboard/remote interactions continue working.
- Loading and error states are not replaced by playback controls.

## Tasks
- [x] TVHC-1 — Reveal and dismiss TV playback controls with mouse hover.
  - Route: delegated direct; writer trigger is the source behavior plus regression test across multiple non-trivial files.
  - TDD: strict; runner `flutter test`; require observed RED then GREEN.
  - Progress: implemented Windows-only hover handling without stealing keyboard focus; exiting restores the prior controls visibility unless focus moved to a control.
  - Verification: focused test was observed RED before implementation, then `flutter test test/features/player/tv_player_hover_controls_test.dart` passed (2/2). `git diff --check` is clean. `flutter analyze lib/features/player/presentation/tv/tv_player_page.dart test/features/player/tv_player_hover_controls_test.dart` exits 1 with 21 pre-existing diagnostics in the legacy player file; none reference the new hover code/test.
  - Manual Windows visual verification and native review/commit: pending.

## Next step
Resolve whether to grant or decline the native high-risk review candidate; then follow the corresponding review path or ordinary policy, create the local work-unit commit, and perform manual Windows visual verification if available.

## Relevant files
- `lib/features/player/presentation/tv/tv_player_page.dart` — TV player focus, controls, and video surface.
- `test/` — focused hover interaction regression coverage.
