# Windows video_player backend

## Objective
Make existing video_player-based player screens initialize and render video on Windows.

## Problem and why
On Windows, player screens fail with `UnimplementedError: init() has not been implemented.` The running code uses `video_player`, but no Windows-capable platform backend is declared or initialized. This is the next runtime blocker while getting the Windows build operational.

## Scope and constraints
- Add a Windows-compatible video_player backend and initialize it before `runApp`, only when running on Windows; retain existing Android/iOS/web implementations.
- If Windows reports a video texture/output size of `0x0` while audio plays, select the stable software-backed rendering path on Windows only; preserve hardware acceleration elsewhere.
- Cover platform-specific backend and rendering policy with focused regression tests and build Windows.
- Do not modify individual player screens unless evidence shows the bootstrap/backend approach is insufficient.
- Preserve all existing user files and changes, including `windows/nuget.exe`, generated files, and the ongoing WebView task state.
- No push, PR, merge, or remote repository operation.

## Authorized scope
The user asked to get the Windows version running, authorized fixing Windows blockers (`solucionalo`), and continued the same troubleshooting after the WebView runtime error. This narrow backend fix is within that Windows-run objective.

## Delivery and checks
- Route: delegated direct implementation.
- Trigger evidence: mapper trigger — dependency, startup, generated plugin registration, and several player call sites; writer trigger — backend dependency + bootstrap + regression test span multiple non-trivial files. A read-only mapper confirmed the error source before writing.
- TDD: strict; source: existing project preference (`TDD estricto`) and historical Windows player task; runner: `flutter test`.
- Forecast: ~100 authored changed lines, generated lockfile changes excluded from the heuristic. User-selected delivery strategy on this Windows work: `feature-branch-chain`.
- Branch: `codex/windows-webview-support`, based on the Jostin main commit; do not push or create a PR without a separate user request.
- Applicable checks: observe focused test RED before implementation; focused test GREEN; `flutter analyze` for changed Dart; `flutter build windows` using the user-provided NuGet on process-local PATH.
- RDD: previously observed enabled globally; assess any work-unit commit and follow native consent gates. Existing WebView commit `861c34c` has a separate pending consent; do not conflate the two candidates.

## Acceptance criteria
- Windows has a concrete backend registered before any player calls `VideoPlayerController.initialize()`.
- Other platforms preserve their existing backend selection.
- Focused regression tests and Windows release build pass, or unavailable/failing checks are recorded honestly.

## Tasks
- [x] VPW-1 — Add and initialize the Windows video_player backend, with strict TDD.
  - Route: delegated direct.
  - TDD: focused test first failed because the helper/backend dependency did not exist (RED); after implementation both regression tests passed (GREEN).
  - Implementation: added `video_player_media_kit ^2.0.0` and `media_kit_libs_windows_video ^1.0.11`; a testable helper calls the injected backend only on Windows. `lib/main.dart` invokes it after binding initialization and before other async startup work / `runApp`. Android, iOS, and web backend selection remains unchanged. No player screens were changed.
  - Focused `flutter test test/core/video_player_backend_test.dart`: passed 2/2. Focused `flutter analyze lib/core/video_player_backend.dart test/core/video_player_backend_test.dart`: passed with no issues. Analysis including `lib/main.dart` exits 1 with 16 existing diagnostics in legacy code (warnings/info, including async-context, deprecated `withOpacity`, unused imports, and naming); no issue was reported in the helper/test.
  - `flutter build windows`: passed and produced `build\\windows\\x64\\runner\\Release\\lol.exe` using the user-provided `windows/nuget.exe` via process-local PATH. Flutter generated Windows plugin registration for `media_kit_libs_windows_video` and `media_kit_video`; CMake emitted developer warnings but no build errors.
  - Manual playback of a real TV URL was not exercised; user-side runtime confirmation remains pending.
  - Implementation work-unit commit: `a4868953b77290361ed02f06800e9bbdf095f7cc` (`fix(windows): add video player backend`). Its RDD assessment against the last reviewed boundary `8755add3d2a99ee68f309a680b005a1d8665d7df` covers the unreviewed branch range (the earlier WebView support commit plus this backend commit): medium risk, `review_due=true`, reason `slice_budget_reached`, 695 authored changed lines, unrelated untracked files excluded. The fresh native review start is still awaiting explicit user consent; no review was started.
