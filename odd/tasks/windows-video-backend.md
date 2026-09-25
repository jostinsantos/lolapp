# Windows video_player backend

## Objective
Make existing video_player-based player screens initialize and play on Windows.

## Problem and why
On Windows, player screens fail with `UnimplementedError: init() has not been implemented.` The running code uses `video_player`, but no Windows-capable platform backend is declared or initialized. This is the next runtime blocker while getting the Windows build operational.

## Scope and constraints
- Add a Windows-compatible video_player backend and initialize it before `runApp`, only when running on Windows; retain existing Android/iOS/web implementations.
- Cover the platform-specific bootstrap behavior with focused regression tests and build Windows.
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

## Progress
- Read-only mapping confirms `video_player_platform_interface 6.9.0` itself throws the exact reported error from its default `VideoPlayerPlatform.init()` when no implementation is registered.
- `lib/main.dart` calls `WidgetsFlutterBinding.ensureInitialized()` then app setup and `runApp`, but never registers a Windows backend.
- `pubspec.yaml` contains only `video_player`; lockfile includes Android, AVFoundation, and web implementations but no Windows backend. Windows generated registrar similarly contains no native video plugin.
- Existing player implementations use `VideoPlayerController.networkUrl(...).initialize()` in the general player, TV player, TV discover player, mobile player, and local-download player; a bootstrap/backend fix covers them without editing each call site.
- Package compatibility was revalidated against the current lockfile: resolved `video_player_media_kit 2.0.0`, `media_kit_libs_windows_video 1.0.11` alongside `video_player_platform_interface 6.9.0`; `flutter build windows` succeeded.
- The regression-tested helper accepts a synchronous callback because `VideoPlayerMediaKit.ensureInitialized(windows: true)` returns `void`; the Windows plugin is registered by Flutter's generated Windows registrar.

## Next step
Obtain explicit user consent before starting the due native review of the accumulated branch range. After the review boundary is resolved, keep manual stream-playback confirmation explicitly pending unless the user's actual Windows app is exercised.

## Relevant files
- `lib/main.dart` — app startup, where Windows backend should initialize before `runApp`.
- `pubspec.yaml`, `pubspec.lock` — current video_player dependencies.
- `test/` — add focused bootstrap regression coverage.
- `windows/flutter/generated_plugin_registrant.cc` — confirm any required Windows native registration.