- [x] VPW-2 — Mitigate Windows 0x0 video output with a Windows-only software rendering configuration.
  - Authorization/evidence: The user previously explicitly authorized fixing the Windows audio-with-black-picture symptom. The fresh Embed69 log again shows Direct3D hardware rendering followed by `VideoOutput.Resize` with width and height `0`; it does not show whether a later nonzero resize occurs. Treat this as the confirmed runtime symptom, but do not claim success until a visible frame is manually observed.
  - Route: delegated direct. Mapping trigger: diagnosis spans the app player surface, the MediaKit `video_player` adapter and its configuration path; writer trigger: a license-preserving package adapter fork/configuration plus regression tests touches multiple non-trivial files. Preparation/code reading goes with the writer.
  - TDD: strict; source: project preference `TDD estricto`; runner: `flutter test`.
  - Forecast: ~580 authored changed lines if the current 2.0.0 adapter must be vendored to expose its fixed configuration point. User-selected delivery strategy: `feature-branch-chain`. Keep upstream license/notices, do not minify or drop source/comments, and explain the size if the correct fork naturally exceeds the heuristic.
  - Implementation: vendored the resolved `video_player_media_kit 2.0.0` under `packages/video_player_media_kit` with upstream license/notices and a narrow exported platform configuration helper. The adapter now uses `VideoControllerConfiguration(enableHardwareAcceleration: false)` for Windows only; all other platforms retain hardware acceleration. Root dependency resolves through the local path. Player layouts and platform call sites were untouched.
  - TDD: the rendering-policy test first failed because the helper/configuration hook did not exist (RED), then passed with Windows false and non-Windows true (GREEN).
  - Checks: `flutter test test/core/video_player_rendering_config_test.dart test/core/video_player_backend_test.dart` passed 4/4; `flutter analyze` on the six changed Dart/test files passed with no issues; `git diff --check` passed. `flutter build windows` passed and produced the Release executable; existing `flutter_inappwebview` CMake developer warning only.
  - Manual playback still has not produced a user-observed visible frame; treat this as a tested mitigation, not a confirmed visual resolution, until the user reruns the URL.
  - Work-unit commit identity and cumulative-range RDD assessment: pending.

## Progress
- Read-only mapping confirms `video_player_platform_interface 6.9.0` itself throws the exact reported error from its default `VideoPlayerPlatform.init()` when no implementation is registered.
- `lib/main.dart` calls `WidgetsFlutterBinding.ensureInitialized()` then app setup and `runApp`, but never registers a Windows backend.
- `pubspec.yaml` contains only `video_player`; lockfile includes Android, AVFoundation, and web implementations but no Windows backend. Windows generated registrar similarly contains no native video plugin.
- Existing player implementations use `VideoPlayerController.networkUrl(...).initialize()` in the general player, TV player, TV discover player, mobile player, and local-download player; a bootstrap/backend fix covers them without editing each call site.
- Package compatibility was revalidated against the current lockfile: resolved `video_player_media_kit 2.0.0`, `media_kit_libs_windows_video 1.0.11` alongside `video_player_platform_interface 6.9.0`; `flutter build windows` succeeded.
- The regression-tested helper accepts a synchronous callback because `VideoPlayerMediaKit.ensureInitialized(windows: true)` returns `void`; the Windows plugin is registered by Flutter's generated Windows registrar.
- The user's newest Embed69 trace confirms that MediaKit is initialized and receives a D3D texture, then reports an initial `0x0` output rectangle. The earlier diagnosis says this is consistent with the Windows hardware texture path, but the trace alone does not establish whether the rectangle later becomes nonzero. Historical authorized mitigation is to disable hardware acceleration for Windows only via the MediaKit video controller configuration; this may increase CPU use.
- VPW-2 implementation/build evidence: the MediaKit adapter's `VideoController` is now configured with acceleration disabled only on Windows. Focused rendering/backend tests pass 4/4, six-file analyzer is clean, and the Windows Release build succeeds. The local 2.0.0 adapter copy preserves its upstream licensing files. The `.gitignore` is also modified in the worktree but was not part of this task's edits and must remain excluded/preserved unless independently authorized.

## Next step
Commit VPW-2 as a work unit and record its RDD outcome; obtain explicit user consent before starting the due native review. Ask the user to rerun the URL and confirm that a visible frame appears; keep visual resolution pending until then.

## Relevant files
- `lib/main.dart` — app startup, where Windows backend should initialize before `runApp`.
- `pubspec.yaml`, `pubspec.lock` — current video_player dependencies.
- `test/` — add focused bootstrap regression coverage.
- `windows/flutter/generated_plugin_registrant.cc` — confirm any required Windows native registration.
- `packages/video_player_media_kit/` — candidate license-preserving local adapter fork if no configuration hook exists upstream.
- `test/core/video_player_rendering_config_test.dart` — candidate regression test for platform-specific rendering policy.
